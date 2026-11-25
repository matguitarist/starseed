import FileKit
import Foundation
import Security

/// Stores the user's personal Nexus Mods API key in the login Keychain.
enum Keychain {
    private static let store = FileKit.Keychain(service: "local.stardew-mod-manager.nexus", label: "Starseed – Nexus Mods API key")
    private static let account = "api-key"

    static func readNexusAPIKey() -> String? {
        store.string(for: account)
    }

    static func saveNexusAPIKey(_ key: String) throws {
        do {
            try store.set(key, for: account)
        } catch let failure as FileKit.Keychain.Failure {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(failure.status), userInfo: [
                NSLocalizedDescriptionKey: SecCopyErrorMessageString(failure.status, nil) as String? ?? String(localized: "Keychain error \(failure.status)"),
            ])
        }
    }

    static func deleteNexusAPIKey() {
        try? store.remove(account)
    }
}
