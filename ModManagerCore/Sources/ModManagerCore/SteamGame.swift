// What Steam knows about the installed game: its appmanifest file
// (steamapps/appmanifest_413150.acf) says whether an update is waiting.

import Foundation
import SteamKit

public struct SteamGameState: Sendable, Equatable {
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
        Steam.app(containing: gameFolder).map { SteamGameState(buildID: $0.buildID, updatePending: $0.isUpdatePending) }
    }
}
