// Where the installed game came from, from its location and bundle.

import Foundation

public enum GameStore: String, Sendable, CaseIterable {
    case steam, gog, appStore, other

    /// "Steam", "GOG", "Mac App Store"; nil when unknown.
    public var displayName: String? {
        switch self {
        case .steam: "Steam"
        case .gog: "GOG"
        case .appStore: "Mac App Store"
        case .other: nil
        }
    }

    /// `gameFolder` is the game's Contents/MacOS folder (next to Mods).
    public static func detect(gameFolder: URL) -> GameStore {
        let fm = FileManager.default
        let path = gameFolder.standardizedFileURL.path(percentEncoded: false)
        if path.contains("/steamapps/") { return .steam }
        let contents = gameFolder.deletingLastPathComponent()  // .../Stardew Valley.app/Contents
        if fm.fileExists(atPath: contents.appending(path: "_MASReceipt/receipt").path(percentEncoded: false)) { return .appStore }
        // GOG builds ship goggame-<id>.info files and are often under "GOG Games".
        if path.localizedCaseInsensitiveContains("GOG Games") { return .gog }
        for folder in [gameFolder, contents.appending(path: "Resources")] {
            let names = (try? fm.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            if names.contains(where: { $0.hasPrefix("goggame-") }) { return .gog }
        }
        return .other
    }
}
