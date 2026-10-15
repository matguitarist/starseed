import Foundation
import Testing
@testable import ModManagerCore

@Suite struct GameLocatorTests {
    private func makeGame(at folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appending(path: "Stardew Valley.dll"))
    }

    @Test func readsSteamLibraryPaths() {
        let vdf = """
        "libraryfolders"
        {
        \t"0"
        \t{
        \t\t"path"\t\t"/Users/me/Library/Application Support/Steam"
        \t\t"label"\t\t""
        \t}
        \t"1"
        \t{
        \t\t"path"\t\t"/Volumes/Games/SteamLibrary"
        \t}
        }
        """
        #expect(GameLocator.steamLibraries(inVDF: vdf) == ["/Users/me/Library/Application Support/Steam", "/Volumes/Games/SteamLibrary"])
    }

    @Test func findsSteamLibrariesAndApps() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "locator-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appending(path: "home")
        let library = root.appending(path: "SteamLibrary")
        let steamApps = home.appending(path: "Library/Application Support/Steam/steamapps")
        try FileManager.default.createDirectory(at: steamApps, withIntermediateDirectories: true)
        try "\"libraryfolders\"\n{\n\t\"1\"\n\t{\n\t\t\"path\"\t\t\"\(library.path(percentEncoded: false))\"\n\t}\n}".write(to: steamApps.appending(path: "libraryfolders.vdf"), atomically: true, encoding: .utf8)
        let steamGame = library.appending(path: "steamapps/common/Stardew Valley/Contents/MacOS")
        let apps = root.appending(path: "Applications")
        let gogGame = apps.appending(path: "Stardew Valley.app/Contents/MacOS")
        try makeGame(at: steamGame)
        try makeGame(at: gogGame)

        let found = GameLocator(home: home, applicationFolders: [apps]).installs()
        #expect(found.map { $0.standardizedFileURL.path(percentEncoded: false) } == [steamGame, gogGame].map { $0.standardizedFileURL.path(percentEncoded: false) })
    }

    @Test func normalizesWhatTheUserPicked() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "picked-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "Stardew Valley.app")
        let game = app.appending(path: "Contents/MacOS")
        try makeGame(at: game)
        let expected = game.standardizedFileURL.path(percentEncoded: false)
        for picked in [app, root, game, game.appending(path: "Mods")] {
            #expect(GameLocator.gameFolder(fromPicked: picked)?.standardizedFileURL.path(percentEncoded: false) == expected)
        }
        #expect(GameLocator.gameFolder(fromPicked: root.appending(path: "nothing")) == nil)
    }
}
