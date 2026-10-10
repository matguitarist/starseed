import AppKit
import ModManagerCore
import SwiftUI

extension ModStatus {
    var color: Color {
        switch self {
        case .enabled: .green
        case .disabled: .secondary
        case .missingDependency, .needsNewerSMAPI: .orange
        case .duplicate: .red
        case .missingManifest, .manifestError: .red
        }
    }
}

struct InstalledView: View {
    @AppModelEnvironment private var model
    @State private var sortOrder = [KeyPathComparator(\ModRow.name, comparator: .localizedStandard)]
    @State private var showInspector = true
    @State private var showProfiles = false
    @FocusState private var isFilterFocused: Bool
    @AppStorage(Preferences.showModPictures) private var showModPictures = true

    var body: some View {
        modTable
        .background {
            TableScroller(index: model.scrollTarget.flatMap { target in rows.firstIndex { $0.id == target } }) {
                model.scrollTarget = nil
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                BisectBanner()
                SMAPIBanner()
                DuplicatesBanner()
                filterBar
            }
        }
        .navigationTitle("Installed")
        .navigationSubtitle(model.summary)
        .toolbar { toolbar }
        .inspector(isPresented: $showInspector) {
            ModDetailView()
                .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
        }
        .sheet(isPresented: $showProfiles) {
            ProfilesView()
        }
    }

    // MARK: Filter

