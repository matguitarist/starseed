// What Steam knows about the installed game: its appmanifest file
// (steamapps/appmanifest_413150.acf) says whether an update is waiting.

import Foundation

public struct SteamGameState: Sendable, Equatable {
    public static let appID = 413150

    public let buildID: String?
    /// Steam has a newer build to download (it updates the game itself,
    /// usually the next time Steam runs or the game is launched).
    public let updatePending: Bool

    public init(buildID: String?, updatePending: Bool) {
        self.buildID = buildID
        self.updatePending = updatePending
    }

    /// Reads the manifest for a game folder inside a Steam library
    /// (".../steamapps/common/Stardew Valley/Contents/MacOS"). Nil when the
    /// game isn't installed through Steam.
    public static func read(gameFolder: URL) -> SteamGameState? {
        var folder = gameFolder
        while folder.pathComponents.count > 1, folder.lastPathComponent != "steamapps" {
            folder.deleteLastPathComponent()
        }
        guard folder.lastPathComponent == "steamapps",
              let text = try? String(contentsOf: folder.appending(path: "appmanifest_\(appID).acf"), encoding: .utf8)
        else { return nil }
        return parse(text)
    }

    /// Valve's KeyValues text: `"key"		"value"` lines.
    static func parse(_ text: String) -> SteamGameState {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            // `	"key"		"value"` splits into ["\t", key, "\t\t", value, ""].
            if parts.count >= 5 { values[String(parts[1])] = values[String(parts[1])] ?? String(parts[3]) }
        }
        let flags = Int(values["StateFlags"] ?? "") ?? 0
        let build = values["buildid"]
        let target = values["TargetBuildID"]
        // StateFlags bit 2 is "update required"; a different target build
        // means Steam already knows about the next one.
        let pending = flags & 2 != 0 || (target != nil && target != "0" && target != build)
        return SteamGameState(buildID: build, updatePending: pending)
    }
}
