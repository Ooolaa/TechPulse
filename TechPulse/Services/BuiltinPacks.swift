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

    /// Every Pack file shipped in the app, by file name.
    static let fileNames = [aiEngineerFileName]

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
}
