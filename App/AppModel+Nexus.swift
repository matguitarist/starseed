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
            accountListsLoaded = false
        } catch {
            nexusAccount = .invalid(error.localizedDescription)
        }
    }

    // MARK: Endorse & track


    /// Loads your endorsements and tracked mods, once per key, when Endorse
    /// and Track buttons first appear.
    func loadNexusAccountLists() async {
        guard nexusAccount.user != nil, !accountListsLoaded else { return }
        accountListsLoaded = true
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

    /// UniqueIDs of the installed mods that belong to a collection, with
    /// every part of a multi-part mod (only one part may carry the Nexus number).
    func installedUniqueIDs(for collectionMods: [CollectionMod]) -> [String] {
        let nexusIDs = Set(collectionMods.map(\.modID))
        var result: [String] = []
        var seen = Set<String>()
        for mod in mods where nexusID(for: mod).map(nexusIDs.contains) ?? false {
            for part in group(containing: mod)?.mods ?? [mod] where !part.uniqueID.isEmpty {
                if seen.insert(part.uniqueID.lowercased()).inserted { result.append(part.uniqueID) }
            }
        }
        return result
    }

    /// Puts a profile named after the collection in use, with only the
    /// collection's installed mods (and SMAPI's own) on. Mods installed next
    /// are enabled, so they join it. An existing profile of that name keeps
    /// its mods and gains the collection's.
    func useCollectionProfile(_ revision: CollectionRevision, mods collectionMods: [CollectionMod]) {
        guard !isGameRunning else {
            return show("Stardew Valley Is Running", "Quit the game first: mods are only loaded when it starts.")
        }
        let name = revision.collection.name
        let smapiMods = mods.filter { $0.uniqueID.lowercased().hasPrefix("smapi.") }.map(\.uniqueID)
        var ids = profiles[name] ?? []
        for id in smapiMods + installedUniqueIDs(for: collectionMods)
        where !ids.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) {
            ids.append(id)
        }
        profiles[name] = ids
        persistProfiles()
        activeProfile = name
        applyEnabledSet(ids, title: String(localized: "profile “\(name)”"), undoable: false)
    }
}
