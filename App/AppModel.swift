// App state shared by all views: the scanned mods, selection, profiles,
// Nexus account, updates and downloads, plus the user-facing actions.

import AppKit
import ModManagerCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    /// The one model for the whole app (see `AppModelEnvironment`).
    static let shared = AppModel()

    struct UserMessage: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    /// Shown while an install waits for the user to decide about name collisions.
    struct ConflictPrompt: Identifiable {
        let id = UUID()
        let archiveName: String
        let names: [String]
        fileprivate let continuation: CheckedContinuation<Bool?, Never>
    }

    /// Nexus account state, derived from the API key in the Keychain.
    enum NexusAccount: Equatable {
        case none
        case checking
        case signedIn(NexusUser)
        case invalid(String)

        var user: NexusUser? {
            if case .signedIn(let user) = self { user } else { nil }
        }
    }

    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

    private let store = ConfigStore()
    private(set) var manager: ModManager?
    private(set) var mods: [ModInfo] = [] {
        didSet { recomputeDerived() }
    }
    private(set) var profiles: [String: [String]] = [:]
    private var pendingInstalls = 0
    private var installQueue: Task<Void, Never>?
    var isInstalling: Bool { pendingInstalls > 0 }

    private(set) var nexusAccount: NexusAccount = .none
    /// Loaded in the background by `start()`: reading the Keychain can show a
    /// system password prompt, which must not block the window from appearing.
    private var nexusAPIKey: String?
    var nexusClient: NexusClient { NexusClient(apiKey: nexusAPIKey, appVersion: Self.appVersion) }

    /// Available updates keyed by lowercased UniqueID (see `update(for:)`).
    private(set) var updates: [String: ModUpdate] = [:] {
        didSet { recomputeDerived() }
    }
    /// What SMAPI's database knows about installed mods and missing
    /// dependencies (names, Nexus IDs), keyed by lowercased UniqueID.
    private(set) var smapiRecords: [String: SMAPIModRecord] = [:] {
        didSet { recomputeDerived() }
    }
    /// Set after an install leaves mods with missing requirements.
    var requirementsPrompt: [MissingDependency]?
    private(set) var isCheckingUpdates = false
    private(set) var lastUpdateCheck: Date?
    private(set) var updateCheckError: String?

    private(set) var downloads: [DownloadItem] = []
    var nexusSheet: NexusSheetRequest?
    var collectionSheet: CollectionSheetRequest?

    /// The sidebar section; lives here so actions can navigate (e.g. log -> saves).
    var sidebarSelection: SidebarItem? = .installed
    /// Save to show in the Saves section.
    var selectedSaveID: String?

    /// Where the log was cleared: entries before it are hidden. Kept here so
    /// it survives switching sections; a new game session resets it.
    struct LogClearMark: Equatable {
        let file: URL
        let session: String
        let entryCount: Int
        let date: Date
    }
    var logClearMark: LogClearMark?

    /// SMAPI next to the Mods folder (nil if missing) and the latest release on Nexus.
    private(set) var smapi: SMAPIInstallation?
    private(set) var latestSMAPIVersion: SemanticVersion?

    /// What the in-app Nexus browser should show; RootView opens its window.
    private(set) var browserRequest: BrowserRequest?
    /// Pages a free account still has to click "Slow download" on (Update
    /// All / install requirements). Advances each time an nxm link arrives.
    private(set) var browserQueue: [BrowserQueueItem] = []

    var searchText = ""
    var selection: Set<ModInfo.ID> = []
    var needsFolderSetup = false
    var message: UserMessage?
    var conflictPrompt: ConflictPrompt?
    var pendingTrash: [ModInfo] = []

    // MARK: Derived state

    var visibleMods: [ModInfo] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return mods }
        return mods.filter {
            "\($0.name) \($0.author) \($0.uniqueID)".localizedCaseInsensitiveContains(query)
        }
    }

    var singleSelectedMod: ModInfo? {
        if let group = selectedGroup, group.mods.count == 1 { return group.mods[0] }
        guard selection.count == 1 else { return nil }
        return mods.first { selection.contains($0.id) }
    }

    // Derived from `mods` (and update data), stored rather than computed:
    // views read these many times per redraw. See `recomputeDerived()`.
    private(set) var enabledIDs: Set<String> = []
    private(set) var allGroups: [ModGroup] = []
    private(set) var missingDependencies: [MissingDependency] = []
    private(set) var duplicateGroups: [[ModInfo]] = []

    private func recomputeDerived() {
        enabledIDs = Set(mods.filter { $0.isEnabled && !$0.uniqueID.isEmpty }.map { $0.uniqueID.lowercased() })
        allGroups = ModGrouping.groups(mods) { self.nexusID(for: $0) }
        missingDependencies = MissingDependency.find(in: mods)
        duplicateGroups = ModManager.duplicateGroups(in: mods)
    }

    var summary: String {
        let enabled = mods.filter(\.isEnabled).count
        let shown = searchText.isEmpty ? "" : "\(visibleMods.count) shown · "
        return "\(shown)\(mods.count) mods · \(enabled) enabled"
    }

    var profileNames: [String] {
        profiles.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var defaultFolderExists: Bool {
        FileManager.default.fileExists(atPath: AppConstants.defaultSteamModsURL.path(percentEncoded: false))
    }

    // MARK: Mods folder

    func start() {
        profiles = store.loadProfiles()
        saveLinks = store.loadSaveLinks()
        loadModLists()
        if let saved = store.modsURL(), FileManager.default.fileExists(atPath: saved.path(percentEncoded: false)) {
            use(modsFolder: saved, remember: false)
        } else {
            needsFolderSetup = true
        }
        nexusAccount = .checking
        Task {
            nexusAPIKey = await Task.detached { Keychain.readNexusAPIKey() }.value
            await validateNexusKey()
        }
    }

    func use(modsFolder url: URL, remember: Bool = true) {
        if remember {
            do {
                try store.setModsURL(url)
            } catch {
                show("Couldn't save settings", error.localizedDescription)
            }
        }
        manager = ModManager(modsURL: url, archive: modArchive)
        needsFolderSetup = false
        selection = []
        updates = [:]
        refresh()
        detectSMAPI()
        Task { await checkForUpdates() }
    }

    func chooseModsFolder() {
        let panel = NSOpenPanel()
        panel.message = "Select your Stardew Valley \"Mods\" folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true  // the Steam path lives under ~/Library
        panel.directoryURL = manager?.modsURL ?? (defaultFolderExists ? AppConstants.defaultSteamModsURL : .homeDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            use(modsFolder: url)
        }
    }

    func refresh() {
        guard let manager else { return }
        var scanned: [ModInfo]
        do {
            scanned = try manager.scan()
        } catch {
            scanned = []
            show("Couldn't read Mods folder", error.localizedDescription)
        }
        markModsNeedingNewerSMAPI(in: &scanned)
        mods = scanned  // one assignment: one recompute of derived data
        // Keep selected groups too (their IDs aren't mod IDs).
        let ids = Set(mods.map(\.id)).union(allGroups.map(\.id))
        selection.formIntersection(ids)
    }

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

    private func markModsNeedingNewerSMAPI(in list: inout [ModInfo]) {
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

    // MARK: Enable / disable / trash

    func setEnabled(_ ids: Set<ModInfo.ID>, _ enabled: Bool) {
        // Selection follows the mods through renames (".Off" -> "Off").
        let selectedKeys = Set(mods.filter { selection.contains($0.id) }.map(Self.stableKey))
        let failures = toggle(mods.filter { ids.contains($0.id) }, to: enabled)
        refresh()
        selection = selection.filter { id in allGroups.contains { $0.id == id } }
            .union(mods.filter { selectedKeys.contains(Self.stableKey($0)) }.map(\.id))
        if !failures.isEmpty {
            show("Couldn't toggle mod", failures.joined(separator: "\n"))
        }
    }

    /// A mod's path with the "disabled" dots removed: stays the same when it
    /// (or a folder it's in) is enabled or disabled.
    static func stableKey(_ mod: ModInfo) -> String {
        (mod.containerPath + [mod.folderName]).map { String($0.drop { $0 == "." }) }.joined(separator: "/")
    }

    /// Enables/disables mods one by one. Enabling a mod inside a disabled
    /// folder renames that folder, which moves the other mods in it, so
    /// later targets are looked up again after such a rename.
    private func toggle(_ targets: [ModInfo], to enabled: Bool) -> [String] {
        guard let manager else { return [] }
        var failures: [String] = []
        var foldersRenamed = false
        for target in targets {
            var mod = target
            if foldersRenamed, let fresh = (try? manager.scan())?.first(where: { Self.stableKey($0) == Self.stableKey(target) }) {
                mod = fresh
            }
            guard mod.isEnabled != enabled else { continue }
            do {
                try manager.setEnabled(mod, enabled)
                if enabled && mod.isDisabledByContainer { foldersRenamed = true }
            } catch {
                failures.append("\(mod.displayName): \(error.localizedDescription)")
            }
        }
        return failures
    }

    func moveToTrash(_ targets: [ModInfo]) {
        guard let manager else { return }
        var failures: [String] = []
        for mod in targets {
            do {
                try manager.moveToTrash(mod)
            } catch {
                failures.append("\(mod.displayName): \(error.localizedDescription)")
            }
        }
        refresh()
        if !failures.isEmpty {
            show("Couldn't move to Trash", failures.joined(separator: "\n"))
        }
    }

    // MARK: Installing

    func presentInstallPanel() {
        guard manager != nil else { return }
        let panel = NSOpenPanel()
        panel.message = "Select downloaded mod archives (.zip, .7z, .rar)"
        panel.allowedContentTypes = ModManager.archiveExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.directoryURL = .downloadsDirectory
        if panel.runModal() == .OK {
            install(panel.urls)
        }
    }

    /// Queues archives for installation. Installs run one at a time, so
    /// conflict prompts never overlap.
    ///
    /// - Parameters:
    ///   - replaceExisting: skip the "already installed" prompt and replace
    ///     (used for downloads the user explicitly picked, i.e. updates).
    ///   - quiet: don't show a summary alert on success.
    @discardableResult
    func install(_ urls: [URL], replaceExisting: Bool = false, quiet: Bool = false) -> Task<InstallResult, Never> {
        let previous = installQueue
        pendingInstalls += 1
        let task = Task {
            await previous?.value
            defer { pendingInstalls -= 1 }
            return await performInstall(urls, replaceExisting: replaceExisting, quiet: quiet)
        }
        installQueue = Task { _ = await task.value }
        return task
    }

    private func performInstall(_ urls: [URL], replaceExisting: Bool, quiet: Bool) async -> InstallResult {
        var total = InstallResult()
        guard let manager else {
            total.errors.append("Choose your Mods folder first.")
            report(total)
            return total
        }
        let archives = urls.filter { ModManager.archiveExtensions.contains($0.pathExtension.lowercased()) }
        guard !archives.isEmpty else {
            show("Nothing to install", "Drop or choose mod archives (.zip, .7z, .rar) downloaded from Nexus or elsewhere.")
            return total
        }

        let missingBefore = Set(missingDependencies.map(\.id))
        for archive in archives {
            do {
                let prepared = try await manager.prepareInstall(archive: archive)
                var overwrite = replaceExisting
                if !prepared.conflicts.isEmpty && !replaceExisting {
                    guard let choice = await askAboutConflicts(prepared) else {
                        prepared.discard()  // cancelled this archive
                        continue
                    }
                    overwrite = choice
                }
                total.merge(await manager.commit(prepared, overwrite: overwrite))
            } catch let error as ModManagerError where error.revealURL != nil {
                // SMAPI's installer: unpacked to Downloads rather than installed.
                NSWorkspace.shared.activateFileViewerSelecting([error.revealURL!])
                show("SMAPI Installer Ready", error.message)
            } catch {
                total.errors.append(error.localizedDescription)
            }
        }

        refresh()
        if !total.installed.isEmpty {
            Task { await checkForUpdates() }
            let newlyMissing = missingDependencies.filter { !missingBefore.contains($0.id) }
            if !newlyMissing.isEmpty {
                Task {
                    await resolveMissingDependencies()
                    requirementsPrompt = newlyMissing
                }
            }
        }
        if !quiet || !total.errors.isEmpty {
            report(total)
        }
        return total
    }

    func resolveConflict(_ overwrite: Bool?) {
        guard let prompt = conflictPrompt else { return }
        conflictPrompt = nil
        prompt.continuation.resume(returning: overwrite)
    }

    private func askAboutConflicts(_ prepared: PreparedInstall) async -> Bool? {
        await withCheckedContinuation { continuation in
            conflictPrompt = ConflictPrompt(
                archiveName: prepared.archiveName,
                names: prepared.conflicts,
                continuation: continuation
            )
        }
    }

    private func report(_ result: InstallResult) {
        guard !result.isEmpty else { return }
        var lines: [String] = []
        if !result.installed.isEmpty { lines.append("Installed/updated: " + result.installed.joined(separator: ", ")) }
        if !result.skipped.isEmpty { lines.append("Skipped: " + result.skipped.joined(separator: ", ")) }
        if !result.errors.isEmpty { lines.append("Errors:\n" + result.errors.joined(separator: "\n")) }
        let title = result.errors.isEmpty ? "Install Complete" : "Install Finished with Problems"
        show(title, lines.joined(separator: "\n\n"))
    }

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
        applyEnabledSet(ids, title: "profile '\(name)'")
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

        var lines = ["Applied \(title)."]
        if !notInstalled.isEmpty { lines.append("Not installed: " + notInstalled.joined(separator: ", ")) }
        if !failures.isEmpty { lines.append("Couldn't toggle:\n" + failures.joined(separator: "\n")) }
        if lines.count > 1 { show("Profile Applied", lines.joined(separator: "\n\n")) }
    }

    private func persistProfiles() {
        do {
            try store.saveProfiles(profiles)
        } catch {
            show("Couldn't save profiles", error.localizedDescription)
        }
    }

    // MARK: Groups, duplicates, rollback

    let modArchive = ModArchive()

    /// Groups with members matching the filter (whole groups when not filtering).
    var visibleGroups: [ModGroup] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return allGroups }
        return allGroups.compactMap { group in
            let matching = group.mods.filter { "\($0.name) \($0.author) \($0.uniqueID)".localizedCaseInsensitiveContains(query) }
            guard !matching.isEmpty else { return nil }
            return ModGroup(id: group.id, name: group.name, mods: matching, isFolder: group.isFolder)
        }
    }

    /// Mod IDs for a selection that may include group rows.
    func modIDs(expanding ids: Set<String>) -> Set<ModInfo.ID> {
        var result = ids.filter { id in mods.contains { $0.id == id } }
        for group in allGroups where ids.contains(group.id) {
            result.formUnion(group.mods.map(\.id))
        }
        return result
    }

    var selectedGroup: ModGroup? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return allGroups.first { $0.id == id && $0.isGroup }
    }

    /// Keeps the newest copy of each duplicated mod and trashes the others.
    func fixDuplicates() {
        let extras = duplicateGroups.flatMap { copies -> [ModInfo] in
            guard let keep = ModManager.preferredCopy(among: copies) else { return [] }
            return copies.filter { $0.id != keep.id }
        }
        moveToTrash(extras)
    }

    func archivedVersions(of mod: ModInfo) -> [ArchivedVersion] {
        mod.uniqueID.isEmpty ? [] : modArchive.versions(of: mod.uniqueID)
    }

    func revert(_ mod: ModInfo, to version: ArchivedVersion) {
        guard !isGameRunning else {
            show("Quit Stardew Valley First", "Mods can't be swapped while the game is running.")
            return
        }
        do {
            try modArchive.restore(version, replacing: mod)
        } catch {
            show("Couldn't Revert", error.localizedDescription)
        }
        refresh()
        Task { await checkForUpdates() }
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

    // MARK: Endorse & track

    private(set) var endorsements: [Int: NexusClient.EndorsementStatus] = [:]
    private(set) var trackedMods: Set<Int> = []

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
                show(endorsed ? "Couldn't Endorse" : "Couldn't Remove Endorsement", Self.friendlyNexusMessage(error.localizedDescription))
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
                show("Couldn't Change Tracking", Self.friendlyNexusMessage(error.localizedDescription))
            }
        }
    }

    /// Nexus answers with codes like "NOT_DOWNLOADED_MOD"; explain them.
    static func friendlyNexusMessage(_ message: String) -> String {
        switch message {
        case let m where m.contains("NOT_DOWNLOADED_MOD"):
            "Nexus only lets you endorse mods you've downloaded with this account."
        case let m where m.contains("TOO_SOON_AFTER_DOWNLOAD"):
            "Nexus asks you to try a mod for a little while before endorsing it. Try again later."
        case let m where m.contains("IS_OWN_MOD"):
            "You can't endorse your own mod."
        default:
            message
        }
    }

    // MARK: Nexus files of installed mods

    /// Nexus file lists by mod number, fetched once per session.
    private(set) var nexusFiles: [Int: [NexusFile]] = [:]

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
            show("Couldn't Find Some Requirements", "These aren't on Nexus (or SMAPI doesn't know where they are). Search for them by name:\n\n" + unresolved.joined(separator: "\n"))
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

    // MARK: Nexus account

    func setNexusAPIKey(_ rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try Keychain.saveNexusAPIKey(key)
        } catch {
            show("Couldn't save API key", error.localizedDescription)
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

    // MARK: Downloads

    /// Handles nxm:// links from the website's "Mod Manager Download" button,
    /// and archive files opened with the app.
    func handleOpenURL(_ url: URL) {
        if url.isFileURL {
            install([url])
            return
        }
        if let collection = NXMCollectionLink(url: url), collection.gameDomain == NexusClient.gameDomain {
            collectionSheet = CollectionSheetRequest(slug: collection.slug, revision: collection.revision)
            NSApp.activate()
            return
        }
        guard let link = NXMLink(url: url) else {
            show("Unsupported Link", url.absoluteString)
            return
        }
        guard link.gameDomain == NexusClient.gameDomain else {
            show("Not a Stardew Valley Mod", "This link is for “\(link.gameDomain)”. Only Stardew Valley mods can be installed here.")
            return
        }
        downloadAndInstall(modID: link.modID, fileID: link.fileID, title: "Nexus mod \(link.modID)", key: link.key, expires: link.expires)
    }

    /// Downloads one Nexus file and installs it, replacing an older copy.
    func downloadAndInstall(modID: Int, fileID: Int, title: String, key: String? = nil, expires: String? = nil) {
        guard manager != nil else {
            show("Choose Your Mods Folder", "Pick your Mods folder before installing mods.")
            return
        }
        guard nexusAPIKey != nil else {
            show("Nexus API Key Needed", "Add your personal Nexus Mods API key in Settings → Nexus Mods to download mods.")
            return
        }

        let item = DownloadItem(title: title)
        downloads.insert(item, at: 0)
        let client = nexusClient

        Task {
            if title.hasPrefix("Nexus mod "), let mod = try? await client.mod(id: modID) {
                item.title = mod.name
            }
        }

        Task {
            var folder: URL?
            do {
                let url = try await client.downloadURL(modID: modID, fileID: fileID, key: key, expires: expires)
                item.state = .downloading
                let file = try await FileDownloader.download(url) { fraction in
                    Task { @MainActor in item.progress = fraction }
                }
                folder = file.deletingLastPathComponent()
                item.state = .installing
                let result = await install([file], replaceExisting: true, quiet: true).value
                item.state = result.errors.isEmpty ? .installed : .failed(result.errors.joined(separator: "\n"))
            } catch {
                item.state = .failed(error.localizedDescription)
            }
            if let folder { try? FileManager.default.removeItem(at: folder) }
        }
    }

    func clearFinishedDownloads() {
        downloads.removeAll { $0.isFinished }
    }

    /// Installs the best file for each Nexus mod: directly for Premium
    /// accounts, otherwise by walking the in-app browser through each mod's
    /// "Mod Manager Download" page.
    func queueNexusInstalls(_ requests: [NexusInstallRequest]) {
        guard !requests.isEmpty else { return }
        guard nexusAPIKey != nil else {
            show("Nexus API Key Needed", "Add your personal Nexus Mods API key in Settings → Nexus Mods to download mods.")
            return
        }
        let client = nexusClient
        let isPremium = nexusAccount.user?.isPremium == true

        Task {
            var pages: [BrowserQueueItem] = []
            var failures: [String] = []
            for request in requests {
                do {
                    let fileID: Int
                    if let pinned = request.fileID {
                        fileID = pinned  // e.g. a collection's exact file
                    } else if let file = NexusFile.bestMatch(in: try await client.files(forMod: request.modID), version: request.version) {
                        fileID = file.fileId
                    } else {
                        failures.append("\(request.title): no downloadable file")
                        continue
                    }
                    if isPremium {
                        downloadAndInstall(modID: request.modID, fileID: fileID, title: request.title)
                    } else {
                        pages.append(BrowserQueueItem(
                            title: request.title,
                            url: NexusClient.modManagerDownloadPageURL(modID: request.modID, fileID: fileID)
                        ))
                    }
                } catch {
                    failures.append("\(request.title): \(error.localizedDescription)")
                }
            }
            if !pages.isEmpty {
                browserQueue += pages
                openInBrowser(browserQueue[0].url)
            }
            if !failures.isEmpty {
                show("Some Mods Couldn't Be Queued", failures.joined(separator: "\n"))
            }
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

    /// Which profile/collection each save uses.
    private(set) var saveLinks: [String: SaveModSet] = [:]

    func link(saveID: String, to modSet: SaveModSet?) {
        saveLinks[saveID] = modSet
        do {
            try store.saveSaveLinks(saveLinks)
        } catch {
            show("Couldn't Save Link", error.localizedDescription)
        }
    }

    /// Whether a linked profile/collection still exists.
    func exists(_ modSet: SaveModSet) -> Bool {
        switch modSet.kind {
        case .profile: profiles[modSet.name] != nil
        case .collection: modLists.contains { $0.name == modSet.name }
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
                guard let ids = profiles[modSet.name] else { return show("Profile Not Found", "“\(modSet.name)” no longer exists. Pick another one for this save.") }
                applyEnabledSet(ids, title: "profile '\(modSet.name)'")
            case .collection:
                guard let list = modLists.first(where: { $0.name == modSet.name }) else { return show("Collection Not Found", "“\(modSet.name)” no longer exists. Pick another one for this save.") }
                apply(list)
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
        progress("Reading the save file…")
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
        progress("Checking SMAPI's mod database…")
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
        progress("Matching \(needsSearch.count) mod IDs on Nexus…")
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
            progress("Matching \(groups.count) groups of missing content on Nexus…")
            let groupMatches = await Self.concurrentMap(groups) { group in try? await client.likelyMod(for: group) }
            for (group, match) in zip(groups, groupMatches) {
                analysis.gaps.append(SaveContentGap(group: group, match: match, installed: match.flatMap { installedMod(nexusID: $0.modID) }))
            }
        }
        return analysis
    }

    /// Maps `items` with up to `limit` requests in flight, keeping order.
    private static func concurrentMap<T: Sendable, R: Sendable>(
        _ items: [T],
        limit: Int = 6,
        _ transform: @escaping @Sendable (T) async -> R
    ) async -> [R] {
        await withTaskGroup(of: (Int, R).self) { group in
            var results = [R?](repeating: nil, count: items.count)
            var next = 0
            while next < min(limit, items.count) {
                let index = next
                group.addTask { (index, await transform(items[index])) }
                next += 1
            }
            for await (index, result) in group {
                results[index] = result
                if next < items.count {
                    let index = next
                    group.addTask { (index, await transform(items[index])) }
                    next += 1
                }
            }
            return results.map { $0! }
        }
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

    func backUpSaves(_ ids: [String], label: String) async -> SaveBackup? {
        do {
            return try await backupStore.backUp(saveIDs: ids, label: label)
        } catch {
            show("Backup Failed", error.localizedDescription)
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
            show("Restore Failed", error.localizedDescription)
            return false
        }
    }

    // MARK: My Collections (mod lists)

    private let modListStore = ModListStore()
    private(set) var modLists: [ModList] = []

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
            show("Couldn't Save Collection", error.localizedDescription)
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
        panel.message = "Export “\(list.name)” to share it or use it on another computer"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try list.encoded().write(to: url, options: .atomic)
        } catch {
            show("Export Failed", error.localizedDescription)
        }
    }

    /// Imports a mod list file and keeps a copy in My Collections.
    func importModList() -> ModList? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a mod list exported from Stardew Mod Manager"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            var list = try ModList.decode(from: Data(contentsOf: url))
            // Don't silently replace a different list that has the same name.
            if modLists.contains(where: { $0.name == list.name && $0 != list }) {
                list.name += " (imported)"
            }
            return store(list)
        } catch {
            show("Import Failed", error.localizedDescription)
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
                show("Some Mods Aren't on Nexus", "Couldn't find a Nexus page for:\n\n" + unknown.joined(separator: "\n"))
            }
        }
    }

    /// Enables exactly the mods the list had enabled, like a profile.
    func apply(_ list: ModList) {
        applyEnabledSet(list.mods.filter(\.enabled).map(\.uniqueID), title: "collection '\(list.name)'")
    }

    // MARK: In-app browser

    func openInBrowser(_ url: URL) {
        browserRequest = BrowserRequest(url: url)
    }

    /// Called by the browser when Nexus hands over an nxm:// link.
    func browserDidReceiveNXM(_ url: URL) {
        handleOpenURL(url)
        advanceBrowserQueue()
    }

    func advanceBrowserQueue() {
        guard !browserQueue.isEmpty else { return }
        browserQueue.removeFirst()
        if let next = browserQueue.first {
            openInBrowser(next.url)
        }
    }

    func cancelBrowserQueue() {
        browserQueue = []
    }

    /// A mod archive downloaded directly in the browser (e.g. "Manual download").
    func installBrowserDownload(_ file: URL) {
        let item = DownloadItem(title: file.lastPathComponent)
        item.state = .installing
        downloads.insert(item, at: 0)
        Task {
            let result = await install([file], replaceExisting: true, quiet: true).value
            item.state = result.errors.isEmpty ? .installed : .failed(result.errors.joined(separator: "\n"))
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
    }

    // MARK: Finder / web / Steam

    func openModsFolder() {
        if let url = manager?.modsURL { NSWorkspace.shared.open(url) }
    }

    func revealInFinder(_ targets: [ModInfo]) {
        NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.folderURL))
    }

    /// On macOS, SMAPI's installer replaces the game's own launcher, so a
    /// normal Steam launch already runs through SMAPI.
    func launchGame() {
        if let url = URL(string: "steam://rungameid/\(AppConstants.steamAppID)") {
            NSWorkspace.shared.open(url)
        }
    }

    func show(_ title: String, _ body: String) {
        message = UserMessage(title: title, body: body)
    }
}
