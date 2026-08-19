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

    /// What survives when the record does not: the Pack's field and where it
    /// came from.
    struct Remembered: Equatable {
        let field: String
        let origin: PackOrigin
    }

    /// Called by every install, so the answer is never older than the Pack.
    static func remember(field: String, origin: PackOrigin) {
        UserDefaults.standard.set(field, forKey: fieldKey)
        UserDefaults.standard.set(origin.rawValue, forKey: originKey)
    }

    /// Nil on a device that has never installed a Pack — a fresh install, and
    /// every store damaged before this shipped.
    static var recalled: Remembered? {
        guard let field = UserDefaults.standard.string(forKey: fieldKey), !field.isEmpty
        else { return nil }
        let origin = UserDefaults.standard.string(forKey: originKey)
            .flatMap(PackOrigin.init(rawValue:)) ?? .imported
        return Remembered(field: field, origin: origin)
    }

    /// For tests, which share one process across stores.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: fieldKey)
        UserDefaults.standard.removeObject(forKey: originKey)
    }
}
