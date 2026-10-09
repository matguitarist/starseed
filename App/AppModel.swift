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

    var searchText = ""
    var selection: Set<ModInfo.ID> = []
    var needsFolderSetup = false
    var message: UserMessage?
    var conflictPrompt: ConflictPrompt?
    var pendingTrash: [ModInfo] = []

    /// Previous versions of mods, for "Revert".
    let modArchive = ModArchive()

    // Nexus account data (AppModel+Nexus).
    var endorsements: [Int: NexusClient.EndorsementStatus] = [:]
    var trackedMods: Set<Int> = []
    /// Nexus file lists by mod number, fetched once per session.
    var nexusFiles: [Int: [NexusFile]] = [:]

    /// Which profile/collection each save uses (AppModel+Saves).
    var saveLinks: [String: SaveModSet] = [:]

    // My Collections (AppModel+Profiles).
    let modListStore = ModListStore()
    var modLists: [ModList] = []

    // Derived from `mods` (and update data), stored rather than computed:
    // views read these many times per redraw. See `recomputeDerived()`.
    private(set) var enabledIDs: Set<String> = []
    private(set) var allGroups: [ModGroup] = []
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
        profiles = configStore.loadProfiles()
        saveLinks = configStore.loadSaveLinks()
        loadModLists()
        if let saved = configStore.modsURL(), FileManager.default.fileExists(atPath: saved.path(percentEncoded: false)) {
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
                try configStore.setModsURL(url)
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

    // MARK: Groups, duplicates, rollback


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
    func launchGame() {
        if let url = URL(string: "steam://rungameid/\(AppConstants.steamAppID)") {
            NSWorkspace.shared.open(url)
        }
    }

    func show(_ title: String, _ body: String) {
        message = UserMessage(title: title, body: body)
    }
}
