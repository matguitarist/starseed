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
        var updated = mods
        markModsNeedingNewerSMAPI(in: &updated)
        mods = updated
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

    /// SMAPI has to be installed with its own installer: open its Nexus files.
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
        defer { isCheckingUpdates = false }
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
        await resolveMissingDependencies()
        notifyAboutNewUpdates()
        await prefetchNexusFiles()
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
        allGroups.first { $0.isGroup && $0.mods.contains { $0.id == mod.id } }
    }

    /// "East Scarp: Locations (East Scarp)": names a part with its group, since
    /// the Installed list shows multi-part mods under the group's name.
    func describeNeeding(_ names: [String]) -> String {
        names.map { name in
            guard let mod = mods.first(where: { $0.displayName == name }),
                  let group = group(containing: mod), group.name != name
            else { return name }
            return "\(name) (\(group.name))"
        }
        .joined(separator: ", ")
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
    func prefetchNexusFiles() async {
        let ids = Array(Set(mods.compactMap { nexusID(for: $0) })).filter { nexusFiles[$0] == nil }
        let client = nexusClient
        let results = await Self.concurrentMap(ids) { id in try? await client.files(forMod: id) }
        for (id, files) in zip(ids, results) {
            if let files { nexusFiles[id] = files }
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
        for dependency in dependencies where dependency.disabledCopy == nil {
            let record = record(forDependency: dependency.uniqueID)
            if let nexusID = record?.nexusID {
                requests.append(NexusInstallRequest(modID: nexusID, title: record?.name ?? dependency.uniqueID, version: nil))
            } else {
                unresolved.append(dependency.uniqueID)
            }
        }
        queueNexusInstalls(requests)
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
