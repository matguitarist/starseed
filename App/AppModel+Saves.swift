// Save games: which mods they need, backups and restores, and the mod set
// each save is played with.

import AppKit
import CryptoKit
import ModManagerCore
import SwiftUI

extension AppModel {
    // MARK: Saves

    /// One mod a save depends on, found from its UniqueID in the save file.
    struct SaveModUse: Identifiable {
        let uniqueID: String
        let occurrences: Int
        var match: ModMatch?
        var installed: ModInfo?
        var id: String { uniqueID.lowercased() }
    }

    /// Missing content from the SMAPI log, with the mod it probably needs.
    struct SaveContentGap: Identifiable {
        let group: MissingContentGroup
        var match: ModMatch?
        var installed: ModInfo?
        var id: String { group.id }
    }

    struct SaveAnalysis {
        var mods: [SaveModUse] = []
        var unmatchedIDs: [String] = []
        var gaps: [SaveContentGap] = []
        /// Whether the latest SMAPI log is from loading this save.
        var logCoversSave = false
    }

    func link(saveID: String, to modSet: SaveModSet?) {
        saveLinks[saveID] = modSet
        do {
            try configStore.saveSaveLinks(saveLinks)
        } catch {
            show("Couldn't Save Link", detail: error.localizedDescription)
        }
    }

    /// After a session, links the saves played in it (new farms too) to the
    /// profile in use, so "Use Mods & Play" brings their mods back. Saves
    /// already linked keep their profile.
    func linkPlayedSaves(launchedAt launch: Date) {
        defer { savesRevision += 1 }
        guard let profile = activeProfile, profiles[profile] != nil else { return }
        let saves = SaveGame.list(in: backupStore.savesFolder)
        let ids = ProfileRules.savesToLink(saved: saves.map { ($0.id, $0.lastSaved) }, since: launch, linked: Set(saveLinks.keys))
        guard !ids.isEmpty else { return }
        for id in ids { saveLinks[id] = SaveModSet(kind: .profile, name: profile) }
        do {
            try configStore.saveSaveLinks(saveLinks)
        } catch {
            return show("Couldn't Save Link", detail: error.localizedDescription)
        }
        let farms = saves.filter { ids.contains($0.id) }.map { $0.farmName.isEmpty ? $0.id : String(localized: "\($0.farmName) Farm") }
        showStatusResult(String(localized: "\(farms.formatted(.list(type: .and))) now plays with the profile “\(profile)”. Change it in Saves."))
    }

    /// The profile a save is played with, when it still exists.
    func profile(forSave id: String) -> String? {
        guard let modSet = saveLinks[id], profiles[modSet.name] != nil else { return nil }
        return modSet.name
    }

    /// Whether a linked profile/collection still exists.
    func exists(_ modSet: SaveModSet) -> Bool {
        switch modSet.kind {
        case .profile: profiles[modSet.name] != nil
        case .collection: false  // My Collections lists became profiles
        }
    }

    /// Switches to the save's mods, then launches the game.
    func play(_ save: SaveGame) {
        guard !isGameRunning else {
            show("Stardew Valley Is Running", "Quit the game first: mods are only loaded when it starts.")
            return
        }
        if let modSet = saveLinks[save.id] {
            switch modSet.kind {
            case .profile:
                guard profiles[modSet.name] != nil else { return show("Profile Not Found", "“\(modSet.name)” no longer exists. Pick another one for this save.") }
                switchProfile(to: modSet.name)
            case .collection:
                // Lists from My Collections became profiles of the same name.
                guard profiles[modSet.name] != nil else { return show("Profile Not Found", "“\(modSet.name)” no longer exists. Pick another one for this save.") }
                switchProfile(to: modSet.name)
            }
        }
        launchGame()
    }

    func showSave(id: String) {
        selectedSaveID = id
        sidebarSelection = .saves
    }

    func installedMod(uniqueID: String) -> ModInfo? {
        mods.first { $0.uniqueID.caseInsensitiveCompare(uniqueID) == .orderedSame }
    }

