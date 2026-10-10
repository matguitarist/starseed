// After the game closes, reads SMAPI's new log and posts a notification
// when something went wrong: mods that didn't load, errors, conflicts, or a
// crash. Clicking it opens the SMAPI Log section.

import AppKit
import ModManagerCore
import UserNotifications

extension AppModel {
    static let gameProcessNames: Set<String> = ["Stardew Valley", "StardewValley", "StardewModdingAPI"]

    static func isGame(_ app: NSRunningApplication) -> Bool {
        [app.localizedName, app.executableURL?.lastPathComponent].compactMap { $0 }.contains(where: gameProcessNames.contains)
    }

    func startWatchingGame() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  MainActor.assumeIsolated({ Self.isGame(app) })  // queue: .main
            else { return }
            let launched = app.launchDate ?? Date(timeIntervalSinceNow: -24 * 60 * 60)
            Task { @MainActor in
                self?.detectSMAPI()  // a game update may have disconnected it
                await self?.reportOnSession(launchedAt: launched)
            }
        }
        // Steam may have queued or installed a game update meanwhile.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let folder = self.gameFolder else { return }
                self.steamGame = SteamGameState.read(gameFolder: folder)
            }
        }
    }

    /// Reads the log of the session that just ended. SMAPI finishes writing
    /// as the game quits, so wait a moment first.
    func reportOnSession(launchedAt launched: Date) async {
        guard Preferences.bool(Preferences.reportAfterPlaying, default: true) else { return }
        try? await Task.sleep(for: .seconds(2))
        let logURL = SMAPILog.latestLogURL
        guard Self.modified(logURL, since: launched) else { return }  // played without SMAPI
        let crashed = Self.modified(SMAPILog.crashLogURL, since: launched)
        guard let log = try? await Task.detached(operation: { try SMAPILog.load(from: logURL) }).value else { return }
        setLogConflicts(from: log.insights)
        let report = log.playReport(crashed: crashed)
        guard !report.isEmpty else { return }
        lastPlayReport = report
        await post(report)
    }

    private static func modified(_ url: URL, since date: Date) -> Bool {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return modified.map { $0 >= date.addingTimeInterval(-5) } ?? false
    }

    private func post(_ report: PlayReport) async {
        let content = UNMutableNotificationContent()
        content.title = report.crashed ? String(localized: "Stardew Valley crashed") : String(localized: "Some mods had problems")
        content.body = Self.summary(of: report)
        content.sound = .default
        content.userInfo = ["open": report.crashed ? "crash-log" : "log"]
        let request = UNNotificationRequest(identifier: "play-report-\(UUID().uuidString)", content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        try? await center.add(request)
    }

    /// "Better Crafting didn't load. Lookup Anything had errors. Click to see why."
    static func summary(of report: PlayReport) -> String {
        func names(_ list: [String]) -> String {
            list.count <= 2 ? list.formatted(.list(type: .and))
                : String(localized: "\(list.prefix(2).formatted(.list(type: .and))) and \(list.count - 2) more")
        }
        var parts: [String] = []
        if !report.notLoaded.isEmpty {
            parts.append(String(localized: "\(names(report.notLoaded)) didn't load."))
        }
        if !report.withErrors.isEmpty {
            parts.append(String(localized: "\(names(report.withErrors)) had errors."))
        }
        if report.conflicts > 0 {
            parts.append(report.conflicts == 1 ? String(localized: "2 mods conflict.") : String(localized: "\(report.conflicts) mod conflicts."))
        }
        parts.append(String(localized: "Click to see what SMAPI says."))
        return parts.joined(separator: " ")
    }

    /// Opens the SMAPI Log section from a notification.
    func openLogFromNotification(crash: Bool) {
        requestedLogURL = crash ? SMAPILog.crashLogURL : SMAPILog.latestLogURL
        sidebarSelection = .log
        NSApp.activate()
    }
}
