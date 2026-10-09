import AppKit
import ModManagerCore
import SwiftUI
import UserNotifications

/// Preference keys (UserDefaults), shared by Settings, the app delegate and the model.
enum Preferences {
    static let autoCheckUpdates = "autoCheckUpdates"        // default on
    static let notifyUpdates = "notifyUpdates"              // default on
    static let showMenuBarIcon = "showMenuBarIcon"          // default off
    static let notifiedUpdates = "notifiedUpdates"          // ["uniqueid@version"]
    static let backupBeforePlay = "backupBeforePlay"        // default on
    static let lastPlayedModSet = "lastPlayedModSet"        // fingerprint of enabled mods at last Play

    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}

extension AppModel {
    /// Checks for updates every few hours while the app (or its menu bar
    /// icon) is running, and posts a notification for newly found ones.
    func startBackgroundChecks() {
        Task {
            while true {
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
                guard Preferences.bool(Preferences.autoCheckUpdates, default: true) else { continue }
                await checkForUpdates()
            }
        }
    }

    /// Notifies about updates that haven't been announced yet.
    func notifyAboutNewUpdates() {
        guard Preferences.bool(Preferences.notifyUpdates, default: true) else { return }
        let current = modsWithUpdates.compactMap { mod in update(for: mod).map { (mod, $0) } }
        let keys = current.map { "\($0.0.uniqueID.lowercased())@\($0.1.version)" }
        let announced = Set(UserDefaults.standard.stringArray(forKey: Preferences.notifiedUpdates) ?? [])
        let fresh = current.filter { !announced.contains("\($0.0.uniqueID.lowercased())@\($0.1.version)") }
        UserDefaults.standard.set(keys, forKey: Preferences.notifiedUpdates)  // forget ones that were installed
        guard !fresh.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = fresh.count == 1 ? String(localized: "Mod update available") : String(localized: "\(fresh.count) mod updates available")
        content.body = fresh.prefix(4).map { "\($0.0.displayName) \($0.1.version)" }.joined(separator: ", ")
            + (fresh.count > 4 ? "…" : "")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "updates-\(UUID().uuidString)", content: content, trigger: nil)

        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(request)
        }
    }
}

/// The optional menu bar icon: play, updates at a glance, open the app.
struct MenuBarContent: View {
    @AppModelEnvironment private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Play Stardew Valley") { model.launchGame() }
        Divider()
        let updates = model.modsWithUpdates.count
        Button(updates == 0 ? String(localized: "All mods up to date")
               : updates == 1 ? String(localized: "1 mod update available…")
               : String(localized: "\(updates) mod updates available…")) {
            model.sidebarSelection = .updates
            showMainWindow()
        }
        .disabled(updates == 0)
        let missing = model.missingDependencies.count
        if missing > 0 {
            Button(missing == 1 ? String(localized: "1 missing requirement…") : String(localized: "\(missing) missing requirements…")) {
                model.sidebarSelection = .requirements
                showMainWindow()
            }
        }
        Button(model.isCheckingUpdates ? "Checking…" : "Check for Updates") {
            Task { await model.checkForUpdates() }
        }
        .disabled(model.isCheckingUpdates)
        Divider()
        Button("Open Stardew Mod Manager") { showMainWindow() }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
