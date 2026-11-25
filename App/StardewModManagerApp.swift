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
        AppTheme.current.apply()
    }

    /// With the menu bar icon on, closing the window keeps the app (and its
    /// background update checks) running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !Preferences.bool(Preferences.showMenuBarIcon, default: true)
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
    @AppStorage(Preferences.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        Window("Starseed", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1080, minHeight: 560)
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
        .defaultSize(width: 1240, height: 760)
        .commands {
            StandardCommands(app: "Starseed", repository: "matguitarist/starseed",
                             updates: AppUpdates(isAvailable: appUpdater.isConfigured) { appUpdater.checkForUpdates() },
                             about: { AboutPanel.show(StarseedAbout.credits) },
                             help: .window(HelpView.windowID)) {
                HelpCommands(model: model)
            }
            PageCommands(pages: SidebarItem.menuPages, title: \.menuTitle, isEnabled: model.manager != nil) {
                model.sidebarSelection = $0
            }
            AppMenus(model: model)
        }

        Window("Starseed Help", id: HelpView.windowID) {
            HelpView()
                .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 900, height: 640)
        .commandsRemoved()  // opened from the Help menu, not listed under Window

        Window("Nexus Mods", id: BrowserWindow.id) {
            BrowserView()
                .environment(model)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 1180, height: 820)

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarContent()
                .environment(model)
        } label: {
            // The number of mod updates next to the leaf, when there are some.
            let updates = model.modsWithUpdates.count
            if updates > 0 {
                Label("\(updates)", systemImage: "leaf.fill")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "leaf.fill")
            }
        }

        Settings {
            SettingsView()
                .opensWebLinksInApp()  // must be inside .environment(model): it reads the model
                .environment(model)
        }
    }
}

/// About Starseed's credits, under the shared About panel's icon, name and version.
@MainActor
enum StarseedAbout {
    static var credits: [AboutPanel.Credit] {
        [
            .text(String(localized: "Mod manager for Stardew Valley.")),
            .text(String(localized: "Mod updates and info come from SMAPI's web API and Nexus Mods. Not affiliated with ConcernedApe, SMAPI or Nexus Mods.")),
            // The project page (not translated: it's an address).
            .links([("github.com/matguitarist/starseed", URL(string: "https://github.com/matguitarist/starseed")!)]),
        ]
    }
}
