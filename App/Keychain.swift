import Foundation
import Security

/// Stores the user's personal Nexus Mods API key in the login Keychain.
enum Keychain {
    private static let service = "local.stardew-mod-manager.nexus"
    private static let account = "api-key"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func readNexusAPIKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveNexusAPIKey(_ key: String) throws {
        deleteNexusAPIKey()
        var item = baseQuery
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrLabel as String] = "Stardew Mod Manager – Nexus Mods API key"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? String(localized: "Keychain error \(status)"),
            ])
        }
    }

    static func deleteNexusAPIKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
