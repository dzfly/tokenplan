import Foundation
import Security

enum TokenStore {
    private static let service = "com.tal.token-plan"
    private static let account = "jwt-token"
    private static let bearerPrefixKey = "auth-use-bearer-prefix"

    /// API 是否使用 `Bearer ` 前缀；登录验证时会自动探测
    static var useBearerPrefix: Bool {
        get {
            if UserDefaults.standard.object(forKey: bearerPrefixKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: bearerPrefixKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: bearerPrefixKey) }
    }

    static func save(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: bearerPrefixKey)
    }
}
