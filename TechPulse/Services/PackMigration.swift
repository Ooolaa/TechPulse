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
            guard let active = ActivePack.load(context: context) else {
                return try openOnTheRememberedPack(context: context)
            }
            // Only the built-in Pack the reader is on is refreshed, and a
            // built-in is found by its field: two of them never cover one.
            // Readers who upgrade into this build installed their Pack before
            // anything wrote the memory down; this is where they get one.
            ActivePackIdentity.remember(field: active.field, origin: active.origin)
            let installed = UserDefaults.standard.integer(forKey: installedVersionKey)
            guard installed < builtinPackVersion, active.origin == .builtin,
                  let current = BuiltinPacks.all.first(where: { $0.pack.field == active.field })
            else { return }
            try install(current.pack, context: context)
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
            return try install(BuiltinPacks.aiEngineer(), context: context)
        }
        // The record may be intact and merely not active — a Pack switch that
        // did not finish, say. Nothing was lost, so nothing needs rebuilding.
        let stored = (try? context.fetch(FetchDescriptor<InstalledPack>())) ?? []
        if let intact = stored.filter({ $0.field == remembered.field })
            .max(by: { $0.installedAt < $1.installedAt }) {
            return try PackInstaller.reactivate(intact, context: context)
        }
        // A built-in ships with the app, so it comes back whole — Stages,
        // specialty Cluster, suggested Sources and all.
        if remembered.origin == .builtin {
            let builtin = BuiltinPacks.all.first { $0.pack.field == remembered.field }
            // A built-in whose field no longer ships cannot be rebuilt as one:
            // the version bump finds a built-in *by field*, so a record naming
            // a Pack no build has could never be updated again. The flagship is
            // the honest answer, and it is what this reader got before.
            return try install(builtin?.pack ?? BuiltinPacks.aiEngineer(), context: context)
        }
        // A Pack the reader brought or generated is not kept as a file, so it
        // cannot be reinstalled — but the map it made outlived it.
        if try PackInstaller.adoptSurvivingMap(remembered, context: context) != nil { return }
        // Nothing survived either: an empty store that remembers a Pack is a
        // reader who has been reset, not one who lost anything.
        try install(BuiltinPacks.aiEngineer(), context: context)
    }

    private static func install(_ pack: PackFile, context: ModelContext) throws {
        try PackInstaller.install(pack, origin: .builtin, context: context)
        UserDefaults.standard.set(builtinPackVersion, forKey: installedVersionKey)
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
