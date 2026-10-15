// Profiles (sets of enabled mods) and My Collections (exportable mod lists).

/// The Nexus collection a profile was made from.
struct ProfileCollection: Codable, Equatable {
    let slug: String
    let name: String
}

import AppKit
import ModManagerCore
import SwiftUI

extension AppModel {
    // MARK: Profiles
    //
    // One profile is always in use. Turning mods on or off updates it, so
    // switching to another profile and back returns to exactly that set.

    /// The enabled mods' UniqueIDs.
    private var enabledUniqueIDs: [String] {
        mods.filter { $0.isEnabled && !$0.uniqueID.isEmpty }.map(\.uniqueID)
    }

    /// Makes sure a profile is in use: the remembered one, else one that
    /// matches the enabled mods, else a new "Default" made from them.
    func ensureActiveProfile() {
        guard manager != nil else { return }
        if let activeProfile, profiles[activeProfile] != nil { return }
        let current = Set(enabledUniqueIDs.map { $0.lowercased() })
        if let match = profileNames.first(where: { Set((profiles[$0] ?? []).map { $0.lowercased() }) == current }) {
            activeProfile = match
            return
        }
        var name = String(localized: "Default")
        var counter = 2
        while profiles[name] != nil {
            name = String(localized: "Default \(counter)")
            counter += 1
        }
        profiles[name] = enabledUniqueIDs
        persistProfiles()
        activeProfile = name
    }

    /// Records the enabled mods in the profile in use. Mods the profile
    /// lists that aren't installed stay in it; a broken-mod search's
    /// temporary changes aren't recorded.
    func trackActiveProfile() {
        guard manager != nil, bisection == nil, let name = activeProfile, let saved = profiles[name] else { return }
        let installed = Set(mods.map { $0.uniqueID.lowercased() })
        let notInstalled = saved.filter { !installed.contains($0.lowercased()) }
        let updated = enabledUniqueIDs + notInstalled
        guard Set(updated.map { $0.lowercased() }) != Set(saved.map { $0.lowercased() }) else { return }
        profiles[name] = updated
        persistProfiles()
    }

    /// Switches to another profile: turns its mods on and the others off.
    /// The current profile already holds its mods, so nothing is lost.
    func switchProfile(to name: String) {
        guard let ids = profiles[name], name != activeProfile else { return }
        guard !isGameRunning else {
            return show("Stardew Valley Is Running", "Quit the game first: mods are only loaded when it starts.")
        }
        activeProfile = name
        applyEnabledSet(ids, title: String(localized: "profile “\(name)”"), undoable: false)
    }

    /// A new profile, put in use: with the mods enabled now, or with none
    /// but SMAPI's own (Console Commands, Save Backup), which then turns
    /// every other mod off.
    func createProfile(named rawName: String, empty: Bool = false) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, profiles[name] == nil else { return }
        if empty {
            guard !isGameRunning else {
                return show("Stardew Valley Is Running", "Quit the game first: mods are only loaded when it starts.")
            }
            let smapiMods = mods.filter { $0.uniqueID.lowercased().hasPrefix("smapi.") }.map(\.uniqueID)
            profiles[name] = smapiMods
            persistProfiles()
            activeProfile = name
            applyEnabledSet(smapiMods, title: String(localized: "profile “\(name)”"), undoable: false)
        } else {
            profiles[name] = enabledUniqueIDs
            persistProfiles()
            activeProfile = name
        }
    }

    func renameProfile(_ old: String, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != old, profiles[name] == nil, let ids = profiles[old] else { return }
        profiles[name] = ids
        profiles[old] = nil
        persistProfiles()
        if activeProfile == old { activeProfile = name }
        if let collection = profileCollections.removeValue(forKey: old) { profileCollections[name] = collection }
        // Saves played with this profile keep using it.
        for (save, modSet) in saveLinks where modSet.kind == .profile && modSet.name == old {
            link(saveID: save, to: SaveModSet(kind: .profile, name: name))
        }
    }

    /// Deletes a profile (not its mods). Deleting the one in use puts
    /// another in use, or a new Default.
    func deleteProfile(named name: String) {
        profiles[name] = nil
        profileCollections[name] = nil
        persistProfiles()
        if activeProfile == name {
            activeProfile = nil
            ensureActiveProfile()
        }
    }

    /// Enables exactly the given UniqueIDs and disables every other mod that
    /// has one. Mods without a UniqueID (no/broken manifest) are left alone.
    func applyEnabledSet(_ ids: [String], title: String, undoable: Bool = true) {
        guard manager != nil else { return }
        let wanted = Set(ids.map { $0.lowercased() })
        let withIDs = mods.filter { !$0.uniqueID.isEmpty }
        if undoable {
            registerEnabledUndo(before: enabledSnapshot, actionName: String(localized: "Apply \(title)"))
        }
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

    /// Opens the Nexus collection a profile came from (to add its optional mods).
    func showCollection(forProfile name: String) {
        guard let collection = profileCollections[name] else { return }
        collectionSheet = CollectionSheetRequest(slug: collection.slug)
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
        panel.message = String(localized: "Choose a mod list exported from Starseed")
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

    /// Writes the list's mod settings (config.json) over the installed ones
    /// that differ. The previous files are kept as config.json.bak.
    func applySettings(from list: ModList) {
        guard !isGameRunning else {
            return show("Quit Stardew Valley First", "Mods read their settings when the game starts, and the game may overwrite them while it runs.")
        }
        var applied = 0
        var failures: [String] = []
        for change in list.settingsChanges(for: mods) {
            do {
                try ModList.apply(settings: change.settings, to: change.mod)
                applied += 1
            } catch {
                failures.append("\(change.mod.displayName): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            show("Some Settings Weren't Applied", detail: failures.joined(separator: "\n"))
        }
        if applied > 0 {
            showStatusResult(String(localized: "Applied the collection's settings to \(applied) mod(s). The previous ones are kept as config.json.bak."))
        }
    }

    /// Enables exactly the mods the list had enabled, like a profile.
    func apply(_ list: ModList) {
        applyEnabledSet(list.mods.filter(\.enabled).map(\.uniqueID), title: String(localized: "collection “\(list.name)”"))
    }
}
