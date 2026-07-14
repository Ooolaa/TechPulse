import Foundation
import Security

/// API keys live in the iOS Keychain — never UserDefaults, never logged,
/// never synced anywhere by us (kSecAttrSynchronizable defaults to false).
enum KeychainStore {
    private static let service = "com.johnchen.TechPulse"

    @discardableResult
    static func save(_ value: String, account: String = "anthropic-api-key") -> Bool {
        saveStatus(value, account: account) == errSecSuccess
    }

    /// Returns the raw OSStatus so callers/tests can distinguish real failures
    /// from an entitlement-less environment (errSecMissingEntitlement, e.g.
    /// unsigned simulator test hosts).
    static func saveStatus(_ value: String, account: String = "anthropic-api-key") -> OSStatus {
        guard let data = value.data(using: .utf8) else { return errSecParam }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            return SecItemAdd(addQuery as CFDictionary, nil)
        }
        return updateStatus
    }

    static func read(account: String = "anthropic-api-key") -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(account: String = "anthropic-api-key") -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static var hasAnthropicKey: Bool { read() != nil }
}
