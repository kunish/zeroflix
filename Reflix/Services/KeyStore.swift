import Foundation

/// Small persistence helpers: the TMDB key in UserDefaults, the auth session
/// in the Keychain.
enum KeyStore {
    private static let defaults = UserDefaults.standard
    private static let tmdbKeyName = "reflix_tmdb_key"

    static var tmdbKey: String {
        get { defaults.string(forKey: tmdbKeyName) ?? AppConfig.tmdbDefaultKey }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                defaults.removeObject(forKey: tmdbKeyName)
            } else {
                defaults.set(trimmed, forKey: tmdbKeyName)
            }
        }
    }

    static var hasCustomTMDBKey: Bool {
        defaults.string(forKey: tmdbKeyName) != nil
    }
}

/// Minimal Keychain wrapper for the Supabase session blob.
enum Keychain {
    private static let account = "reflix.supabase.session"
    private static let service = "com.kunish.reflix"

    static func save(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
