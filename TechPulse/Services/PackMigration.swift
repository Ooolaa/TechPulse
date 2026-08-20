import Foundation
import SwiftData

/// Gets a reader onto an installed Pack, whether they are new or have been
/// using the app since before Packs were data.
@MainActor
enum PackMigration {

    /// Which built-in Pack file the app last installed. Bumping the Pack file
    /// means bumping this, and the reinstall delivers the new Concepts —
    /// the role `KnowledgePack.packVersion` used to play for compiled seeding.
    private static let installedVersionKey = "builtinPackVersion"
    static let builtinPackVersion = 1

    /// Ensures the reader has an active Pack.
    ///
    /// Runs on every launch and is idempotent. Three cases:
    ///
    /// - **Fresh install** — no Concepts, no Pack. Installing creates the map.
    /// - **Existing install from before Packs were data** — Concepts exist with
    ///   Mastery on them, but no `InstalledPack` record. Installing over the
    ///   top adopts them: `PackInstaller` matches by name and keeps Mastery,
    ///   Lit state and `lastReviewed`, so the reader's map is exactly as they
    ///   left it. `LearningEvent` rows are keyed by Concept name and are never
    ///   touched, so history and Streak survive untouched.
    /// - **A record that went missing** — the same shape as the case above, but
    ///   the reader was on a Pack the flagship would bury. Told apart by
    ///   `ActivePackIdentity`, which is written at install and outlives the
    ///   store (#37).
    /// - **Already migrated** — an active Pack of the current version. Nothing
    ///   happens.
    ///
    /// A reader who chose a Pack of their own keeps it. Launch only ever
    /// refreshes the built-in Pack they are actually on: replacing a chosen
    /// Pack with the flagship because the flagship's file moved on would take
    /// the map out from under them.
    static func ensureBuiltinInstalled(context: ModelContext) {
        // `install` refreshes, but the common launch installs nothing at all
        // and must still end up with the engines pointed at the stored Pack.
        defer { ActivePack.refresh(context: context) }

        do {
            guard let record = ActivePack.activeRecord(context: context) else {
                return try openOnTheRememberedPack(context: context)
            }
            // Only the built-in Pack the reader is on is refreshed, and which
            // one that is comes from `BuiltinPacks.matching` — by file name,
            // not by the field the reader sees (#19). A record from a build
            // that stored no file name is recognised by field this once and
            // adopted onto its file, so the field may move afterwards.
            let activeBuiltin = adoptBuiltinFileName(of: record, context: context)
            // Readers who upgrade into this build installed their Pack before
            // anything wrote the memory down; this is where they get one.
            ActivePackIdentity.remember(field: record.field, origin: record.packOrigin,
                                        builtinFileName: record.builtinFileName)
            let installed = UserDefaults.standard.integer(forKey: installedVersionKey)
            guard installed < builtinPackVersion, let activeBuiltin else { return }
            try installBuiltin(activeBuiltin, context: context)
        } catch {
            // A broken built-in Pack is a broken build, but crashing a
            // returning reader's launch over it would be worse than opening
            // on the map they already have.
            assertionFailure("built-in pack failed to install: \(error)")
        }
    }

