// SMAPI version checks, mod updates (SMAPI's API), missing requirements,
// and Nexus file lists of installed mods.

import ModManagerCore
import SwiftUI

extension AppModel {
    // MARK: SMAPI

    /// Re-reads SMAPI's version from disk (the DLL scan is too slow for every refresh).
    func detectSMAPI() {
        guard let manager else { return }
        smapi = SMAPIInstallation.detect(modsURL: manager.modsURL, bundledMods: mods)
        steamGame = SteamGameState.read(gameFolder: gameFolder ?? manager.modsURL.deletingLastPathComponent())
        var updated = mods
        markModsNeedingNewerSMAPI(in: &updated)
        mods = updated
    }

    /// The game's folder (Contents/MacOS), if the Mods folder is inside it.
    var gameFolder: URL? {
        let folder = smapi?.gameFolder ?? manager?.modsURL.deletingLastPathComponent()
        return folder.flatMap { SMAPIInstaller.isGameFolder($0) ? $0 : nil }
    }

    var gameVersion: SemanticVersion? {
        smapi?.gameVersion ?? gameFolder.flatMap(SMAPIInstallation.gameVersion(in:))
    }

    /// Opens the game's page in Steam, where a waiting update can be started.
    func openGameInSteam() {
        if let url = URL(string: "steam://nav/games/details/\(SteamGameState.appID)") {
            NSWorkspace.shared.open(url)
        }
    }

    var isSMAPIOutdated: Bool {
        guard let installed = smapi?.version, let latest = latestSMAPIVersion else { return false }
        return installed < latest
    }

    var modsNeedingNewerSMAPI: [ModInfo] {
        mods.filter { $0.needsNewerSMAPI && $0.isEnabled }
    }

    func markModsNeedingNewerSMAPI(in list: inout [ModInfo]) {
        let installed = smapi?.version
        for index in list.indices {
            let required = list[index].minimumApiVersion.flatMap(SemanticVersion.init)
            list[index].needsNewerSMAPI = if let required, let installed { installed < required } else { false }
        }
    }

    func checkLatestSMAPI() async {
        if let version = try? await nexusClient.mod(id: NexusClient.smapiModID).version {
            latestSMAPIVersion = SemanticVersion(version)
        }
    }

    /// Installs or updates SMAPI with its official installer (no Terminal
    /// window), then rescans: the installer adds SMAPI's bundled mods.
    func installSMAPI() {
        guard smapiInstallPhase == nil, let manager else { return }
        guard !isGameRunning else {
            return show("Quit Stardew Valley First", "SMAPI can't be installed while the game is running.")
        }
        let gameFolder = smapi?.gameFolder ?? manager.modsURL.deletingLastPathComponent()
        guard SMAPIInstaller.isGameFolder(gameFolder) else {
            // A Mods folder outside the game: fall back to the manual installer.
            show("Game Folder Not Found", "SMAPI goes next to the game, but your Mods folder isn't inside it. Opening SMAPI's download page instead.")
            return getSMAPI()
        }
        smapiInstallPhase = .downloading(0)
        Task {
            defer { smapiInstallPhase = nil }
            do {
                let release = try await SMAPIInstaller.latestRelease()
                try await SMAPIInstaller.install(release, gameFolder: gameFolder) { phase in
                    Task { @MainActor in self.smapiInstallPhase = phase }
                }
                detectSMAPI()
                refresh()
                latestSMAPIVersion = max(latestSMAPIVersion ?? release.version, release.version)
                showStatusResult(String(localized: "SMAPI \(release.version.description) is installed. Launch the game as usual to play with mods."))
            } catch {
                show("Couldn't Install SMAPI", detail: error.localizedDescription)
            }
        }
    }

    /// Whether SMAPI needs installing, updating, or reconnecting to the game.
    var smapiNeedsInstall: Bool {
        guard let smapi else { return manager != nil }
        return isSMAPIOutdated || !smapi.isLauncherHooked || !modsNeedingNewerSMAPI.isEmpty
    }

