import Foundation
import Testing
@testable import ModManagerCore

@Suite struct SaveBackupTests {
    /// A Saves folder with two saves, plus an empty backups folder.
    func makeSaves(_ tmp: TempDir) throws -> (saves: URL, store: SaveBackupStore) {
        let saves = tmp.url.appending(path: "Saves", directoryHint: .isDirectory)
        for (id, farm) in [("Mats_1", "Mat's"), ("Cydonia_2", "Cydonia")] {
            let folder = saves.appending(path: id, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("<Farmer><name>Mat</name><farmName>\(farm)</farmName><dayOfMonthForSaveGame>3</dayOfMonthForSaveGame><seasonForSaveGame>2</seasonForSaveGame><yearForSaveGame>1</yearForSaveGame></Farmer>".utf8).write(to: folder.appending(path: "SaveGameInfo"))
            try Data("day 1".utf8).write(to: folder.appending(path: id))
        }
        let store = SaveBackupStore(
            directory: tmp.url.appending(path: "Backups", directoryHint: .isDirectory),
            savesFolder: saves,
            recycle: { try FileManager.default.removeItem(at: $0) }
        )
        return (saves, store)
    }

    @Test func backsUpAndListsSaves() async throws {
        let tmp = try TempDir()
        let (_, store) = try makeSaves(tmp)
        let backup = try await store.backUp(saveIDs: ["Mats_1", "Cydonia_2"], label: "All saves")
        #expect(backup.saveIDs == ["Cydonia_2", "Mats_1"])
        #expect(backup.saveNames["Mats_1"] == "Mat's Farm (Mat) · Fall 3, Year 1")
        #expect(backup.label == "All saves")
        #expect(await store.list().count == 1)
    }

    @Test func prunesOnlyMatchingBackups() async throws {
        let tmp = try TempDir()
        let (_, store) = try makeSaves(tmp)
        try await store.backUp(saveIDs: ["Mats_1"], label: "Manual")
        var auto: [SaveBackup] = []
        for _ in 0..<4 {
            auto.append(try await store.backUp(saveIDs: ["Mats_1"], label: "Auto"))
        }
        try await store.prune(labels: ["Auto"], keep: 2)
        let left = await store.list().map(\.url.lastPathComponent).sorted()
        #expect(left.count == 3)
        #expect(left.contains { $0.hasSuffix("Manual.zip") })
        // The two newest automatic ones stay.
        #expect(Set(left).isSuperset(of: auto.suffix(2).map(\.url.lastPathComponent)))
    }

    @Test func restoresOneSaveAndKeepsABeforeRestoreCopy() async throws {
        let tmp = try TempDir()
        let (saves, store) = try makeSaves(tmp)
        let backup = try await store.backUp(saveIDs: ["Mats_1", "Cydonia_2"], label: "All saves")

        // Play on: both saves change after the backup.
        try Data("day 50".utf8).write(to: saves.appending(path: "Mats_1/Mats_1"))
        try Data("day 99".utf8).write(to: saves.appending(path: "Cydonia_2/Cydonia_2"))

        try await store.restore(backup, saveIDs: ["Mats_1"])
        #expect(try String(contentsOf: saves.appending(path: "Mats_1/Mats_1"), encoding: .utf8) == "day 1")
        #expect(try String(contentsOf: saves.appending(path: "Cydonia_2/Cydonia_2"), encoding: .utf8) == "day 99")  // untouched

        let all = await store.list()
        let safety = try #require(all.first { $0.label == "Before restore" })
        #expect(safety.saveIDs == ["Mats_1"])
    }

    @Test func restoresEverythingAndBringsBackDeletedSaves() async throws {
        let tmp = try TempDir()
        let (saves, store) = try makeSaves(tmp)
        let backup = try await store.backUp(saveIDs: ["Mats_1", "Cydonia_2"], label: "All saves")
        try FileManager.default.removeItem(at: saves.appending(path: "Cydonia_2"))

        try await store.restore(backup)
        #expect(FileManager.default.fileExists(atPath: saves.appending(path: "Cydonia_2/SaveGameInfo").path))
    }

    @Test func readsSMAPIStyleBackups() async throws {
        let tmp = try TempDir()
        let (saves, _) = try makeSaves(tmp)
        // SMAPI's Save Backup mod zips the save folders into <game>/save-backups.
        let game = tmp.url.appending(path: "Game", directoryHint: .isDirectory)
        let smapiBackups = game.appending(path: "save-backups", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: smapiBackups, withIntermediateDirectories: true)
        _ = try await Archive.run("/usr/bin/zip", ["-r", "-q", smapiBackups.appending(path: "2026-10-09 - SMAPI 4.5.2.zip").path, "Mats_1"], in: saves)

        let store = SaveBackupStore(directory: tmp.url.appending(path: "Backups"), gameFolder: game, savesFolder: saves)
        let backup = try #require(await store.list().first)
        #expect(backup.isSMAPIBackup)
        #expect(backup.saveIDs == ["Mats_1"])
        #expect(throws: ModManagerError.self) { try store.delete(backup) }
    }
}

@Suite struct ModListTests {
    func mod(_ id: String, _ version: String, enabled: Bool = true, keys: [String] = []) -> ModInfo {
        var mod = ModInfo(folderURL: URL(filePath: "/Mods/" + (enabled ? id : "." + id)))
        mod.uniqueID = id
        mod.name = id.components(separatedBy: ".").last!
        mod.version = version
        mod.updateKeys = keys
        return mod
    }

