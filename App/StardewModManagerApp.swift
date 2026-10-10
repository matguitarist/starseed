import AppKit
import ModManagerCore
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by the app once its model exists: opens what a notification is
    /// about ("log", "crash-log", or the Updates section by default).
    var openFromNotification: ((String?) -> Void)?

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
        let target = response.notification.request.content.userInfo["open"] as? String
        await MainActor.run { openFromNotification?(target) }
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
        Window("Starseed", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 500)
                .task {
                    model.start()
                    model.startBackgroundChecks()
                    model.startWatchingGame()
                    appDelegate.openFromNotification = { [model] target in
                        switch target {
                        case "log": model.openLogFromNotification(crash: false)
                        case "crash-log": model.openLogFromNotification(crash: true)
                        default:
                            model.sidebarSelection = .updates
                            NSApp.activate()
                        }
                    }
                }
                // nxm:// links from Nexus "Mod Manager Download", and archives opened with the app.
                .onOpenURL { model.handleOpenURL($0) }
        }
        .defaultSize(width: 1180, height: 700)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Starseed") { AboutPanel.show() }
            }
            if appUpdater.isConfigured {
                CommandGroup(after: .appInfo) {
                    Button("Check for App Updates…") { appUpdater.checkForUpdates() }
                }
            }
            CommandGroup(replacing: .help) {
                HelpCommands()
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
                Divider()
                Button("Find a Broken Mod…") { model.showBisect = true }
                    .disabled(model.manager == nil)
            }
        }

        Window("Starseed Help", id: HelpView.windowID) {
            HelpView()
                .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 900, height: 640)

        Window("Nexus Mods", id: BrowserWindow.id) {
            BrowserView()
                .environment(model)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 1180, height: 820)

        MenuBarExtra("Starseed", systemImage: "leaf.fill", isInserted: $showMenuBarIcon) {
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
@MainActor
enum AboutPanel {
    static func show() {
        let credits = NSMutableAttributedString(
            string: String(localized: "Mod manager for Stardew Valley.") + "\n\n" + String(localized: "Mod updates and info come from SMAPI's web API and Nexus Mods. Not affiliated with ConcernedApe, SMAPI or Nexus Mods."),
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        // The project page, as a link (not translated: it's an address).
        credits.append(NSAttributedString(string: "\n\n", attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]))
        credits.append(NSAttributedString(string: "github.com/matguitarist/starseed", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .link: AppLinks.repository,
        ]))
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

enum AppLinks {
    static let repository = URL(string: "https://github.com/matguitarist/starseed")!
    static let newIssue = URL(string: "https://github.com/matguitarist/starseed/issues/new/choose")!
}
