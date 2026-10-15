// Finds Stardew Valley on this Mac: Steam (every library folder), GOG and
// the Mac App Store. A "game folder" is the game's Contents/MacOS folder,
// where SMAPI installs and the Mods folder lives.

import Foundation

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
    var steamFolder: URL { home.appending(path: "Library/Application Support/Steam", directoryHint: .isDirectory) }

    /// Every game folder found, Steam first, without duplicates.
    public func installs() -> [URL] {
        var libraries = [steamFolder.path(percentEncoded: false)]
        if let text = try? String(contentsOf: steamFolder.appending(path: "steamapps/libraryfolders.vdf"), encoding: .utf8) {
            libraries += Self.steamLibraries(inVDF: text)
        }
        let steam = libraries.map {
            URL(filePath: $0, directoryHint: .isDirectory).appending(path: "steamapps/common/Stardew Valley/Contents/MacOS", directoryHint: .isDirectory)
        }
        let apps = applicationFolders.map { $0.appending(path: "Stardew Valley.app/Contents/MacOS", directoryHint: .isDirectory) }
        var seen = Set<String>()
        return (steam + apps).filter { folder in
            let key = folder.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
            return SMAPIInstaller.isGameFolder(folder) && seen.insert(key).inserted
        }
    }

    /// The "path" entries of Steam's libraryfolders.vdf.
    public static func steamLibraries(inVDF text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            // \t"path"\t\t"/Volumes/Games/SteamLibrary"  ->  ["\t", "path", "\t\t", "/Volumes/…", ""]
            guard parts.count >= 4, parts[1] == "path" else { return nil }
            return parts[3].replacingOccurrences(of: "\\\\", with: "\\")
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