    @Test func snapshotsExportsAndImports() throws {
        let installed = [mod("Pathoschild.ContentPatcher", "2.9.1", keys: ["Nexus:1915"]), mod("SMAPI.ConsoleCommands", "4.5.2"), mod("a.Off", "1.0", enabled: false)]
        let list = ModList.snapshot(name: "My Farm", of: installed, nexusID: \.nexusModID, gameVersion: "1.6.15", smapiVersion: "4.5.2")
        #expect(list.mods.map(\.uniqueID) == ["Pathoschild.ContentPatcher", "a.Off"])  // SMAPI's bundled mods left out
        #expect(list.mods[0].nexusID == 1915)
        #expect(list.mods[1].enabled == false)

        let roundTrip = try ModList.decode(from: list.encoded())
        #expect(roundTrip.mods == list.mods)
        #expect(roundTrip.name == "My Farm")
        #expect(throws: ModManagerError.self) { try ModList.decode(from: Data(#"{"format":"other","formatVersion":1,"name":"x","createdAt":"2026-01-01T00:00:00Z","mods":[]}"#.utf8)) }
    }

    @Test func carriesAndAppliesModSettings() throws {
        let tmp = try TempDir()
        func installed(_ id: String, config: String?) throws -> ModInfo {
            let folder = tmp.url.appending(path: id, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let config { try Data(config.utf8).write(to: folder.appending(path: "config.json")) }
            var mod = ModInfo(folderURL: folder)
            mod.uniqueID = id
            mod.name = id
            mod.version = "1.0"
            return mod
        }
        let here = [try installed("a.Mod", config: "{ \"Speed\": 2 } // fast"), try installed("b.NoConfig", config: nil)]
        let list = ModList.snapshot(name: "Setup", of: here, nexusID: { _ in nil }, gameVersion: nil, smapiVersion: nil)
        #expect(list.mods.first { $0.uniqueID == "a.Mod" }?.settings == "{ \"Speed\": 2 } // fast")
        #expect(list.settingsCount == 1)
        #expect(try ModList.decode(from: list.encoded()).mods == list.mods)

        // Another computer: same mods, different speed.
        let elsewhere = tmp.url.appending(path: "elsewhere", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let other = try { () throws -> ModInfo in
            let folder = elsewhere.appending(path: "a.Mod", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("{ \"Speed\": 5 }".utf8).write(to: folder.appending(path: "config.json"))
            var mod = ModInfo(folderURL: folder)
            mod.uniqueID = "A.MOD"
            return mod
        }()
        let changes = list.settingsChanges(for: [other])
        #expect(changes.count == 1)
        try ModList.apply(settings: changes[0].settings, to: other)
        #expect(try String(contentsOf: other.folderURL.appending(path: "config.json"), encoding: .utf8) == "{ \"Speed\": 2 } // fast")
        #expect(try String(contentsOf: other.folderURL.appending(path: "config.json.bak"), encoding: .utf8) == "{ \"Speed\": 5 }")
        #expect(list.settingsChanges(for: [other]).isEmpty)
        #expect(throws: (any Error).self) { try ModList.apply(settings: "{ broken", to: other) }
    }

    @Test func readsListsSavedWithoutSettings() throws {
        let old = #"{"format":"stardew-mod-manager/mod-list","formatVersion":1,"name":"Old","createdAt":"2026-01-01T00:00:00Z","mods":[{"name":"A","uniqueID":"a.A","version":"1.0","enabled":true}]}"#
        let list = try ModList.decode(from: Data(old.utf8))
        #expect(list.mods.first?.settings == nil)
        #expect(list.settingsCount == 0)
    }

    @Test func comparesEntriesWithInstalledMods() {
        let installed = [mod("a.Same", "1.0"), mod("b.Old", "1.0"), mod("c.New", "3.0"), mod("d.Off", "1.0", enabled: false)]
        func entry(_ id: String, _ version: String) -> ModListEntry {
            ModListEntry(name: id, uniqueID: id, version: version, author: nil, nexusID: nil, enabled: true)
        }
        #expect(ModListEntryState.of(entry("A.SAME", "1.0"), in: installed) == .installed)
        #expect(ModListEntryState.of(entry("b.Old", "2.0"), in: installed) == .olderInstalled("1.0"))
        #expect(ModListEntryState.of(entry("c.New", "2.0"), in: installed) == .newerInstalled("3.0"))
        #expect(ModListEntryState.of(entry("d.Off", "1.0"), in: installed) == .disabled)
        #expect(ModListEntryState.of(entry("e.Gone", "1.0"), in: installed) == .missing)
    }

    @Test func storesListsByName() throws {
        let tmp = try TempDir()
        let store = ModListStore(directory: tmp.url)
        try store.save(ModList(name: "Solo", gameVersion: nil, smapiVersion: nil, mods: []))
        try store.save(ModList(name: "Co-op: friends", gameVersion: nil, smapiVersion: nil, mods: []))
        #expect(Set(store.list().map(\.name)) == ["Solo", "Co-op: friends"])
    }
}
