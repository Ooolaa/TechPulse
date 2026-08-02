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
    /// Runs on every launch and is idempotent. Three cases, one code path:
    ///
    /// - **Fresh install** — no Concepts, no Pack. Installing creates the map.
    /// - **Existing install from before Packs were data** — Concepts exist with
    ///   Mastery on them, but no `InstalledPack` record. Installing over the
    ///   top adopts them: `PackInstaller` matches by name and keeps Mastery,
    ///   Lit state and `lastReviewed`, so the reader's map is exactly as they
    ///   left it. `LearningEvent` rows are keyed by Concept name and are never
    ///   touched, so history and Streak survive untouched.
    /// - **Already migrated** — an active Pack of the current version. Nothing
    ///   happens.
    static func ensureBuiltinInstalled(context: ModelContext) {
        // `install` refreshes, but the common launch installs nothing at all
        // and must still end up with the engines pointed at the stored Pack.
        defer { ActivePack.refresh(context: context) }

        let installed = UserDefaults.standard.integer(forKey: installedVersionKey)
        let hasActivePack = ActivePack.load(context: context) != nil
        guard !hasActivePack || installed < builtinPackVersion else { return }

        do {
            try PackInstaller.install(try BuiltinPacks.aiEngineer(),
                                      origin: "builtin", context: context)
            UserDefaults.standard.set(builtinPackVersion, forKey: installedVersionKey)
        } catch {
            // A broken built-in Pack is a broken build, but crashing a
            // returning reader's launch over it would be worse than opening
            // on the map they already have.
            assertionFailure("built-in pack failed to install: \(error)")
        }
    }
}
