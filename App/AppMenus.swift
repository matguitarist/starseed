// The app's own menus: File → Install Mods, View (details panel, pictures), Mods and Game.
// About, Check for Updates…, Help and the pages (⌘1–⌘7) are the shared AppCommands.swift.

import ModManagerCore
import SwiftUI

struct AppMenus: Commands {
    let model: AppModel

    var body: some Commands {
        // The items are views: unlike a Commands body, a view body is
        // re-evaluated when the model changes, so titles and enabled states
        // stay current.
        CommandGroup(replacing: .newItem) { FileMenuItems(model: model) }
        CommandGroup(before: .sidebar) { ViewMenuItems(model: model) }
        CommandMenu("Mods") { ModsMenuItems(model: model) }
        CommandMenu("Game") { GameMenuItems(model: model) }
    }
}

/// Selects a page, reopening the main window if it was closed.
@MainActor
private func showPage(_ item: SidebarItem, model: AppModel, openWindow: OpenWindowAction) {
    model.sidebarSelection = item
    openWindow(id: "main")
}

private struct FileMenuItems: View {
    let model: AppModel

    var body: some View {
        Button("Install Mods…") { model.presentInstallPanel() }
            .keyboardShortcut("o")
            .disabled(model.manager == nil)
    }
}

extension SidebarItem {
    /// The sidebar's pages, in its order, for View's ⌘1–⌘7 (PageCommands).
    static let menuPages: [SidebarItem] = [.installed, .updates, .requirements, .browse, .collections, .saves, .log]

    var menuTitle: String {
        switch self {
        case .installed: String(localized: "Installed")
        case .updates: String(localized: "Updates")
        case .requirements: String(localized: "Requirements")
        case .browse: String(localized: "Browse Nexus")
        case .collections: String(localized: "Collections")
        case .saves: String(localized: "Saves")
        case .log: String(localized: "SMAPI Log")
        }
    }
}

/// View: the side panel, pictures (the pages above them are PageCommands).
private struct ViewMenuItems: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preferences.showModPictures) private var showModPictures = true

    var body: some View {
        // The panel at the right of the page you're on: mod details, or the
        // mods SMAPI loaded on the SMAPI Log page.
        if model.sidebarSelection == .log {
            Button(model.smapiLog.showInspector ? "Hide Loaded Mods" : "Show Loaded Mods") { model.smapiLog.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        } else {
            Button(model.showInspector ? "Hide Details" : "Show Details") {
                showPage(.installed, model: model, openWindow: openWindow)
                model.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
        Toggle("Mod Pictures", isOn: $showModPictures)
        Divider()
    }
}

private struct ModsMenuItems: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Rescan Mods Folder") { model.refresh() }
            .keyboardShortcut("r")
            .disabled(model.manager == nil)
        Button("Check for Mod Updates") { Task { await model.checkForUpdates() } }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(model.isCheckingUpdates || model.manager == nil)
        Button(model.nexusUpdates.isEmpty ? String(localized: "Update All") : String(localized: "Update All (\(model.nexusUpdates.count))")) {
            model.updateAll()
        }
        .disabled(model.nexusUpdates.isEmpty)
        Button("Install Missing Requirements") {
            model.installMissingDependencies(model.missingDependencies.filter(model.isConfirmed))
        }
        .disabled(!model.missingDependencies.contains(where: model.isConfirmed))
        Divider()
        Menu("Profile") {
            ForEach(model.profileNames, id: \.self) { name in
                CheckedMenuItem(title: name, isChecked: name == model.activeProfile) { model.switchProfile(to: name) }
            }
            Divider()
            if let active = model.activeProfile, let collection = model.profileCollections[active] {
                Button("Show Collection “\(collection.name)”…") {
                    showPage(.installed, model: model, openWindow: openWindow)
                    model.showCollection(forProfile: active)
                }
            }
            Button("Manage Profiles…") {
                showPage(.installed, model: model, openWindow: openWindow)
                model.showProfiles = true
            }
        }
        .disabled(model.manager == nil)
        Divider()
        Button("Open Mods Folder") { model.openModsFolder() }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(model.manager == nil)
        Button("Change Mods Folder…") { model.chooseModsFolder() }
    }
}

private struct GameMenuItems: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Play Stardew Valley") { model.launchGame() }
            .keyboardShortcut("l")
        Divider()
        if model.smapiNeedsInstall, model.gameFolder != nil {
            Button(model.smapi == nil ? String(localized: "Install SMAPI") : String(localized: "Update SMAPI")) {
                model.installSMAPI()
            }
            .disabled(model.smapiInstallPhase != nil)
        }
        Button("Show SMAPI Log") { showPage(.log, model: model, openWindow: openWindow) }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        Button(model.bisection == nil ? String(localized: "Find a Broken Mod…") : String(localized: "Continue Finding a Broken Mod…")) {
            model.showBisect = true
        }
        .disabled(model.manager == nil)
        Divider()
        Button("Back Up All Saves") { Task { await model.backUpAllSaves() } }
        Button("Open Saves Folder") { NSWorkspace.shared.open(SaveGame.defaultFolder) }
    }
}
