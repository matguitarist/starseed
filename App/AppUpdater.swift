// Updates of the app itself, through Sparkle. Off until releases are
// hosted: Info.plist needs SUFeedURL (the appcast) and SUPublicEDKey (the
// key that signs updates). See "Releasing updates" in the README.

import Sparkle
import SwiftUI

@MainActor
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    /// Whether this build knows where to look for updates.
    let isConfigured: Bool
    private let controller: SPUStandardUpdaterController?

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String) ?? ""
        let key = (info["SUPublicEDKey"] as? String) ?? ""
        isConfigured = !feed.isEmpty && !key.isEmpty
        controller = isConfigured
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
