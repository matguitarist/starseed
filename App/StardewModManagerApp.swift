import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by the app once its model exists; opens the Updates section.
    var showUpdates: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    /// With the menu bar icon on, closing the window keeps the app (and its
    /// background update checks) running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !Preferences.bool(Preferences.showMenuBarIcon, default: false)
    }

    // Clicking an update notification opens the Updates section.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { showUpdates?() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct StardewModManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    @AppStorage(Preferences.showMenuBarIcon) private var showMenuBarIcon = false

    var body: some Scene {
        Window("Stardew Mod Manager", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 500)
                .task {
                    model.start()
                    model.startBackgroundChecks()
                    appDelegate.showUpdates = { [model] in
                        model.sidebarSelection = .updates
                        NSApp.activate()
                    }
                }
                // nxm:// links from Nexus "Mod Manager Download", and archives opened with the app.
                .onOpenURL { model.handleOpenURL($0) }
        }
        .defaultSize(width: 1180, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Install Mods…") { model.presentInstallPanel() }
                    .keyboardShortcut("o")
                    .disabled(model.manager == nil)
            }
            CommandMenu("Mods") {
                Button("Refresh") { model.refresh() }
                    .keyboardShortcut("r")
                Button("Check for Updates") { Task { await model.checkForUpdates() } }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                    .disabled(model.isCheckingUpdates)
                Divider()
                Button("Open Mods Folder") { model.openModsFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Change Mods Folder…") { model.chooseModsFolder() }
                Divider()
                Button("Launch Stardew Valley") { model.launchGame() }
                    .keyboardShortcut("l")
            }
        }

        Window("Nexus Mods", id: BrowserWindow.id) {
            BrowserView()
                .environment(model)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 1180, height: 820)

        MenuBarExtra("Stardew Mod Manager", systemImage: "leaf.fill", isInserted: $showMenuBarIcon) {
            MenuBarContent()
                .environment(model)
        }

        Settings {
            SettingsView()
                .opensWebLinksInApp()  // must be inside .environment(model): it reads the model
                .environment(model)
        }
    }
}
