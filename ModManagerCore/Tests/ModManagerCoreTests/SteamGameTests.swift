import Foundation
import Testing
@testable import ModManagerCore

/// How a manifest is read is SteamKit's test; this checks Starseed finds it from the game folder.
@Suite struct SteamGameTests {
    func manifest(flags: String, build: String, target: String) -> String {
        """
        "AppState"
        {
        	"appid"		"413150"
        	"StateFlags"		"\(flags)"
        	"installdir"		"Stardew Valley"
        	"buildid"		"\(build)"
        	"TargetBuildID"		"\(target)"
        }
        """
    }

    @Test func findsTheManifestFromTheGameFolder() throws {
        let tmp = try TempDir()
        let steamapps = tmp.url.appending(path: "steamapps", directoryHint: .isDirectory)
        let game = steamapps.appending(path: "common/Stardew Valley/Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try Data(manifest(flags: "4", build: "7", target: "7").utf8).write(to: steamapps.appending(path: "appmanifest_413150.acf"))
        #expect(SteamGameState.read(gameFolder: game) == SteamGameState(buildID: "7", updatePending: false))
        #expect(SteamGameState.read(gameFolder: tmp.url) == nil)
        // A waiting update, by flag or by target build.
        try Data(manifest(flags: "6", build: "7", target: "7").utf8).write(to: steamapps.appending(path: "appmanifest_413150.acf"))
        #expect(SteamGameState.read(gameFolder: game)?.updatePending == true)
        try Data(manifest(flags: "4", build: "7", target: "8").utf8).write(to: steamapps.appending(path: "appmanifest_413150.acf"))
        #expect(SteamGameState.read(gameFolder: game)?.updatePending == true)
    }
}