    /// Works out which mods a save needs, from the save file and (when it
    /// covers this save) the latest SMAPI log. Network lookups are capped so
    /// a noisy save can't flood Nexus with requests.
    func analyze(_ save: SaveGame, progress: @escaping (String) -> Void = { _ in }) async throws -> SaveAnalysis {
        var analysis = SaveAnalysis()
        let client = nexusClient
        let file = save.saveFile

        // 1. UniqueIDs in the save file (off the main thread: saves are 20+ MB).
        progress(String(localized: "Reading the save file…"))
        let candidates = try await Task.detached { try SaveAnalyzer.candidateModIDs(inSaveFile: file) }.value
        let ordered = candidates.sorted { $0.value > $1.value }

        var unresolved: [(id: String, count: Int)] = []
        for (id, count) in ordered {
            if let installed = installedMod(uniqueID: id) {
                analysis.mods.append(SaveModUse(uniqueID: id, occurrences: count, installed: installed))
            } else {
                unresolved.append((id, count))
            }
        }

        // 2. SMAPI's mod database (one batched request), then Nexus by
        //    author/name for the rest, several at a time.
        progress(String(localized: "Checking SMAPI's mod database…"))
        let records = (try? await UpdateChecker().lookup(uniqueIDs: unresolved.map(\.id))) ?? [:]
        var needsSearch: [String] = []
        var matches: [String: ModMatch] = [:]
        for (id, _) in unresolved {
            if let record = records[id.lowercased()], let nexusID = record.nexusID {
                matches[id] = ModMatch(modID: nexusID, name: record.name ?? id, author: nil, confidence: .confirmed, matchedTerm: id)
            } else if needsSearch.count < 25 {
                needsSearch.append(id)
            }
        }
        progress(String(localized: "Matching \(needsSearch.count) mod IDs on Nexus…"))
        let found = await Self.concurrentMap(needsSearch) { id in try? await client.findMod(forUniqueID: id) }
        for (id, match) in zip(needsSearch, found) { matches[id] = match }

        for (id, count) in unresolved {
            if let match = matches[id] {
                analysis.mods.append(SaveModUse(uniqueID: id, occurrences: count, match: match, installed: installedMod(nexusID: match.modID)))
            } else {
                analysis.unmatchedIDs.append(id)
            }
        }

        // Parent IDs ("A.B" for "A.B.C") and multi-part mods can resolve to the
        // same Nexus mod; keep the most confident entry for each.
        var bestByMod: [Int: Int] = [:]
        var deduped: [SaveModUse] = []
        for use in analysis.mods {
            guard let modID = use.match?.modID ?? use.installed.flatMap(nexusID(for:)) else {
                deduped.append(use)
                continue
            }
            if let index = bestByMod[modID] {
                if (use.match?.confidence ?? .confirmed) > (deduped[index].match?.confidence ?? .confirmed) { deduped[index] = use }
            } else {
                bestByMod[modID] = deduped.count
                deduped.append(use)
            }
        }
        analysis.mods = deduped.sorted { ($0.installed == nil ? 0 : 1, -$0.occurrences) < ($1.installed == nil ? 0 : 1, -$1.occurrences) }

        // 3. Missing locations/NPCs from the log, if it's from this save.
        if let log = try? SMAPILog.load(from: SMAPILog.latestLogURL), log.loadedSaveID == save.id {
            analysis.logCoversSave = true
            let groups = SaveAnalyzer.group(log.unknownLocations)
            progress(String(localized: "Matching \(groups.count) groups of missing content on Nexus…"))
            let groupMatches = await Self.concurrentMap(groups) { group in try? await client.likelyMod(for: group) }
            for (group, match) in zip(groups, groupMatches) {
                analysis.gaps.append(SaveContentGap(group: group, match: match, installed: match.flatMap { installedMod(nexusID: $0.modID) }))
            }
        }
        return analysis
    }

