import Foundation

/// Packs that ship inside the app.
///
/// A built-in Pack is an ordinary Pack file that happens to travel in the app
/// bundle — read from disk and validated on the same path as one a reader was
/// given, so the flagship gets no privileges an imported Pack lacks. Nothing
/// here touches the network: the app opens with a map on a plane.
enum BuiltinPacks {

    /// Identifies the bundle holding the Pack files. Needed because the unit
    /// tests load this code out of the app bundle rather than their own.
    private final class BundleToken {}

    /// The flagship: the AI Engineer map the app shipped with.
    static let aiEngineerFileName = "ai-engineer"

    /// The second field the app covers out of the box.
    static let securityEngineeringFileName = "security-engineering"

    /// Every Pack file shipped in the app, by file name, in the order they are
    /// offered to the reader. The flagship comes first.
    static let fileNames = [aiEngineerFileName, securityEngineeringFileName]

    /// A Pack file shipped in the app, read and checked, ready to install.
    struct Builtin: Equatable, Sendable {
        let fileName: String
        let pack: PackFile
    }

    /// Every built-in Pack, in offer order.
    ///
    /// Loaded once: the Pack chooser reads this from a view body, and a decode
    /// per redraw would be paid for nothing. A file that fails to load is left
    /// out rather than taking the rest down — one broken Pack in a build
    /// should not cost the reader the Packs that are fine.
    static let all: [Builtin] = fileNames.compactMap { fileName in
        do {
            return Builtin(fileName: fileName, pack: try load(fileName))
        } catch {
            assertionFailure("built-in pack “\(fileName)” failed to load: \(error)")
            return nil
        }
    }

    /// Reads and validates a built-in Pack.
    ///
    /// Throws rather than returning nil: a built-in Pack failing to load is a
    /// broken build, and the reason is worth surfacing rather than swallowing.
    static func load(_ fileName: String) throws -> PackFile {
        // Resources are flattened into the bundle root, so the on-disk
        // Resources/Packs/ grouping is for humans, not for lookup.
        guard let url = Bundle(for: BundleToken.self)
            .url(forResource: fileName, withExtension: "json")
        else {
            throw PackValidationError.unreadable("“\(fileName).json” is not in the app bundle")
        }
        return try PackValidator.decodeAndValidate(Data(contentsOf: url))
    }

    static func aiEngineer() throws -> PackFile {
        try load(aiEngineerFileName)
    }

    /// The flagship as something installable: its Pack alongside the file name
    /// that keeps it on the update path.
    ///
    /// Read rather than taken from `all`, which leaves out a file that failed
    /// to load — the fallback every lost reader lands on should throw the
    /// reason rather than quietly not being there.
    static func aiEngineerBuiltin() throws -> Builtin {
        Builtin(fileName: aiEngineerFileName, pack: try aiEngineer())
    }

    /// The built-in shipped under this file name, if this build ships one.
    static func named(_ fileName: String) -> Builtin? {
        all.first { $0.fileName == fileName }
    }

    /// The built-in Pack a stored record is the app's copy of, if it is one.
    ///
    /// Matched on file name, which the app controls. Matching on `field` — copy
    /// the Pack's author may rewrite — meant a rename ended that reader's
    /// built-in Pack updates for good, because nothing would ever recognise
    /// their record again (#19).
    static func matching(_ record: InstalledPack) -> Builtin? {
        guard record.packOrigin == .builtin else { return nil }
        return matching(fileName: record.builtinFileName, field: record.field)
    }

    /// The same question asked of what survives outside the store (#37), so a
    /// reader whose record was destroyed is rebuilt onto the Pack they were on
    /// rather than the flagship, however its field reads by then.
    @MainActor
    static func matching(_ remembered: ActivePackIdentity.Remembered) -> Builtin? {
        guard remembered.origin == .builtin else { return nil }
        return matching(fileName: remembered.builtinFileName, field: remembered.field)
    }

    /// File name, then field — one rule, so the two callers above cannot drift.
    ///
    /// The field is what answers for a Pack installed before the file name was
    /// stored: `PackMigration` recognises such a record the once and writes the
    /// file name onto it, after which the field is free to change. It is also
    /// the answer for a file name this build no longer ships, where the field
    /// is all that is left to go on — renaming a Pack *file* is a code change
    /// and not the reader-visible rewrite this all guards against, but a Pack
    /// that can still be recognised should be.
    private static func matching(fileName: String?, field: String) -> Builtin? {
        fileName.flatMap(named) ?? all.first { $0.pack.field == field }
    }
}