    /// Sits right above the table. A toolbar search field would end up over
    /// the inspector column, away from the list it filters.
    private var filterBar: some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter by name, author, or ID", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .focused($isFilterFocused)
                    .onExitCommand { model.searchText = ""; isFilterFocused = false }
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear filter")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 360)
            Spacer()
            // ⌘F focuses the filter, like a toolbar search field would.
            Button("Find") { isFilterFocused = true }
                .keyboardShortcut("f")
                .hidden()
                .frame(width: 0, height: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: Table

    private var rows: [ModRow] {
        model.visibleGroups.map { ModRow(group: $0) }.sorted(using: sortOrder)
    }

    private var modTable: some View {
        @Bindable var model = model

        return Table(rows, children: \.children, selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn("On") { row in
                EnableCheckbox(row: row)
            }
            .width(46)  // room for the group disclosure arrow

            TableColumn("Name", value: \.name, comparator: .localizedStandard) { row in
                HStack(spacing: 6) {
                    if showModPictures {
                        ModPicture(url: model.nexusInfo(for: row.mods)?.thumbnailURL)
                            .frame(width: 34, height: 20)
                    }
                    Circle()
                        .fill(row.status.color)
                        .frame(width: 8, height: 8)
                    if row.isGroup {
                        Image(systemName: row.isFolder ? "folder.fill" : "square.stack.3d.up.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(row.name)
                        .fontWeight(row.isGroup ? .semibold : .regular)
                        .foregroundStyle(row.enabledState == .off ? .secondary : .primary)
                        .layoutPriority(1)  // truncate the note before the name
                    if row.isGroup {
                        Text("\(row.memberCount) parts").font(.caption).foregroundStyle(.secondary)
                    } else if let note = row.folderNote {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if row.mods.contains(where: model.hasOptionalExtras) {
                        Image(systemName: "plus.square.on.square")
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .help("Has optional content: see Optional Files or optional requirements in the details panel")
                    }
                }
                .help(row.statusText)
            }
            .width(min: 160, ideal: 300)

            TableColumn("Version", value: \.version, comparator: .localizedStandard) { row in
                Text(row.version).monospacedDigit()
            }
            .width(min: 50, ideal: 80)

            TableColumn("Activity") { row in
                ActivityCell(mods: row.mods)
            }
            .width(min: 110, ideal: 160)

            TableColumn("Author", value: \.author, comparator: .localizedStandard)
                .width(min: 80, ideal: 140)

            TableColumn("Status", value: \.statusText) { row in
                Text(row.statusText).foregroundStyle(row.statusColor)
                    .help(row.statusText)
            }
            .width(min: 90, ideal: 140)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            let modIDs = model.modIDs(expanding: ids)
            let targets = model.mods.filter { modIDs.contains($0.id) }
            if !targets.isEmpty {
                Button("Enable") { model.setEnabled(modIDs, true) }
                Button("Disable") { model.setEnabled(modIDs, false) }
                Divider()
                Button("Show in Finder") { model.revealInFinder(targets) }
                if let nexusID = targets.lazy.compactMap({ model.nexusID(for: $0) }).first {
                    Link("Open Nexus Page", destination: NexusClient.modPageURL(nexusID))
                }
                Divider()
                Button("Move to Trash…", role: .destructive) { model.pendingTrash = targets }
            }
        } primaryAction: { _ in
            showInspector = true
        }
        .onDeleteCommand {
            let ids = model.modIDs(expanding: model.selection)
            model.pendingTrash = model.mods.filter { ids.contains($0.id) }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.presentInstallPanel()
            } label: {
                Label("Install Mods", systemImage: "square.and.arrow.down")
            }
            .help("Install mods from downloaded archives (or drop them on the window)")
            .disabled(model.manager == nil || model.isInstalling)

            if model.isCheckingUpdates {
                ProgressView()
                    .controlSize(.small)
                    .help("Checking for updates…")
            } else {
                Button {
                    model.refresh()
                    model.detectSMAPI()
                    Task { await model.checkForUpdates() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Rescan the Mods folder and check for updates")
            }

            Button {
                showProfiles = true
            } label: {
                Label("Profiles", systemImage: "person.2")
            }
            .help("Save and switch between sets of enabled mods")
            .disabled(model.manager == nil)

            Button {
                model.openModsFolder()
            } label: {
                Label("Open Mods Folder", systemImage: "folder")
            }
            .help("Open the Mods folder in Finder")

            Button {
                model.launchGame()
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .help("Launch Stardew Valley via Steam")
        }
        ToolbarItem {
            Button {
                showInspector.toggle()
            } label: {
                Label("Details", systemImage: "sidebar.trailing")
            }
            .help("Show or hide mod details")
        }
    }
}

/// Warns when SMAPI is missing or outdated, or mods need a newer SMAPI.
struct SMAPIBanner: View {
    @AppModelEnvironment private var model

    var body: some View {
        if let message {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(message.title).font(.headline)
                    if let detail = message.detail {
                        Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                SMAPIInstallButton(prominent: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.12))
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var message: (title: String, detail: String?)? {
        guard model.manager != nil else { return nil }
        guard let smapi = model.smapi else {
            return (String(localized: "SMAPI isn't installed"), String(localized: "Mods only load through SMAPI, the mod loader. Starseed can install it for you."))
        }
        if !smapi.isLauncherHooked {
            return (String(localized: "The game will start without mods"), String(localized: "A game update replaced SMAPI's launcher. Reinstall SMAPI to connect it again; your mods and settings stay as they are."))
        }
        let needing = model.modsNeedingNewerSMAPI
        if model.isSMAPIOutdated, let installed = smapi.version, let latest = model.latestSMAPIVersion {
            let names = needing.map(\.displayName).joined(separator: ", ")
            let detail = needing.isEmpty ? nil
                : needing.count == 1 ? String(localized: "This mod needs the newer version: \(names)")
                : String(localized: "These mods need the newer version: \(names)")
            return (String(localized: "SMAPI \(installed.description) installed — \(latest.description) is available"), detail)
        }
        if !needing.isEmpty {
            let title = needing.count == 1 ? String(localized: "A mod needs a newer SMAPI") : String(localized: "\(needing.count) mods need a newer SMAPI")
            return (title, needing.map(\.displayName).joined(separator: ", "))
        }
        return nil
    }
}

struct FolderSetupView: View {
    @AppModelEnvironment private var model

    var body: some View {
        ContentUnavailableView {
            Label("Choose Your Mods Folder", systemImage: "folder.badge.questionmark")
        } description: {
            if model.defaultFolderExists {
                Text("Found a Stardew Valley Mods folder at:\n\(AppConstants.defaultSteamModsURL.path(percentEncoded: false))")
            } else {
                Text("Not sure where it is? Launch the game through SMAPI once — its log prints a line like “Mods go here: …”.")
            }
        } actions: {
            if model.defaultFolderExists {
                Button("Use This Folder") { model.use(modsFolder: AppConstants.defaultSteamModsURL) }
                    .buttonStyle(.borderedProminent)
            }
            Button("Choose Folder…") { model.chooseModsFolder() }
        }
    }
}

/// A row of the Installed table: a single mod, or a group of parts with the
/// parts as its children.
struct ModRow: Identifiable {
    enum EnabledState { case on, off, mixed }

    let id: String
    let name: String
    let version: String
    let author: String
    let mods: [ModInfo]
    let isGroup: Bool
    let isFolder: Bool
    let children: [ModRow]?

    init(group: ModGroup) {
        guard group.isGroup else {
            self = ModRow(mod: group.mods[0])
            return
        }
        id = group.id
        name = group.name
        isGroup = true
        isFolder = group.isFolder
        folderNote = nil
        mods = group.mods
        children = group.mods.map { ModRow(mod: $0, folderNote: true) }
        let versions = Set(group.mods.map(\.version))
        version = versions.count == 1 ? versions.first! : (group.mods.first?.version ?? "")
        let authors = Set(group.mods.map(\.author))
        author = authors.count == 1 ? authors.first! : (group.mods.first?.author ?? "")
    }

    /// For parts of a group: the manifest name, shown next to the folder name.
    let folderNote: String?

    init(mod: ModInfo, folderNote showFolder: Bool = false) {
        id = mod.id
        // Parts are named by folder ("[CP] …", "… Code"), which tells them
        // apart; the manifest name moves to the note when it differs.
        name = showFolder && mod.hasManifest ? mod.bareFolderName : mod.displayName
        folderNote = showFolder && mod.bareFolderName != mod.displayName ? mod.displayName : nil
        version = mod.version
        author = mod.author
        mods = [mod]
        isGroup = false
        isFolder = false
        children = nil
    }

    var memberCount: Int { mods.count }

    var enabledState: EnabledState {
        let enabled = mods.filter(\.isEnabled).count
        return enabled == mods.count ? .on : (enabled == 0 ? .off : .mixed)
    }

    /// The most serious status among the parts.
    var status: ModStatus {
        let order: [ModStatus] = [.missingManifest, .manifestError, .duplicate, .missingDependency, .needsNewerSMAPI, .enabled, .disabled]
        let statuses = Set(mods.map(\.status))
        if isGroup, enabledState == .mixed, !statuses.contains(where: { order.firstIndex(of: $0)! < 5 }) { return .disabled }
        return order.first { statuses.contains($0) } ?? .enabled
    }

    var statusText: String {
        if isGroup, enabledState == .mixed, status == .disabled {
            return String(localized: "\(mods.filter(\.isEnabled).count) of \(mods.count) enabled")
        }
        return status.title
    }

    var statusColor: Color {
        isGroup && enabledState == .mixed && status == .disabled ? .orange : status.color
    }
}

/// Checkbox for a mod or a whole group (shows a dash when only some parts are on).
private struct EnableCheckbox: View {
    @AppModelEnvironment private var model
    let row: ModRow

    var body: some View {
        if row.isGroup {
            Button {
                model.setEnabled(Set(row.mods.map(\.id)), row.enabledState != .on)
            } label: {
                Image(systemName: row.enabledState == .on ? "checkmark.square.fill" : (row.enabledState == .mixed ? "minus.square.fill" : "square"))
                    .foregroundStyle(row.enabledState == .off ? Color.secondary : Color.accentColor)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help(row.enabledState == .on ? "Disable all parts" : "Enable all parts")
        } else if let mod = row.mods.first {
            Toggle("Enabled", isOn: Binding(get: { mod.isEnabled }, set: { model.setEnabled([mod.id], $0) }))
                .labelsHidden()
        }
    }
}

/// Warns about mods installed twice (SMAPI skips both copies).
struct DuplicatesBanner: View {
    @AppModelEnvironment private var model

    var body: some View {
        let groups = model.duplicateGroups
        if !groups.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc.fill").foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(groups.count == 1 ? "A mod is installed twice" : "\(groups.count) mods are installed twice").font(.headline)
                    Text("SMAPI won't load either copy: \(groups.map { copies in "\(copies[0].displayName) (\(copies.map(\.relativePath).joined(separator: ", ")))" }.joined(separator: "; "))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Keep Newest") { model.fixDuplicates() }
                    .help("Keep the newest copy of each and move the others to the Trash")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.red.opacity(0.1))
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

/// Scrolls the enclosing table to a top-level row when `index` is set.
/// SwiftUI's scrollTo doesn't reach Table rows, and the AppKit table's
/// selection can lag, so this counts top-level rows itself (groups may be
/// expanded above the target).
private struct TableScroller: NSViewRepresentable {
    let index: Int?
    let done: () -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard let index else { return }
        // After this update reaches the table.
        DispatchQueue.main.async {
            if let table = Self.table(near: view), let row = Self.row(forTopLevel: index, in: table) {
                table.scrollRowToVisible(row)
            }
            done()
        }
    }

    private static func row(forTopLevel index: Int, in table: NSTableView) -> Int? {
        guard let outline = table as? NSOutlineView else {
            return index < table.numberOfRows ? index : nil
        }
        var topLevel = -1
        for row in 0..<outline.numberOfRows where outline.level(forRow: row) == 0 {
            topLevel += 1
            if topLevel == index { return row }
        }
        return nil
    }

    /// The nearest table: the first ancestor that contains one (the
    /// sidebar's list sits further up, in another column).
    private static func table(near view: NSView) -> NSTableView? {
        var ancestor = view.superview
        while let current = ancestor {
            if let table = firstTable(in: current) { return table }
            ancestor = current.superview
        }
        return nil
    }

    private static func firstTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for subview in view.subviews {
            if let table = firstTable(in: subview) { return table }
        }
        return nil
    }
}

/// Installs, updates or reconnects SMAPI in one click, with "Download Page"
/// for doing it by hand.
struct SMAPIInstallButton: View {
    @AppModelEnvironment private var model
    var prominent = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if model.smapiInstallPhase != nil {
                    ProgressView().controlSize(.small)
                } else if prominent {
                    Button(title) { model.installSMAPI() }.buttonStyle(.borderedProminent)
                } else {
                    Button(title) { model.installSMAPI() }
                }
            }
            .help("Downloads SMAPI's official installer from GitHub and runs it for your game. Quit the game first.")
            Menu {
                Button("Open SMAPI's Download Page") { model.getSMAPI() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Install SMAPI yourself instead")
        }
        .disabled(model.smapiInstallPhase != nil)
    }

    private var title: String {
        guard let smapi = model.smapi else { return String(localized: "Install SMAPI") }
        if !smapi.isLauncherHooked { return String(localized: "Reinstall SMAPI") }
        if let latest = model.latestSMAPIVersion, model.isSMAPIOutdated { return String(localized: "Update SMAPI to \(latest.description)") }
        return String(localized: "Update SMAPI")
    }
}