    /// Installs the given Nexus mods (deduplicated), e.g. everything a save is missing.
    func installMatches(_ matches: [ModMatch]) {
        var seen = Set<Int>()
        queueNexusInstalls(matches.filter { seen.insert($0.modID).inserted }.map {
            NexusInstallRequest(modID: $0.modID, title: $0.name, version: nil)
        })
    }

    // MARK: Save backups

    var backupStore: SaveBackupStore {
        SaveBackupStore(gameFolder: smapi?.gameFolder ?? manager?.modsURL.deletingLastPathComponent())
    }

    /// Restoring while the game runs would be overwritten on its next save.
    var isGameRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            let names = [app.localizedName, app.executableURL?.lastPathComponent].compactMap { $0 }
            return names.contains { ["Stardew Valley", "StardewValley", "StardewModdingAPI"].contains($0) }
        }
    }

    /// Backs up every save into one backup (Game menu, Saves toolbar).
    func backUpAllSaves() async {
        let ids = SaveGame.list(in: backupStore.savesFolder).map(\.id)
        guard !ids.isEmpty else { return show("No Saves Found", "There are no saves to back up.") }
        if await backUpSaves(ids, label: String(localized: "All saves")) != nil {
            showStatusResult(String(localized: "Backed up \(ids.count) save(s). Restore them from Saves."))
        }
    }

    func backUpSaves(_ ids: [String], label: String) async -> SaveBackup? {
        do {
            return try await backupStore.backUp(saveIDs: ids, label: label)
        } catch {
            show("Backup Failed", detail: error.localizedDescription)
            return nil
        }
    }

    /// Restores saves (all in the backup when `ids` is nil). Returns whether it worked.
    func restoreSaves(from backup: SaveBackup, ids: [String]? = nil) async -> Bool {
        guard !isGameRunning else {
            show("Quit Stardew Valley First", "The game would overwrite the restored save the next time it saves. Quit to the desktop, then restore.")
            return false
        }
        do {
            try await backupStore.restore(backup, saveIDs: ids)
            return true
        } catch {
            show("Restore Failed", detail: error.localizedDescription)
            return false
        }
    }

    // MARK: Backup before playing

    /// The label of automatic backups, in English and the current language
    /// (so a language switch doesn't stop old ones from being pruned).
    private static var beforePlayLabels: Set<String> {
        ["Before playing with changed mods", String(localized: "Before playing with changed mods")]
    }

    /// Which mods (and versions) are enabled, as a short stable string.
    var enabledModsFingerprint: String {
        let list = mods.filter(\.isEnabled)
            .map { "\($0.uniqueID.lowercased())@\($0.version)" }
            .sorted()
            .joined(separator: "\n")
        return SHA256.hash(data: Data(list.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// A mod update can break a save in ways that only show later, so before
    /// playing with a different set of mods than last time, zip all saves.
    /// Keeps the last 5 of these. Returns false when the backup failed (the
    /// game is then not started).
    func backUpSavesIfModsChanged() async -> Bool {
        guard Preferences.bool(Preferences.backupBeforePlay, default: true), !isGameRunning else { return true }
        let fingerprint = enabledModsFingerprint
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Preferences.lastPlayedModSet) != fingerprint else { return true }

        let store = backupStore
        let ids = SaveGame.list(in: store.savesFolder).map(\.id)
        guard !ids.isEmpty else {
            defaults.set(fingerprint, forKey: Preferences.lastPlayedModSet)
            return true
        }
        isBackingUpBeforePlay = true
        defer { isBackingUpBeforePlay = false }
        do {
            try await store.backUp(saveIDs: ids, label: String(localized: "Before playing with changed mods"))
            try? await store.prune(labels: Self.beforePlayLabels, keep: 5)
            defaults.set(fingerprint, forKey: Preferences.lastPlayedModSet)
            showStatusResult(String(localized: "Your mods changed, so your saves were backed up before playing (Saves → Backups)"))
            return true
        } catch {
            show("Saves Not Backed Up", detail: String(localized: "The game wasn't started, to keep your saves safe: \(error.localizedDescription)\n\nTo play anyway, turn off “Back up saves before playing” in Settings."))
            return false
        }
    }
}
