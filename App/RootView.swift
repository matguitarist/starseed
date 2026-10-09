import ModManagerCore
import SwiftUI

enum SidebarItem: Hashable {
    case installed, updates, requirements, myCollections, browse, collections, saves, log
}

/// Window content: sidebar + the selected section, plus the app-wide drop
/// target, sheets and alerts.
struct RootView: View {
    @AppModelEnvironment private var model
    @Environment(\.openWindow) private var openWindow
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            Sidebar(selection: $model.sidebarSelection)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
        } detail: {
            if model.needsFolderSetup {
                FolderSetupView()
            } else {
                switch model.sidebarSelection ?? .installed {
                case .installed: InstalledView()
                case .updates: UpdatesView()
                case .requirements: RequirementsView()
                case .myCollections: MyCollectionsView()
                case .browse: BrowseView()
                case .collections: CollectionsView()
                case .saves: SavesView()
                case .log: LogViewerView()
                }
            }
        }
        .sheet(item: $model.nexusSheet) { request in
            NexusModSheet(request: request)
                .opensWebLinksInApp()
        }
        .sheet(item: $model.collectionSheet) { request in
            CollectionSheet(request: request)
                .opensWebLinksInApp()
        }
        .opensWebLinksInApp()
        .onChange(of: model.browserRequest) { _, request in
            if request != nil { openWindow(id: BrowserWindow.id) }
        }
        .alert(
            "Missing Requirements",
            isPresented: Binding(get: { model.requirementsPrompt != nil }, set: { if !$0 { model.requirementsPrompt = nil } }),
            presenting: model.requirementsPrompt
        ) { missing in
            Button("Install") {
                model.installMissingDependencies(missing)
                model.requirementsPrompt = nil
            }
            Button("Show Requirements") {
                model.sidebarSelection = .requirements
                model.requirementsPrompt = nil
            }
            Button("Later", role: .cancel) {}
        } message: { missing in
            Text("The mods you just installed need:\n\n" + missing.map { model.record(forDependency: $0.uniqueID)?.name ?? $0.uniqueID }.joined(separator: "\n"))
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.install(urls)
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .confirmationDialog(
            trashTitle,
            isPresented: Binding(get: { !model.pendingTrash.isEmpty }, set: { if !$0 { model.pendingTrash = [] } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                model.moveToTrash(model.pendingTrash)
                model.pendingTrash = []
            }
        } message: {
            Text("You can restore it from the Trash in Finder.")
        }
        .alert(
            "Already Installed",
            // Dismissal always goes through a button, which resolves the prompt.
            isPresented: Binding(get: { model.conflictPrompt != nil }, set: { _ in }),
            presenting: model.conflictPrompt
        ) { _ in
            Button("Replace") { model.resolveConflict(true) }
            Button("Keep Existing") { model.resolveConflict(false) }
            Button("Cancel", role: .cancel) { model.resolveConflict(nil) }
        } message: { prompt in
            Text("\(prompt.archiveName) contains mods already in your Mods folder:\n\n\(prompt.names.joined(separator: "\n"))\n\nReplace them with this version? Old versions go to the Trash and their config.json settings are kept.")
        }
        .alert(
            model.message?.title ?? "",
            isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } }),
            presenting: model.message
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message.body)
        }
    }

    private var trashTitle: String {
        let targets = model.pendingTrash
        return targets.count == 1 ? "Move '\(targets[0].displayName)' to the Trash?" : "Move \(targets.count) mods to the Trash?"
    }
}

private struct Sidebar: View {
    @AppModelEnvironment private var model
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("Installed", systemImage: "square.stack.3d.up")
                    .badge(model.mods.count)
                    .tag(SidebarItem.installed)
                Label("Updates", systemImage: "arrow.down.circle")
                    .badge(model.modsWithUpdates.count)
                    .tag(SidebarItem.updates)
                Label("Requirements", systemImage: "puzzlepiece.extension")
                    .badge(model.missingDependencies.count)
                    .tag(SidebarItem.requirements)
                Label("My Collections", systemImage: "list.bullet.rectangle")
                    .badge(model.modLists.count)
                    .tag(SidebarItem.myCollections)
            }
            Section("Get Mods") {
                Label("Browse Nexus", systemImage: "globe")
                    .tag(SidebarItem.browse)
                Label("Collections", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.collections)
            }
            Section("Game") {
                Label("Saves", systemImage: "externaldrive")
                    .tag(SidebarItem.saves)
                Label("SMAPI Log", systemImage: "text.alignleft")
                    .tag(SidebarItem.log)
            }
            if !model.downloads.isEmpty {
                Section {
                    ForEach(model.downloads) { item in
                        DownloadRow(item: item)
                    }
                } header: {
                    HStack {
                        Text("Downloads")
                        Spacer()
                        if model.downloads.contains(where: \.isFinished) {
                            Button("Clear") { model.clearFinishedDownloads() }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

enum BrowserWindow {
    static let id = "nexus-browser"
}

extension View {
    /// Sends http(s) links (Link, openURL) to the in-app Nexus browser
    /// instead of the default web browser.
    func opensWebLinksInApp() -> some View {
        modifier(OpenWebLinksInApp())
    }
}

private struct OpenWebLinksInApp: ViewModifier {
    @AppModelEnvironment private var model

    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return .systemAction }
            model.openInBrowser(url)
            return .handled
        })
    }
}
