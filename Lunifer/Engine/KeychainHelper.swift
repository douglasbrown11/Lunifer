import Foundation
import Security

// ─────────────────────────────────────────────────────────────
// KeychainHelper
// ─────────────────────────────────────────────────────────────
// Lightweight wrapper around Security framework for storing
// sensitive string values (OAuth tokens, etc.) in the keychain.
// Uses kSecClassGenericPassword with kSecAttrService = bundle ID.

enum KeychainHelper {

    private static let service: String = Bundle.main.bundleIdentifier ?? "com.lunifer.app"

    // MARK: - Save

    /// Saves (or updates) a string value for the given key.
    /// Overwrites any existing value.
    @discardableResult
    static func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Try to update an existing item first
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        // Item didn't exist — add it
        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    // MARK: - Load

    /// Retrieves the string value for the given key, or nil if not found.
    static func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    // MARK: - Delete

    /// Removes the value for the given key from the keychain.
    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - Keychain Keys

extension KeychainHelper {
    enum Keys {
        static let whoopAccessToken  = "whoop_access_token"
        static let whoopRefreshToken = "whoop_refresh_token"
    }
}
