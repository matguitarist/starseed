// The app's menus beyond macOS's standard ones: File → Install Mods,
// View (pages, details panel, pictures), Mods and Game.

import ModManagerCore
import SwiftUI

struct AppCommands: Commands {
    let model: AppModel
    let appUpdater: AppUpdater

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Starseed") { AboutPanel.show() }
        }
        if appUpdater.isConfigured {
            CommandGroup(after: .appInfo) {
                Button("Check for App Updates…") { appUpdater.checkForUpdates() }
            }
        }
        CommandGroup(replacing: .help) {
            HelpCommands(model: model)
        }
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

/// View: the sidebar's pages (⌘1–⌘7), the side panel, pictures.
private struct ViewMenuItems: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preferences.showModPictures) private var showModPictures = true
    @AppStorage("showLoadedMods") private var showLoadedMods = true

    private static let pages: [(item: SidebarItem, title: LocalizedStringKey)] = [
        (.installed, "Installed"), (.updates, "Updates"), (.requirements, "Requirements"),
        (.browse, "Browse Nexus"), (.collections, "Collections"),
        (.saves, "Saves"), (.log, "SMAPI Log"),
    ]

    var body: some View {
        ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, page in
            Button(page.title) { showPage(page.item, model: model, openWindow: openWindow) }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                .disabled(model.manager == nil)
        }
        Divider()
        // The panel at the right of the page you're on: mod details, or the
        // mods SMAPI loaded on the SMAPI Log page.
        if model.sidebarSelection == .log {
            Button(showLoadedMods ? "Hide Loaded Mods" : "Show Loaded Mods") { showLoadedMods.toggle() }
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
        Button("Check for Updates") { Task { await model.checkForUpdates() } }
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
