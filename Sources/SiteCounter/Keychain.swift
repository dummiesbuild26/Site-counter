import Foundation
import Security

/// Stores the Cloudflare API token in the macOS login keychain.
enum Keychain {
    private static let service = "SiteCounter.CloudflareAPIToken"
    private static let account = "default"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func readToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveToken(_ token: String) {
        SecItemDelete(baseQuery as CFDictionary)
        guard !token.isEmpty else { return }
        var query = baseQuery
        query[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }
}