    /// SMAPI's Nexus files page, for installing it by hand.
    func getSMAPI() {
        openInBrowser(URL(string: "https://www.nexusmods.com/\(NexusClient.gameDomain)/mods/\(NexusClient.smapiModID)?tab=files")!)
    }

    // MARK: Updates

    /// The available update for a mod, if it's still relevant to the
    /// installed version (a stale result is ignored after the mod changes).
    func update(for mod: ModInfo) -> ModUpdate? {
        guard let update = updates[mod.uniqueID.lowercased()], update.installedVersion == mod.version else { return nil }
        return update
    }

    var modsWithUpdates: [ModInfo] {
        mods.filter { update(for: $0) != nil }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// The Nexus mod ID for an installed mod, from its manifest or SMAPI's update data.
    func nexusID(for mod: ModInfo) -> Int? {
        mod.nexusModID ?? update(for: mod)?.nexusModID ?? smapiRecords[mod.uniqueID.lowercased()]?.nexusID
    }

    func installedMod(nexusID: Int) -> ModInfo? {
        mods.first { self.nexusID(for: $0) == nexusID }
    }

    func checkForUpdates() async {
        guard !isCheckingUpdates, !mods.isEmpty else { return }
        isCheckingUpdates = true
        statusResult = nil
        defer {
            isCheckingUpdates = false
            updateCheckStep = nil
            showUpdateCheckResult()
        }
        updateCheckStep = ProgressStep(text: String(localized: "Asking SMAPI about \(mods.count) mods…"), fraction: 0.05)
        Task { await checkLatestSMAPI() }
        do {
            let results = try await UpdateChecker().check(mods)
            updates = results.updates
            smapiRecords.merge(results.records) { _, new in new }
            updateCheckError = nil
            lastUpdateCheck = .now
        } catch {
            updateCheckError = error.localizedDescription
        }
        updateCheckStep = ProgressStep(text: String(localized: "Looking up requirements…"), fraction: 0.3)
        await resolveMissingDependencies()
        notifyAboutNewUpdates()
        await prefetchNexusFiles { done, total in
            self.updateCheckStep = ProgressStep(
                text: String(localized: "Reading Nexus file lists (\(done) of \(total))…"),
                fraction: 0.5 + 0.5 * Double(done) / Double(max(total, 1))
            )
        }
    }

    /// "Checked 30 mods: 2 updates available", for a few seconds.
    private func showUpdateCheckResult() {
        if let updateCheckError {
            showStatusResult(String(localized: "Update check failed: \(updateCheckError)"), isError: true)
        } else if modsWithUpdates.isEmpty {
            showStatusResult(String(localized: "Checked \(mods.count) mods: all up to date"))
        } else {
            showStatusResult(String(localized: "Checked \(mods.count) mods: \(modsWithUpdates.count) update(s) available"))
        }
    }

    /// Shows how a task went in the status bar for a few seconds.
    func showStatusResult(_ text: String, isError: Bool = false) {
        let result = StatusResult(text: text, isError: isError)
        statusResult = result
        Task {
            try? await Task.sleep(for: .seconds(8))
            if statusResult == result { statusResult = nil }
        }
    }

    /// Mods (enabled or not) that have an update on Nexus, ready for Update All.
    var nexusUpdates: [(mod: ModInfo, update: ModUpdate, nexusID: Int)] {
        modsWithUpdates.compactMap { mod in
            guard let update = update(for: mod), let id = nexusID(for: mod) else { return nil }
            return (mod, update, id)
        }
    }

    func updateAll() {
        queueNexusInstalls(nexusUpdates.map {
            NexusInstallRequest(modID: $0.nexusID, title: $0.mod.displayName, version: $0.update.version)
        })
    }

    // MARK: Dependencies

    func record(forDependency uniqueID: String) -> SMAPIModRecord? {
        smapiRecords[uniqueID.lowercased()]
    }

    /// Looks up names and Nexus IDs for missing dependencies we don't know
    /// yet, optional ones included (so they can be offered for install).
    func resolveMissingDependencies() async {
        isResolvingRequirements = true
        defer { isResolvingRequirements = false }
        let optional = mods.filter(\.isEnabled).flatMap { missingOptionalDependencies(for: $0) }
        await resolve(uniqueIDs: missingDependencies.map(\.uniqueID) + optional)
        await resolveFromNexusRequirements()
    }

    /// Tilesheet and content packs are often missing from SMAPI's database.
    /// The mod that needs them lists them on its Nexus page, so match the
    /// missing IDs against that list ("Lumisteria.LumiTilesheetsIndoor" ->
    /// "Lumisteria Tilesheets - Indoor", #9599).
    func resolveFromNexusRequirements() async {
        let client = nexusClient
        for dependency in missingDependencies where smapiRecords[dependency.id]?.nexusID == nil {
            for needingName in dependency.requiredBy {
                guard let needing = mods.first(where: { $0.displayName == needingName }),
                      let pageID = nexusPage(for: needing)
                else { continue }
                if nexusRequirementPages[pageID] == nil {
                    nexusRequirementPages[pageID] = (try? await client.requirements(forMod: pageID)) ?? []
                }
                let candidates = (nexusRequirementPages[pageID] ?? []).filter { $0.modID.map { !isInstalled(nexusID: $0) } ?? false }
                if let match = RequirementMatcher.bestMatch(for: dependency.uniqueID, among: candidates), let modID = match.modID {
                    smapiRecords[dependency.id] = SMAPIModRecord(uniqueID: dependency.uniqueID, name: match.name, nexusID: modID)
                    break
                }
            }
        }
    }

    /// The Nexus page of a mod, or of the multi-part mod it belongs to.
    func nexusPage(for mod: ModInfo) -> Int? {
        if let id = nexusID(for: mod) { return id }
        return group(containing: mod)?.mods.lazy.compactMap { self.nexusID(for: $0) }.first
    }

    func group(containing mod: ModInfo) -> ModGroup? {
        groupByModID[mod.id]
    }

    /// Installed mods that use one of `targets`, named as the Installed list
    /// shows them (a part by its group). Other `targets` and their groups'
    /// parts don't count: a mod doesn't "use" its own parts.
    struct Dependents {
        struct User: Hashable {
            let name: String
            let isEnabled: Bool
            /// Its row in the Installed list (the group's, for a part).
            let rowID: String
            let nexusID: Int?
        }
        var required: [User] = []
        var optional: [User] = []
        var isEmpty: Bool { required.isEmpty && optional.isEmpty }
    }

    func dependents(of targets: [ModInfo]) -> Dependents {
        let ids = Set(targets.map { $0.uniqueID.lowercased() }.filter { !$0.isEmpty })
        guard !ids.isEmpty else { return Dependents() }
        var excluded = Set(targets.map(\.id))
        for target in targets {
            excluded.formUnion(group(containing: target)?.mods.map(\.id) ?? [])
        }
        var required: [String: Dependents.User] = [:]   // by name; enabled if any part is
        var optional: [String: Dependents.User] = [:]
        func merge(_ other: ModInfo, into map: inout [String: Dependents.User]) {
            let group = group(containing: other)
            let name = group?.name ?? other.displayName
            let previous = map[name]
            map[name] = Dependents.User(
                name: name,
                isEnabled: (previous?.isEnabled ?? false) || other.isEnabled,
                rowID: group?.id ?? other.id,
                nexusID: previous?.nexusID ?? nexusID(for: other)
            )
        }
        for other in mods where !excluded.contains(other.id) {
            let needs = other.dependencies.filter(\.isRequired).map { $0.uniqueID.lowercased() } + [other.contentPackFor?.lowercased()].compactMap { $0 }
            if needs.contains(where: ids.contains) {
                merge(other, into: &required)
            } else if other.dependencies.contains(where: { !$0.isRequired && ids.contains($0.uniqueID.lowercased()) }) {
                merge(other, into: &optional)
            }
        }
        func users(_ map: [String: Dependents.User]) -> [Dependents.User] {
            map.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return Dependents(required: users(required), optional: users(optional.filter { required[$0.key] == nil }))
    }

    /// Selects a row of the Installed list (showing its details), clearing a
    /// filter that hides it.
    func reveal(rowID: String) {
        if !visibleGroups.contains(where: { $0.id == rowID || $0.mods.contains { $0.id == rowID } }) {
            searchText = ""
        }
        sidebarSelection = .installed
        selection = [rowID]
        scrollTarget = rowID
    }

    /// The mods needing a requirement, as the Installed list shows them: a
    /// part of a multi-part mod is named by its group ("East Scarp", not its
    /// internal "East Scarp: Locations"), which avoids looking like a mod to install.
    func describeNeeding(_ names: [String]) -> String {
        var seen = Set<String>()
        return names.map { name in
            guard let mod = mods.first(where: { $0.displayName == name }), let group = group(containing: mod) else { return name }
            return group.name
        }
        .filter { seen.insert($0).inserted }
        .joined(separator: ", ")
    }

    /// Exact parts for a tooltip: "East Scarp: Locations (in East Scarp)".
    func describeNeedingParts(_ names: [String]) -> String {
        names.map { name in
            guard let mod = mods.first(where: { $0.displayName == name }),
                  let group = group(containing: mod), group.name != name
            else { return name }
            return String(localized: "\(name) (in \(group.name))")
        }
        .joined(separator: "\n")
    }

    /// A requirement we can name and point to: installed but disabled,
    /// identified on Nexus (SMAPI's database or the needing mod's Nexus
    /// page), or hosted elsewhere per SMAPI (ModDrop, GitHub...).
    func isConfirmed(_ dependency: MissingDependency) -> Bool {
        dependency.disabledCopy != nil || isKnownRequirement(dependency.uniqueID)
    }

    func isKnownRequirement(_ uniqueID: String) -> Bool {
        let record = record(forDependency: uniqueID)
        return record?.nexusID != nil || record?.downloadPage != nil
    }

    /// Opens a non-Nexus mod's download page in the default browser (those
    /// sites don't hand files to mod managers): the user drops the file here.
    func openDownloadPage(_ url: URL) {
        NSWorkspace.shared.open(url)
        showStatusResult(String(localized: "Download the mod's file in your browser, then drop it on this window to install it."))
    }

    func resolve(uniqueIDs: [String]) async {
        let unknown = uniqueIDs.filter { smapiRecords[$0.lowercased()] == nil }
        guard !unknown.isEmpty, let records = try? await UpdateChecker().lookup(uniqueIDs: unknown) else { return }
        smapiRecords.merge(records) { _, new in new }
    }

    /// Optional dependencies of a mod that aren't installed and enabled.
    func missingOptionalDependencies(for mod: ModInfo) -> [String] {
        mod.dependencies.filter { !$0.isRequired && !enabledIDs.contains($0.uniqueID.lowercased()) }.map(\.uniqueID)
    }

    /// Installs mods by UniqueID (e.g. requirements SMAPI said were missing).
    func installMissing(uniqueIDs: [String], neededBy name: String) {
        let dependencies = uniqueIDs.map { id in
            MissingDependency(
                uniqueID: id,
                requiredBy: [name],
                disabledCopy: mods.first { !$0.isEnabled && $0.uniqueID.caseInsensitiveCompare(id) == .orderedSame }
            )
        }
        Task {
            await resolve(uniqueIDs: uniqueIDs)
            installMissingDependencies(dependencies)
        }
    }

    /// The installed mod a log source refers to (SMAPI logs mods by name).
    func installedMod(named name: String) -> ModInfo? {
        mods.first { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Installs (or enables) one dependency of `mod`, required or optional.
    func installDependency(_ uniqueID: String, of mod: ModInfo) {
        let disabled = mods.first { !$0.isEnabled && $0.uniqueID.caseInsensitiveCompare(uniqueID) == .orderedSame }
        let dependency = MissingDependency(uniqueID: uniqueID, requiredBy: [mod.displayName], disabledCopy: disabled)
        Task {
            await resolve(uniqueIDs: [uniqueID])
            installMissingDependencies([dependency])
        }
    }

    // MARK: Nexus files of installed mods


    func loadNexusFiles(for nexusID: Int) async {
        guard nexusFiles[nexusID] == nil, let files = try? await nexusClient.files(forMod: nexusID) else { return }
        nexusFiles[nexusID] = files
    }

    /// Current optional files on the mod's Nexus page (add-ons, patches, variants).
    func optionalFiles(for mod: ModInfo) -> [NexusFile] {
        guard let nexusID = nexusID(for: mod) else { return [] }
        return (nexusFiles[nexusID] ?? []).filter { $0.category == "OPTIONAL" }
    }

    /// Whether the mod has optional extras: Nexus optional files, or optional
    /// dependencies that aren't installed.
    func hasOptionalExtras(_ mod: ModInfo) -> Bool {
        !optionalFiles(for: mod).isEmpty || !missingOptionalDependencies(for: mod).isEmpty
    }

    /// Fetches Nexus file lists for installed mods (a few at a time) so the
    /// mod list can mark which ones have optional files.
    func prefetchNexusFiles(progress: (_ done: Int, _ total: Int) -> Void = { _, _ in }) async {
        let ids = Array(Set(mods.compactMap { nexusID(for: $0) })).filter { nexusFiles[$0] == nil }
        let client = nexusClient
        // In chunks, so the status bar can count them.
        var done = 0
        progress(0, ids.count)
        for start in stride(from: 0, to: ids.count, by: 6) {
            let chunk = Array(ids[start..<min(start + 6, ids.count)])
            let results = await Self.concurrentMap(chunk) { id in try? await client.files(forMod: id) }
            for (id, files) in zip(chunk, results) {
                if let files { nexusFiles[id] = files }
            }
            done += chunk.count
            progress(done, ids.count)
        }
    }

    /// Enables disabled copies, then downloads the rest from Nexus.
    func installMissingDependencies(_ dependencies: [MissingDependency]) {
        let disabled = Set(dependencies.compactMap(\.disabledCopy?.id))
        if !disabled.isEmpty {
            setEnabled(disabled, true)
        }

        var requests: [NexusInstallRequest] = []
        var unresolved: [String] = []
        var elsewhere: [URL] = []
        for dependency in dependencies where dependency.disabledCopy == nil {
            let record = record(forDependency: dependency.uniqueID)
            if let nexusID = record?.nexusID {
                requests.append(NexusInstallRequest(modID: nexusID, title: record?.name ?? dependency.uniqueID, version: nil))
            } else if let page = record?.downloadPage {
                elsewhere.append(page)
            } else {
                unresolved.append(dependency.uniqueID)
            }
        }
        queueNexusInstalls(requests)
        for page in Set(elsewhere) { openDownloadPage(page) }
        if !unresolved.isEmpty {
            show("Couldn't Find Some Requirements", "These aren't on Nexus (or SMAPI doesn't know where they are). Search for them by name:\n\n\(unresolved.joined(separator: "\n"))")
        }
    }

    /// Whether SMAPI itself is installed next to the Mods folder. SMAPI shows
    /// up as a Nexus requirement (mod 2400) but never lives in Mods/.
    var isSMAPIInstalled: Bool {
        guard let gameFolder = manager?.modsURL.deletingLastPathComponent() else { return false }
        return ["StardewModdingAPI", "StardewModdingAPI.dll"].contains {
            FileManager.default.fileExists(atPath: gameFolder.appending(path: $0).path(percentEncoded: false))
        }
    }

    func isInstalled(nexusID: Int) -> Bool {
        nexusID == NexusClient.smapiModID ? isSMAPIInstalled : installedMod(nexusID: nexusID) != nil
    }
}
