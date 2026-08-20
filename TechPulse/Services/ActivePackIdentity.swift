import Foundation

/// Which Pack is active, remembered outside the store.
///
/// The `InstalledPack` row is the only thing that says which Pack a reader is
/// on, and it used to be the only copy. When Siri's weekly intent opened the
/// store with a schema that did not name `InstalledPack`, SwiftData dropped the
/// table and took the answer with it (#21) — the Concepts, the Mastery and the
/// history all survived, so the reader kept their map and lost its name, and
/// launch handed them the flagship instead (#37).
///
/// Two strings in `UserDefaults` are enough to give the name back, and they
/// live where a store migration cannot reach them. This is what the app knows
/// about the Pack without opening the store; the record is still the Pack.
@MainActor
enum ActivePackIdentity {
    private static let fieldKey = "activePackField"
    private static let originKey = "activePackOrigin"
    private static let builtinFileKey = "activePackBuiltinFile"

    /// What survives when the record does not: the Pack's field, where it came
    /// from, and — for a Pack that shipped with the app — which file it was.
    struct Remembered: Equatable {
        let field: String
        let origin: PackOrigin
        /// The built-in Pack file this reader is on. What rebuilds the right
        /// Pack when the field it was remembered under has since been rewritten
        /// (#19). Nil for a Pack of the reader's own, and for a built-in
        /// remembered before this was written down.
        let builtinFileName: String?
    }

    /// Called by every install, so the answer is never older than the Pack.
    ///
    /// The file name is cleared rather than left when there is none: a reader
    /// who moves from a built-in to a Pack of their own must not keep the file
    /// name of the Pack they left.
    static func remember(field: String, origin: PackOrigin, builtinFileName: String? = nil) {
        UserDefaults.standard.set(field, forKey: fieldKey)
        UserDefaults.standard.set(origin.rawValue, forKey: originKey)
        if let builtinFileName {
            UserDefaults.standard.set(builtinFileName, forKey: builtinFileKey)
        } else {
            UserDefaults.standard.removeObject(forKey: builtinFileKey)
        }
    }

    /// Nil on a device that has never installed a Pack — a fresh install, and
    /// every store damaged before this shipped.
    static var recalled: Remembered? {
        guard let field = UserDefaults.standard.string(forKey: fieldKey), !field.isEmpty
        else { return nil }
        let origin = UserDefaults.standard.string(forKey: originKey)
            .flatMap(PackOrigin.init(rawValue:)) ?? .imported
        let fileName = UserDefaults.standard.string(forKey: builtinFileKey)
        return Remembered(field: field, origin: origin,
                          builtinFileName: fileName.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// For tests, which share one process across stores.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: fieldKey)
        UserDefaults.standard.removeObject(forKey: originKey)
        UserDefaults.standard.removeObject(forKey: builtinFileKey)
    }
}
