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
        if let match = ProfileRules.matching(profiles, enabled: enabledUniqueIDs) {
            activeProfile = match
            return
        }
        let name = ProfileRules.uniqueName(String(localized: "Default"), taken: { self.profiles[$0] != nil },
                                           numbered: { String(localized: "Default \($0)") })
        profiles[name] = enabledUniqueIDs
        persistProfiles()
        activeProfile = name
    }

    /// Records the enabled mods in the profile in use. Mods the profile
    /// lists that aren't installed stay in it; a broken-mod search's
    /// temporary changes aren't recorded.
    func trackActiveProfile() {
        guard manager != nil, bisection == nil, let name = activeProfile, let saved = profiles[name],
              let updated = ProfileRules.tracked(saved: saved, enabled: enabledUniqueIDs, installed: Set(mods.map(\.uniqueID)))
        else { return }
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
            let smapiMods = ProfileRules.smapiBundled(mods.map(\.uniqueID))
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
        // Its saves go back to "any mods".
        for (save, modSet) in saveLinks where modSet.kind == .profile && modSet.name == name {
            link(saveID: save, to: nil)
        }
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

    // MARK: Export and import
    //
    // A profile travels as a mod list file (.json): its mods with versions,
    // Nexus numbers and settings. Files from the old My Collections import too.

    func exportProfile(named name: String) {
        guard let ids = profiles[name] else { return }
        let wanted = Set(ids.map { $0.lowercased() })
        let inProfile = mods.filter { wanted.contains($0.uniqueID.lowercased()) }
        var list = ModList.snapshot(
            name: name,
            of: inProfile,
            nexusID: { self.nexusID(for: $0) },
            gameVersion: gameVersion?.description,
            smapiVersion: smapi?.version?.description
        )
        // The profile's view of each mod: on, whatever its state right now.
        list.mods = list.mods.map { entry in var entry = entry; entry.enabled = true; return entry }
        // Mods the profile lists that aren't installed here travel too.
        let installed = Set(mods.map { $0.uniqueID.lowercased() })
        for id in ids where !installed.contains(id.lowercased()) && !id.lowercased().hasPrefix("smapi.") {
            list.mods.append(ModListEntry(name: id, uniqueID: id, version: "", author: nil, nexusID: nil, enabled: true))
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = list.suggestedFileName
        panel.allowedContentTypes = [.json]
        panel.message = String(localized: "Export “\(name)” to share it or use it on another Mac")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try list.encoded().write(to: url, options: .atomic)
            showStatusResult(String(localized: "Exported “\(name)” (\(list.mods.count) mods)."))
        } catch {
            show("Export Failed", detail: error.localizedDescription)
        }
    }

    /// Imports a profile file: a new profile, put in use; missing mods are
    /// downloaded into it and its saved settings applied (previous settings
    /// kept as config.json.bak).
    func importProfile() {
        guard !isGameRunning else {
            return show("Stardew Valley Is Running", "Quit the game first: mods are only loaded when it starts.")
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = String(localized: "Choose a profile exported from Starseed")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let list: ModList
        do {
            list = try ModList.decode(from: Data(contentsOf: url))
        } catch {
            return show("Import Failed", detail: error.localizedDescription)
        }
        let name = ProfileRules.uniqueName(list.name, taken: { self.profiles[$0] != nil },
                                           numbered: { String(localized: "\(list.name) \($0)") })
        let ids = ProfileRules.merged(ProfileRules.smapiBundled(mods.map(\.uniqueID)), adding: list.mods.filter(\.enabled).map(\.uniqueID))
        profiles[name] = ids
        persistProfiles()
        activeProfile = name
        applyEnabledSet(ids, title: String(localized: "profile “\(name)”"), undoable: false)
        applySettings(from: list)
        installMissing(from: list)
        showStatusResult(String(localized: "Imported profile “\(name)”. Missing mods download into it."))
    }

    /// One-time move of the old My Collections lists into profiles (same
    /// name and mods), relinking saves that used them. The files stay.
    func migrateModListsToProfiles() {
        let key = "migratedModListsToProfiles"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        defer { UserDefaults.standard.set(true, forKey: key) }
        var changed = false
        for list in modListStore.list() {
            let ids = list.mods.filter(\.enabled).map(\.uniqueID)
            var name = list.name
            if let existing = profiles[name], Set(existing.map { $0.lowercased() }) == Set(ids.map { $0.lowercased() }) {
                // Already there.
            } else {
                name = ProfileRules.uniqueName(list.name, taken: { self.profiles[$0] != nil },
                                               numbered: { String(localized: "\(list.name) \($0)") })
                profiles[name] = ids
                changed = true
            }
            for (save, modSet) in saveLinks where modSet.kind == .collection && modSet.name == list.name {
                link(saveID: save, to: SaveModSet(kind: .profile, name: name))
            }
        }
        if changed { persistProfiles() }
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
            showStatusResult(String(localized: "Applied the profile's settings to \(applied) mod(s). The previous ones are kept as config.json.bak."))
        }
    }

}
