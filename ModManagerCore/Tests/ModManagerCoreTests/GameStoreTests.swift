import Foundation
import Testing
@testable import ModManagerCore

@Suite struct GameStoreTests {
    func gameFolder(_ tmp: TempDir, _ path: String) throws -> URL {
        let folder = tmp.url.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func recognizesSteam() throws {
        let tmp = try TempDir()
        #expect(GameStore.detect(gameFolder: try gameFolder(tmp, "steamapps/common/Stardew Valley/Contents/MacOS")) == .steam)
    }

    @Test func recognizesTheMacAppStore() throws {
        let tmp = try TempDir()
        let folder = try gameFolder(tmp, "Applications/Stardew Valley.app/Contents/MacOS")
        let receipt = folder.deletingLastPathComponent().appending(path: "_MASReceipt", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: receipt, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: receipt.appending(path: "receipt"))
        #expect(GameStore.detect(gameFolder: folder) == .appStore)
    }

    @Test func recognizesGOG() throws {
        let tmp = try TempDir()
        let folder = try gameFolder(tmp, "Games/Stardew Valley.app/Contents/MacOS")
        let resources = try gameFolder(tmp, "Games/Stardew Valley.app/Contents/Resources")
        try Data("{}".utf8).write(to: resources.appending(path: "goggame-1453375253.info"))
        #expect(GameStore.detect(gameFolder: folder) == .gog)
        #expect(GameStore.detect(gameFolder: try gameFolder(tmp, "Other/Stardew Valley.app/Contents/MacOS")) == .other)
    }
}