    /// No record. Either this store never had one — a fresh install, or one
    /// from before Packs were data — or it lost the one it had.
    ///
    /// Nothing remembered means the first two, and the flagship is right for
    /// both: it creates the map, or it adopts the compiled Concepts already
    /// there by name. A remembered Pack means the third, and the flagship would
    /// bury a map the reader chose.
    private static func openOnTheRememberedPack(context: ModelContext) throws {
        guard let remembered = ActivePackIdentity.recalled else {
            return try installBuiltin(BuiltinPacks.aiEngineerBuiltin(), context: context)
        }
        // The record may be intact and merely not active — a Pack switch that
        // did not finish, say. Nothing was lost, so nothing needs rebuilding.
        // Recognised by file name where both sides have one, so a built-in
        // renamed since it was installed is still found; by field otherwise.
        let stored = (try? context.fetch(FetchDescriptor<InstalledPack>())) ?? []
        let sameFile = stored.filter {
            $0.builtinFileName != nil && $0.builtinFileName == remembered.builtinFileName
        }
        let candidates = sameFile.isEmpty ? stored.filter { $0.field == remembered.field }
                                          : sameFile
        if let intact = candidates.max(by: { $0.installedAt < $1.installedAt }) {
            return try PackInstaller.reactivate(intact, context: context)
        }
        // A built-in ships with the app, so it comes back whole — Stages,
        // specialty Cluster, suggested Sources and all. Which one it is comes
        // from the file name where there is one, so a reader whose Pack has
        // been renamed since gets their Pack back rather than the flagship.
        if remembered.origin == .builtin {
            // A Pack no build ships cannot be rebuilt as a built-in: nothing
            // would recognise the record again, so it could never be updated.
            // The flagship is the honest answer, and it is what this reader
            // got before.
            return try installBuiltin(BuiltinPacks.matching(remembered)
                                      ?? BuiltinPacks.aiEngineerBuiltin(),
                                      context: context)
        }
        // A Pack the reader brought or generated is not kept as a file, so it
        // cannot be reinstalled — but the map it made outlived it.
        if try PackInstaller.adoptSurvivingMap(remembered, context: context) != nil { return }
        // Nothing survived either: an empty store that remembers a Pack is a
        // reader who has been reset, not one who lost anything.
        try installBuiltin(BuiltinPacks.aiEngineerBuiltin(), context: context)
    }

    /// Installs a Pack that ships with the app.
    ///
    /// Every built-in install goes through here, wherever the reader chose it
    /// — launch, or picking one out of the library. Recording the version is
    /// why: a version left unrecorded has the next launch re-run a full install
    /// of the Pack the reader just installed, deleting and recreating every
    /// Dependency for nothing (#19).
    static func installBuiltin(_ builtin: BuiltinPacks.Builtin,
                               context: ModelContext) throws {
        try PackInstaller.install(builtin.pack, origin: .builtin,
                                  builtinFileName: builtin.fileName, context: context)
        UserDefaults.standard.set(builtinPackVersion, forKey: installedVersionKey)
    }

    /// The built-in Pack this record is the app's copy of, writing the file
    /// name onto a record that predates it.
    ///
    /// The write is the point: it happens whether or not there is anything to
    /// install, so the one field-based match each such record ever needs is
    /// spent on the launch after this ships — while the field still matches.
    ///
    /// Which is the one ordering rule this carries: **a built-in Pack's `field`
    /// must not be rewritten in the same build that first stores file names**,
    /// or a reader upgrading straight into that build has their single match
    /// tried against a field that has already moved, and is stranded by exactly
    /// the bug this closes. One shipped build apart is enough.
    private static func adoptBuiltinFileName(of record: InstalledPack,
                                             context: ModelContext) -> BuiltinPacks.Builtin? {
        guard let builtin = BuiltinPacks.matching(record) else { return nil }
        if record.builtinFileName != builtin.fileName {
            record.builtinFileName = builtin.fileName
            try? context.save()
        }
        return builtin
    }

    /// Gives an already-installed Pack the Semantic Links it never got.
    ///
    /// Semantic Links are computed *at install*, and the common launch installs
    /// nothing — so a reader already on the current Pack would never receive
    /// them, which is every store written before they existed. Without this the
    /// map opens as the unconnected dust the whole feature was meant to end,
    /// and only switching Packs would fix it.
    ///
    /// Runs at most once: it recomputes only when there are none at all, so a
    /// reader who has them pays nothing.
    static func ensureSemanticLinks(context: ModelContext) {
        guard let active = ActivePack.load(context: context),
              active.conceptNames.count > 1,
              ((try? context.fetch(FetchDescriptor<SemanticLink>())) ?? []).isEmpty
        else { return }

        // Definitions come from the store, which is where install put the
        // Pack's own — so the result matches what installing would have made.
        let members = Set(active.conceptNames)
        let byName = Dictionary(
            ((try? context.fetch(FetchDescriptor<Concept>())) ?? [])
                .filter { members.contains($0.name) }
                .map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first })
        let linkable = active.conceptNames.compactMap { name in
            byName[name].map { LinkableConcept(name: $0.name, definition: $0.conceptDefinition) }
        }
        PackInstaller.rebuildSemanticLinks(for: linkable, context: context)
        try? context.save()
    }
}
