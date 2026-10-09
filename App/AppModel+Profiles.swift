// Profiles (sets of enabled mods) and My Collections (exportable mod lists).

import AppKit
import ModManagerCore
import SwiftUI

extension AppModel {
    // MARK: Profiles

    func saveProfile(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        profiles[name] = mods.filter { $0.isEnabled && !$0.uniqueID.isEmpty }.map(\.uniqueID)
        persistProfiles()
    }

    func deleteProfile(named name: String) {
        profiles[name] = nil
        persistProfiles()
    }

    /// Enable exactly the profile's mods and disable everything else. Mods
    /// without a UniqueID (no/broken manifest) are left alone.
    func applyProfile(named name: String) {
        guard let ids = profiles[name] else { return }
        applyEnabledSet(ids, title: String(localized: "profile “\(name)”"))
    }

    /// Enables exactly the given UniqueIDs and disables every other mod that
    /// has one. Mods without a UniqueID (no/broken manifest) are left alone.
    func applyEnabledSet(_ ids: [String], title: String) {
        guard manager != nil else { return }
        let wanted = Set(ids.map { $0.lowercased() })
        let withIDs = mods.filter { !$0.uniqueID.isEmpty }
        // Disable first, then enable (enabling may rename folders).
        var failures = toggle(withIDs.filter { !wanted.contains($0.uniqueID.lowercased()) }, to: false)
        failures += toggle(withIDs.filter { wanted.contains($0.uniqueID.lowercased()) }, to: true)

        let installedIDs = Set(mods.map { $0.uniqueID.lowercased() })
        let notInstalled = ids.filter { !installedIDs.contains($0.lowercased()) }

        selection = []
        refresh()

        var lines = [String(localized: "Applied \(title).")]
        if !notInstalled.isEmpty { lines.append(String(localized: "Not installed: \(notInstalled.joined(separator: ", "))")) }
        if !failures.isEmpty { lines.append(String(localized: "Couldn't toggle:\n\(failures.joined(separator: "\n"))")) }
        if lines.count > 1 { show("Profile Applied", detail: lines.joined(separator: "\n\n")) }
    }

    func persistProfiles() {
        do {
            try configStore.saveProfiles(profiles)
        } catch {
            show("Couldn't save profiles", detail: error.localizedDescription)
        }
    }

    // MARK: My Collections (mod lists)


    func loadModLists() {
        modLists = modListStore.list()
    }

    /// Saves the installed mods as a named list (replacing one with that name).
    @discardableResult
    func saveCurrentMods(as rawName: String) -> ModList? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let list = ModList.snapshot(
            name: name,
            of: mods,
            nexusID: { self.nexusID(for: $0) },
            gameVersion: smapi?.gameVersion?.description,
            smapiVersion: smapi?.version?.description
        )
        return store(list)
    }

    @discardableResult
    func store(_ list: ModList) -> ModList? {
        do {
            try modListStore.save(list)
            loadModLists()
            return list
        } catch {
            show("Couldn't Save Collection", detail: error.localizedDescription)
            return nil
        }
    }

    func deleteModList(_ list: ModList) {
        try? modListStore.delete(list)
        loadModLists()
    }

    func exportModList(_ list: ModList) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = list.suggestedFileName
        panel.allowedContentTypes = [.json]
        panel.message = String(localized: "Export “\(list.name)” to share it or use it on another computer")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try list.encoded().write(to: url, options: .atomic)
        } catch {
            show("Export Failed", detail: error.localizedDescription)
        }
    }

    /// Imports a mod list file and keeps a copy in My Collections.
    func importModList() -> ModList? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = String(localized: "Choose a mod list exported from Stardew Mod Manager")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            var list = try ModList.decode(from: Data(contentsOf: url))
            // Don't silently replace a different list that has the same name.
            if modLists.contains(where: { $0.name == list.name && $0 != list }) {
                list.name += " " + String(localized: "(imported)")
            }
            return store(list)
        } catch {
            show("Import Failed", detail: error.localizedDescription)
            return nil
        }
    }

    /// Downloads mods from a list that are missing or older here. Entries
    /// without a Nexus number are looked up via SMAPI's database, then Nexus.
    func installMissing(from list: ModList) {
        let entries = list.mods.filter {
            switch ModListEntryState.of($0, in: mods) {
            case .missing, .olderInstalled: true
            default: false
            }
        }
        guard !entries.isEmpty else { return }
        let client = nexusClient
        Task {
            var requests: [NexusInstallRequest] = []
            var unknown: [String] = []
            let lookups = (try? await UpdateChecker().lookup(uniqueIDs: entries.filter { $0.nexusID == nil }.map(\.uniqueID))) ?? [:]
            for entry in entries {
                var nexusID = entry.nexusID ?? lookups[entry.uniqueID.lowercased()]?.nexusID
                if nexusID == nil {
                    nexusID = try? await client.findMod(forUniqueID: entry.uniqueID)?.modID
                }
                if let nexusID {
                    requests.append(NexusInstallRequest(modID: nexusID, title: entry.name, version: entry.version))
                } else {
                    unknown.append(entry.name)
                }
            }
            // Several entries (e.g. a mod's [CP] and code parts) can share one Nexus page.
            var seen = Set<Int>()
            queueNexusInstalls(requests.filter { seen.insert($0.modID).inserted })
            if !unknown.isEmpty {
                show("Some Mods Aren't on Nexus", "Couldn't find a Nexus page for:\n\n\(unknown.joined(separator: "\n"))")
            }
        }
    }

    /// Enables exactly the mods the list had enabled, like a profile.
    func apply(_ list: ModList) {
        applyEnabledSet(list.mods.filter(\.enabled).map(\.uniqueID), title: String(localized: "collection “\(list.name)”"))
    }
}
