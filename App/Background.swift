import AppKit
import ModManagerCore
import SwiftUI
import UserNotifications

/// Preference keys (UserDefaults), shared by Settings, the app delegate and the model.
enum Preferences {
    static let autoCheckUpdates = "autoCheckUpdates"        // default on
    static let notifyUpdates = "notifyUpdates"              // default on
    static let showMenuBarIcon = "showMenuBarIcon"          // default on
    static let notifiedUpdates = "notifiedUpdates"          // ["uniqueid@version"]
    static let backupBeforePlay = "backupBeforePlay"        // default on
    static let reportAfterPlaying = "reportAfterPlaying"    // default on
    static let showModPictures = "showModPictures"          // default on
    static let activeProfile = "activeProfile"              // name of the profile in use
    static let profileCollections = "profileCollections"    // profile name -> Nexus collection it came from
    static let showProfileModsOnly = "showProfileModsOnly"  // Installed list: hide mods outside the profile
    static let lastPlayedModSet = "lastPlayedModSet"        // fingerprint of enabled mods at last Play
    static let theme = "theme"                              // AppTheme: system, light or dark
    static let setupCompleted = "setupCompleted"            // the setup assistant was finished or skipped
    static let showPageTips = "showPageTips"                // default on: a tip at the top of each page
    static let seenPageTips = "seenPageTips"                // [page] whose tip was dismissed

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

/// The optional menu bar icon: the game's and SMAPI's state, play, updates
/// and profiles at a glance, without opening the window.
struct MenuBarContent: View {
    @AppModelEnvironment private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // Status (not clickable): "Stardew Valley 1.6.15 · SMAPI 4.5.2".
        Text(statusLine)
        if model.smapiNeedsInstall, model.gameFolder != nil {
            Button(model.smapi == nil ? String(localized: "Install SMAPI") : String(localized: "Update SMAPI")) {
                model.installSMAPI()
            }
            .disabled(model.smapiInstallPhase != nil)
        }
        Button("Play Stardew Valley") { model.launchGame() }
        // Each farm with the profile it's played with: switches, then launches.
        let saves = SaveGame.list()
        if !saves.isEmpty {
            Menu("Play a Farm") {
                ForEach(saves) { save in
                    Button {
                        model.play(save)
                    } label: {
                        if let profile = model.profile(forSave: save.id) {
                            Text("\(save.displayName) · \(profile)")
                        } else {
                            Text(save.displayName)
                        }
                    }
                }
            }
            .disabled(model.manager == nil)
        }
        Divider()

        let updates = model.modsWithUpdates.count
        if updates == 0 {
            Text("All mods up to date")
        } else {
            Button(updates == 1 ? String(localized: "1 mod update available…") : String(localized: "\(updates) mod updates available…")) {
                show(.updates)
            }
            if !model.nexusUpdates.isEmpty {
                Button("Update All") { model.updateAll() }
            }
        }
        let missing = model.missingDependencies.count
        if missing > 0 {
            Button(missing == 1 ? String(localized: "1 missing requirement…") : String(localized: "\(missing) missing requirements…")) {
                show(.requirements)
            }
        }
        if model.lastPlayReport != nil {
            Button("Problems in the last game session…") {
                model.openLogFromNotification(crash: model.lastPlayReport?.crashed == true)
                showMainWindow()
            }
        }
        Button(model.isCheckingUpdates ? String(localized: "Checking…") : String(localized: "Check for Updates")) {
            Task { await model.checkForUpdates() }
        }
        .disabled(model.isCheckingUpdates)
        Divider()

        if !model.profileNames.isEmpty {
            Menu(model.activeProfile.map { String(localized: "Profile: \($0)") } ?? String(localized: "Use Profile")) {
                ForEach(model.profileNames, id: \.self) { name in
                    Button {
                        model.switchProfile(to: name)
                    } label: {
                        if name == model.activeProfile {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
                Divider()
                if let active = model.activeProfile, let collection = model.profileCollections[active] {
                    Button("Show Collection “\(collection.name)”…") {
                        model.showCollection(forProfile: active)
                        showMainWindow()
                    }
                }
                Button("Manage Profiles…") {
                    model.showProfiles = true
                    showMainWindow()
                }
            }
        }
        Button(model.bisection == nil ? String(localized: "Find a Broken Mod…") : String(localized: "Continue Finding a Broken Mod…")) {
            model.showBisect = true
            showMainWindow()
        }
        .disabled(model.manager == nil)
        Divider()
        Button("Open Starseed") { showMainWindow() }
        Button("Settings…") {
            openSettings()
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Button("Quit Starseed") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        guard model.manager != nil else { return String(localized: "Choose your Mods folder in Starseed") }
        let game = model.gameVersion.map { String(localized: "Stardew Valley \($0.description)") } ?? String(localized: "Stardew Valley not found")
        let smapi = model.smapi.map { smapi in smapi.version.map { "SMAPI \($0.description)" } ?? "SMAPI" } ?? String(localized: "SMAPI not installed")
        return "\(game) · \(smapi)"
    }

    private func show(_ item: SidebarItem) {
        model.sidebarSelection = item
        showMainWindow()
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
