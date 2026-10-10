import Foundation
import Testing
@testable import ModManagerCore

@Suite struct SteamGameTests {
    func manifest(flags: String, build: String, target: String) -> String {
        """
        "AppState"
        {
        	"appid"		"413150"
        	"StateFlags"		"\(flags)"
        	"buildid"		"\(build)"
        	"TargetBuildID"		"\(target)"
        	"InstalledDepots"
        	{
        		"413152"
        		{
        			"manifest"		"2618652301291810021"
        		}
        	}
        }
        """
    }

    @Test func readsAnUpToDateGame() {
        let state = SteamGameState.parse(manifest(flags: "4", build: "16826371", target: "16826371"))
        #expect(state == SteamGameState(buildID: "16826371", updatePending: false))
    }

    @Test func noticesAWaitingUpdate() {
        #expect(SteamGameState.parse(manifest(flags: "6", build: "1", target: "1")).updatePending)
        #expect(SteamGameState.parse(manifest(flags: "4", build: "1", target: "2")).updatePending)
    }

    @Test func findsTheManifestFromTheGameFolder() throws {
        let tmp = try TempDir()
        let steamapps = tmp.url.appending(path: "steamapps", directoryHint: .isDirectory)
        let game = steamapps.appending(path: "common/Stardew Valley/Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try Data(manifest(flags: "4", build: "7", target: "7").utf8).write(to: steamapps.appending(path: "appmanifest_413150.acf"))
        #expect(SteamGameState.read(gameFolder: game)?.buildID == "7")
        #expect(SteamGameState.read(gameFolder: tmp.url) == nil)
    }
}
