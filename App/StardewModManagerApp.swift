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
    private let appUpdater = AppUpdater.shared
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
            CommandGroup(replacing: .appInfo) {
                Button("About Stardew Mod Manager") { AboutPanel.show() }
            }
            if appUpdater.isConfigured {
                CommandGroup(after: .appInfo) {
                    Button("Check for App Updates…") { appUpdater.checkForUpdates() }
                }
            }
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

/// The standard About panel, with the icon passed in explicitly (macOS can
/// show a stale generic icon for a rebuilt app) and a short credit line.
enum AboutPanel {
    static func show() {
        let credits = NSMutableAttributedString(
            string: String(localized: "Mod updates and info come from SMAPI's web API and Nexus Mods. Not affiliated with ConcernedApe, SMAPI or Nexus Mods."),
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        credits.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: credits.length))
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.credits: credits]
        if let icon = NSImage(named: "AppIcon") ?? NSImage(named: NSImage.applicationIconName) {
            options[.applicationIcon] = icon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate()
    }
}
