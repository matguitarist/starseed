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
        let continuation: CheckedContinuation<Bool?, Never>
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

    let configStore = ConfigStore()
    private(set) var manager: ModManager?
    var mods: [ModInfo] = [] {
        didSet { recomputeDerived() }
    }
    var profiles: [String: [String]] = [:]
    /// Collections fetched for the details panel's profile overview, by slug.
    var collectionRevisions: [String: CollectionRevision] = [:]
    /// Profiles made from a Nexus collection, by profile name, so the
    /// collection (and its optional mods) can be opened again.
    var profileCollections: [String: ProfileCollection] = {
        guard let data = UserDefaults.standard.data(forKey: Preferences.profileCollections),
              let saved = try? JSONDecoder().decode([String: ProfileCollection].self, from: data)
        else { return [:] }
        return saved
    }() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(profileCollections), forKey: Preferences.profileCollections) }
    }
    /// The profile in use: turning mods on or off updates it (see
    /// AppModel+Profiles.swift). Remembered between launches.
    var activeProfile: String? = UserDefaults.standard.string(forKey: Preferences.activeProfile) {
        didSet { UserDefaults.standard.set(activeProfile, forKey: Preferences.activeProfile) }
    }
    var pendingInstalls = 0
    var installQueue: Task<Void, Never>?
    var isInstalling: Bool { pendingInstalls > 0 }

    var nexusAccount: NexusAccount = .none
    /// Loaded in the background by `start()`: reading the Keychain can show a
    /// system password prompt, which must not block the window from appearing.
    var nexusAPIKey: String?
    var nexusClient: NexusClient { NexusClient(apiKey: nexusAPIKey, appVersion: Self.appVersion) }

    /// Available updates keyed by lowercased UniqueID (see `update(for:)`).
    var updates: [String: ModUpdate] = [:] {
        didSet { recomputeDerived() }
    }
    /// What SMAPI's database knows about installed mods and missing
    /// dependencies (names, Nexus IDs), keyed by lowercased UniqueID.
    var smapiRecords: [String: SMAPIModRecord] = [:] {
        didSet { recomputeDerived() }
    }
    /// Set after an install leaves mods with missing requirements.
    var requirementsPrompt: [MissingDependency]?
    var isCheckingUpdates = false
    /// The running update check's current step, for the status bar.
    var updateCheckStep: ProgressStep?
    /// How the last task went (update check, backup before playing);
    /// shown briefly in the status bar.
    var statusResult: StatusResult?
    var isBackingUpBeforePlay = false
    /// The Installed page's details panel and Profiles sheet (also driven by
    /// the View and Mods menus).
    var showInspector = true
    var showProfiles = false
    /// The running "Find a Broken Mod" search (see BisectView.swift).
    var bisection: Bisection?
    var bisectionOriginal: Set<String>?
    var showBisect = false
    /// The problems from the last game session (see PlayReports.swift).
    var lastPlayReport: PlayReport?
    /// A log the SMAPI Log section should open (e.g. the crash log).
    var requestedLogURL: URL?
    /// Steam's view of the game (update waiting?), read with SMAPI's version.
    var steamGame: SteamGameState?
    /// Where the game was bought (Steam, GOG, Mac App Store).
    var gameStore: GameStore?
    /// Set while SMAPI is being downloaded or installed.
    var smapiInstallPhase: SMAPIInstaller.Phase?
    var lastUpdateCheck: Date?
    var updateCheckError: String?

    var downloads: [DownloadItem] = []
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
    var smapi: SMAPIInstallation?
    var latestSMAPIVersion: SemanticVersion?

    /// What the in-app Nexus browser should show; RootView opens its window.
    var browserRequest: BrowserRequest?
    /// Pages a free account still has to click "Slow download" on (Update
    /// All / install requirements). Advances each time an nxm link arrives.
    var browserQueue: [BrowserQueueItem] = []
    /// Bumped when the last page of a download queue is done, so the
    /// browser window closes itself.
    var browserQueueFinished = 0
    /// Asset conflicts SMAPI reported in the latest log (mods -> assets).
    var logConflicts: [LogConflict] = []
    /// Nexus page info (pictures) of installed mods, by mod number.
    var nexusModInfo: [Int: NexusMod] = [:]
    /// Nexus changelogs by mod number, fetched when first shown.
    var changelogs: [Int: [ChangelogEntry]] = [:]
    /// The profile that asked for each queued Nexus download (by mod number),
    /// so a download that finishes after a profile switch still joins it.
    var downloadProfiles: [Int: String] = [:]
    /// Nexus mods whose files are being looked up before download.
    var preparingNexusIDs: Set<Int> = []

    var searchText = ""
    var selection: Set<ModInfo.ID> = []
    var needsFolderSetup = false
    var message: UserMessage?
    var conflictPrompt: ConflictPrompt?
    var pendingTrash: [ModInfo] = []
    /// Requirements nothing uses anymore after a deletion, offered for removal.
    var unusedRequirementsPrompt: UnusedRequirementsPrompt?

    struct UnusedRequirementsPrompt: Identifiable {
        let id = UUID()
        /// Display names of the mods that were just removed.
        let removedNames: [String]
        let items: [UnusedRequirement]
    }

    /// Previous versions of mods, for "Revert".
    let modArchive = ModArchive()

    // Nexus account data (AppModel+Nexus).
    var endorsements: [Int: NexusClient.EndorsementStatus] = [:]
    var trackedMods: Set<Int> = []
    /// Endorsements and tracked mods are fetched the first time a mod's
    /// Endorse/Track buttons are shown, not at every launch (Nexus's API
    /// policy: use the key for things the user does).
    var accountListsLoaded = false
    /// Nexus file lists by mod number, fetched once per session.
    var nexusFiles: [Int: [NexusFile]] = [:]
    /// True while missing requirements are being looked up (SMAPI, then Nexus pages).
    var isResolvingRequirements = false
    /// Nexus "Requirements" lists by mod number, fetched once per session.
    var nexusRequirementPages: [Int: [NexusRequirement]] = [:]

    /// Which profile/collection each save uses (AppModel+Saves).
    var saveLinks: [String: SaveModSet] = [:]

    // My Collections (AppModel+Profiles).
    let modListStore = ModListStore()

    // Derived from `mods` (and update data), stored rather than computed:
    // views read these many times per redraw. See `recomputeDerived()`.
    private(set) var enabledIDs: Set<String> = []
    private(set) var allGroups: [ModGroup] = []
    /// A row the Installed table should scroll to (set by `reveal`).
    var scrollTarget: String?
    /// Multi-part groups by member mod ID, for `group(containing:)`.
    private(set) var groupByModID: [ModInfo.ID: ModGroup] = [:]
    private(set) var missingDependencies: [MissingDependency] = []
    private(set) var duplicateGroups: [[ModInfo]] = []

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

    private func recomputeDerived() {
        enabledIDs = Set(mods.filter { $0.isEnabled && !$0.uniqueID.isEmpty }.map { $0.uniqueID.lowercased() })
        allGroups = ModGrouping.groups(mods) { self.nexusID(for: $0) }
        groupByModID = [:]
        for group in allGroups where group.isGroup {
            for mod in group.mods { groupByModID[mod.id] = group }
        }
        missingDependencies = MissingDependency.find(in: mods)
        duplicateGroups = ModManager.duplicateGroups(in: mods)
    }

    var summary: String {
        let enabled = mods.filter(\.isEnabled).count
        let total = String(localized: "\(mods.count) mods · \(enabled) enabled")
        return searchText.isEmpty ? total : String(localized: "\(visibleMods.count) shown · \(total)")
    }

    var profileNames: [String] {
        profiles.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var defaultFolderExists: Bool {
        FileManager.default.fileExists(atPath: AppConstants.defaultSteamModsURL.path(percentEncoded: false))
    }

    // MARK: Mods folder

    func start() {
        // Before reading the Mods folder: a broken-mod search in progress
        // keeps its temporary mod set out of the profile in use.
        loadBisection()
        profiles = configStore.loadProfiles()
        saveLinks = configStore.loadSaveLinks()
        migrateModListsToProfiles()  // the old My Collections become profiles
        if let saved = configStore.modsURL(), FileManager.default.fileExists(atPath: saved.path(percentEncoded: false)) {
            use(modsFolder: saved, remember: false)
        } else {
            needsFolderSetup = true
        }
        Task { await loadLogConflicts() }
        nexusAccount = .checking
        Task {
            nexusAPIKey = await Task.detached { Keychain.readNexusAPIKey() }.value
            await validateNexusKey()
        }
    }

    func use(modsFolder url: URL, remember: Bool = true) {
        if remember {
            do {
                try configStore.setModsURL(url)
            } catch {
                show("Couldn't save settings", detail: error.localizedDescription)
            }
        }
        manager = ModManager(modsURL: url, archive: modArchive)
        needsFolderSetup = false
        selection = []
        updates = [:]
        refresh()
        ensureActiveProfile()  // first launch: a "Default" profile from the current mods
        detectSMAPI()
        Task { await checkForUpdates() }
    }

    func chooseModsFolder() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Select your Stardew Valley “Mods” folder")
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
            show("Couldn't read Mods folder", detail: error.localizedDescription)
        }
        markModsNeedingNewerSMAPI(in: &scanned)
        mods = scanned  // one assignment: one recompute of derived data
        trackActiveProfile()
        // Keep selected groups too (their IDs aren't mod IDs).
        let ids = Set(mods.map(\.id)).union(allGroups.map(\.id))
        selection.formIntersection(ids)
        Task { await loadNexusModInfo() }  // pictures of newly installed mods
    }

    // MARK: Enable / disable / trash

    func setEnabled(_ ids: Set<ModInfo.ID>, _ enabled: Bool) {
        // Selection follows the mods through renames (".Off" -> "Off").
        let selectedKeys = Set(mods.filter { selection.contains($0.id) }.map(Self.stableKey))
        let targets = mods.filter { ids.contains($0.id) && $0.isEnabled != enabled }
        if !targets.isEmpty {
            let name = targets.count == 1
                ? (enabled ? String(localized: "Enable \(targets[0].displayName)") : String(localized: "Disable \(targets[0].displayName)"))
                : (enabled ? String(localized: "Enable \(targets.count) Mods") : String(localized: "Disable \(targets.count) Mods"))
            registerEnabledUndo(before: enabledSnapshot, actionName: name)
        }
        let failures = toggle(targets, to: enabled)
        refresh()
        selection = selection.filter { id in allGroups.contains { $0.id == id } }
            .union(mods.filter { selectedKeys.contains(Self.stableKey($0)) }.map(\.id))
        if !failures.isEmpty {
            show("Couldn't toggle mod", detail: failures.joined(separator: "\n"))
        }
    }

    // MARK: Undo

    /// Which mods are enabled, by `stableKey` (survives the renames).
    var enabledSnapshot: Set<String> {
        Set(mods.filter(\.isEnabled).map(Self.stableKey))
    }

    /// Lets ⌘Z put the enabled mods back as they were in `before`, and ⇧⌘Z
    /// redo it. Uses the key window's undo manager, like the Edit menu.
    func registerEnabledUndo(before: Set<String>, actionName: String) {
        guard let undoManager = NSApp.keyWindow?.undoManager ?? NSApp.mainWindow?.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                let current = model.enabledSnapshot
                model.registerEnabledUndo(before: current, actionName: actionName)
                model.restoreEnabled(before)
            }
        }
        undoManager.setActionName(actionName)
    }

    /// Enables exactly the mods in `snapshot` (by stable key).
    func restoreEnabled(_ snapshot: Set<String>) {
        let selectedKeys = Set(mods.filter { selection.contains($0.id) }.map(Self.stableKey))
        // Disable first, then enable (enabling may rename folders).
        var failures = toggle(mods.filter { $0.isEnabled && !snapshot.contains(Self.stableKey($0)) }, to: false)
        failures += toggle(mods.filter { !$0.isEnabled && snapshot.contains(Self.stableKey($0)) }, to: true)
        refresh()
        selection = selection.filter { id in allGroups.contains { $0.id == id } }
            .union(mods.filter { selectedKeys.contains(Self.stableKey($0)) }.map(\.id))
        if !failures.isEmpty {
            show("Couldn't toggle mod", detail: failures.joined(separator: "\n"))
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
    func toggle(_ targets: [ModInfo], to enabled: Bool) -> [String] {
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

    /// Moves mods to the Trash. Afterwards, requirements that nothing else
    /// uses anymore are offered for removal (`suggestUnused`).
    func moveToTrash(_ targets: [ModInfo], suggestUnused: Bool = true) {
        guard let manager else { return }
        let groupsBefore = allGroups
        var failures: [String] = []
        var trashed: [ModInfo] = []
        for mod in targets {
            do {
                try manager.moveToTrash(mod)
                trashed.append(mod)
            } catch {
                failures.append("\(mod.displayName): \(error.localizedDescription)")
            }
        }
        refresh()
        if !failures.isEmpty {
            show("Couldn't move to Trash", detail: failures.joined(separator: "\n"))
        } else if suggestUnused, !trashed.isEmpty {
            // Other parts of a partly deleted multi-part mod aren't "unused".
            let trashedIDs = Set(trashed.map(\.id))
            let siblings = Set(groupsBefore.filter { $0.isGroup && $0.mods.contains { trashedIDs.contains($0.id) } }.flatMap { $0.mods.map(\.id) })
            // Name removed parts by their group ("East Scarp", not "East Scarp: Locations").
            func label(_ name: String) -> String {
                groupsBefore.first { $0.isGroup && $0.mods.contains { $0.displayName == name } }?.name ?? name
            }
            func labels(_ names: [String]) -> [String] {
                var seen = Set<String>()
                return names.map(label).filter { seen.insert($0).inserted }
            }
            let unused = UnusedRequirements.find(removed: trashed, remaining: mods)
                .filter { !siblings.contains($0.mod.id) }
                .map { UnusedRequirement(mod: $0.mod, neededBy: labels($0.neededBy)) }
            if !unused.isEmpty {
                unusedRequirementsPrompt = UnusedRequirementsPrompt(removedNames: labels(trashed.map(\.displayName)), items: unused)
            }
        }
    }

    // MARK: Groups, duplicates, rollback


    /// Groups with members matching the filter (whole groups when not filtering).
    /// Installed list: only the mods in the profile in use (the enabled
    /// ones), hiding the rest of the library.
    var showProfileModsOnly = UserDefaults.standard.bool(forKey: Preferences.showProfileModsOnly) {
        didSet { UserDefaults.standard.set(showProfileModsOnly, forKey: Preferences.showProfileModsOnly) }
    }

    var visibleGroups: [ModGroup] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let groups = showProfileModsOnly ? allGroups.filter { $0.mods.contains(where: \.isEnabled) } : allGroups
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
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
            show("Couldn't Revert", detail: error.localizedDescription)
        }
        refresh()
        Task { await checkForUpdates() }
    }

    // MARK: Helpers

    /// Maps `items` with up to `limit` requests in flight, keeping order.
    static func concurrentMap<T: Sendable, R: Sendable>(
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

    // MARK: Finder / web / Steam

    func openModsFolder() {
        if let url = manager?.modsURL { NSWorkspace.shared.open(url) }
    }

    func revealInFinder(_ targets: [ModInfo]) {
        NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.folderURL))
    }

    /// On macOS, SMAPI's installer replaces the game's own launcher, so a
    /// normal Steam launch already runs through SMAPI.
    /// Starts the game through Steam, first backing up the saves when the
    /// mods changed since the last Play (see `backUpSavesIfModsChanged`).
    func launchGame() {
        Task {
            guard await backUpSavesIfModsChanged() else { return }
            if let url = URL(string: "steam://rungameid/\(AppConstants.steamAppID)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Shows an alert. Both texts are looked up in the String Catalog.
    func show(_ title: String.LocalizationValue, _ body: String.LocalizationValue) {
        message = UserMessage(title: String(localized: title), body: String(localized: body))
    }

    /// Shows an alert whose body is already final text (e.g. a system error).
    func show(_ title: String.LocalizationValue, detail: String) {
        message = UserMessage(title: String(localized: title), body: detail)
    }

    /// Shows an alert with an already-localized title and body.
    func show(localizedTitle title: String, detail: String) {
        message = UserMessage(title: title, body: detail)
    }
}
