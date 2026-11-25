// Finds Stardew Valley on this Mac: Steam (every library folder), GOG and
// the Mac App Store. A "game folder" is the game's Contents/MacOS folder,
// where SMAPI installs and the Mods folder lives.

import Foundation
import SteamKit

public struct GameLocator: Sendable {
    public var home: URL
    public var applicationFolders: [URL]

    public init(home: URL = .homeDirectory, applicationFolders: [URL]? = nil) {
        self.home = home
        self.applicationFolders = applicationFolders ?? [
            URL(filePath: "/Applications", directoryHint: .isDirectory),
            URL(filePath: "/Applications/GOG Games", directoryHint: .isDirectory),
            home.appending(path: "Applications", directoryHint: .isDirectory),
            home.appending(path: "GOG Games", directoryHint: .isDirectory),
        ]
    }

    /// Steam keeps its main library here, and lists the others in libraryfolders.vdf.
    var steamFolder: URL { Steam.defaultRoot(home: home) }

    /// Every game folder found, Steam first, without duplicates.
    public func installs() -> [URL] {
        let steam = Steam(root: steamFolder).libraries().map {
            $0.common.appending(path: "Stardew Valley/Contents/MacOS", directoryHint: .isDirectory)
        }
        let apps = applicationFolders.map { $0.appending(path: "Stardew Valley.app/Contents/MacOS", directoryHint: .isDirectory) }
        var seen = Set<String>()
        return (steam + apps).filter { folder in
            let key = folder.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
            return SMAPIInstaller.isGameFolder(folder) && seen.insert(key).inserted
        }
    }

    /// The game folder for something the user picked: the game folder
    /// itself, "Stardew Valley.app", the folder holding it, or a Mods folder.
    public static func gameFolder(fromPicked url: URL) -> URL? {
        let candidates = [
            url,
            url.appending(path: "Contents/MacOS", directoryHint: .isDirectory),
            url.appending(path: "Stardew Valley.app/Contents/MacOS", directoryHint: .isDirectory),
            url.deletingLastPathComponent(),  // picked the Mods folder
        ]
        return candidates.first(where: SMAPIInstaller.isGameFolder)
    }
}
