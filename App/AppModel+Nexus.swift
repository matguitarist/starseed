// The Nexus account (API key), endorsements and tracking, and collections.

import ModManagerCore
import SwiftUI

extension AppModel {
    // MARK: Nexus account

    func setNexusAPIKey(_ rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try Keychain.saveNexusAPIKey(key)
        } catch {
            show("Couldn't save API key", detail: error.localizedDescription)
            return
        }
        nexusAPIKey = key
        await validateNexusKey()
    }

    func removeNexusAPIKey() {
        Keychain.deleteNexusAPIKey()
        nexusAPIKey = nil
        nexusAccount = .none
    }

    func validateNexusKey() async {
        guard nexusAPIKey != nil else {
            nexusAccount = .none
            return
        }
        nexusAccount = .checking
        do {
            nexusAccount = .signedIn(try await nexusClient.validateKey())
            await loadNexusAccountLists()
        } catch {
            nexusAccount = .invalid(error.localizedDescription)
        }
    }

    // MARK: Endorse & track


    /// Loads your endorsements and tracked mods (after the API key is verified).
    func loadNexusAccountLists() async {
        guard nexusAccount.user != nil else { return }
        let client = nexusClient
        async let endorsed = try? client.endorsements()
        async let tracked = try? client.trackedMods()
        if let value = await endorsed { endorsements = value }
        if let value = await tracked { trackedMods = value }
    }

    func setEndorsed(_ endorsed: Bool, modID: Int, version: String?) {
        Task {
            do {
                if endorsed {
                    try await nexusClient.endorse(modID: modID, version: version)
                    endorsements[modID] = .endorsed
                } else {
                    try await nexusClient.abstain(modID: modID, version: version)
                    endorsements[modID] = .abstained
                }
            } catch {
                show(endorsed ? "Couldn't Endorse" : "Couldn't Remove Endorsement", detail: Self.friendlyNexusMessage(error.localizedDescription))
            }
        }
    }

    func setTracked(_ tracked: Bool, modID: Int) {
        Task {
            do {
                if tracked {
                    try await nexusClient.track(modID: modID)
                    trackedMods.insert(modID)
                } else {
                    try await nexusClient.untrack(modID: modID)
                    trackedMods.remove(modID)
                }
            } catch {
                show("Couldn't Change Tracking", detail: Self.friendlyNexusMessage(error.localizedDescription))
            }
        }
    }

    /// Nexus answers with codes like "NOT_DOWNLOADED_MOD"; explain them.
    static func friendlyNexusMessage(_ message: String) -> String {
        switch message {
        case let m where m.contains("NOT_DOWNLOADED_MOD"):
            String(localized: "Nexus only lets you endorse mods you've downloaded with this account.")
        case let m where m.contains("TOO_SOON_AFTER_DOWNLOAD"):
            String(localized: "Nexus asks you to try a mod for a little while before endorsing it. Try again later.")
        case let m where m.contains("IS_OWN_MOD"):
            String(localized: "You can't endorse your own mod.")
        default:
            message
        }
    }

    // MARK: Collections

    enum CollectionModState: Equatable {
        case installed
        case olderInstalled(String)   // installed version is older than the collection's
        case newerInstalled(String)   // installed version is newer; kept by default
        case missing
    }

    func state(of collectionMod: CollectionMod) -> CollectionModState {
        guard let installed = installedMod(nexusID: collectionMod.modID) else { return .missing }
        guard let wanted = collectionMod.version.flatMap(SemanticVersion.init),
              let have = SemanticVersion(installed.version), have != wanted
        else { return .installed }
        return have < wanted ? .olderInstalled(installed.version) : .newerInstalled(installed.version)
    }

    func installCollection(_ mods: [CollectionMod]) {
        queueNexusInstalls(mods.map {
            NexusInstallRequest(modID: $0.modID, title: $0.modName, version: $0.version, fileID: $0.fileID)
        })
    }

    /// Saves a profile enabling exactly the installed mods from a collection.
    func saveProfile(fromCollection revision: CollectionRevision) -> Int {
        let nexusIDs = Set(revision.mods.map(\.modID))
        let ids = mods.filter { mod in nexusID(for: mod).map(nexusIDs.contains) ?? false }
            .map(\.uniqueID)
            .filter { !$0.isEmpty }
        profiles[revision.collection.name] = ids
        persistProfiles()
        return ids.count
    }
}
