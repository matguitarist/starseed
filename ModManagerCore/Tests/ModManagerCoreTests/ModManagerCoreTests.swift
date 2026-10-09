import Foundation
import Testing
@testable import ModManagerCore

/// A throwaway directory that's deleted when the test finishes.
final class TempDir {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "sdv_tests_\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func makeMod(_ folder: String, manifest: String?, in parent: URL? = nil) throws -> URL {
        let dir = (parent ?? url).appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let manifest {
            try Data(manifest.utf8).write(to: dir.appending(path: "manifest.json"))
        }
        return dir
    }

    /// Zips `folder` (keeping it as the top-level entry unless `keepParent` is false).
    func zip(_ folder: URL, named name: String, keepParent: Bool = true) throws -> URL {
        let out = url.appending(path: name)
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k"] + (keepParent ? ["--keepParent"] : []) + [folder.path, out.path]
        try process.run()
        process.waitUntilExit()
        return out
    }
}

extension ModManager {
    /// Deletes instead of trashing, so test runs don't fill the user's Trash.
    static func forTesting(_ modsURL: URL) -> ModManager {
        ModManager(modsURL: modsURL, recycle: { try FileManager.default.removeItem(at: $0) })
    }
}

func manifest(_ id: String, name: String? = nil, version: String = "1.0.0", extra: String = "") -> String {
    """
    { "Name": "\(name ?? id)", "UniqueID": "\(id)", "Version": "\(version)", "Author": "Me" \(extra) }
    """
}

@Suite struct ManifestTests {
    @Test func toleratesBOMCommentsTrailingCommasAndKeyCase() throws {
        let tmp = try TempDir()
        let json = """
        // leading comment
        {
          "name": "Lenient", /* inline */
          "uniqueId": "me.lenient",
          "version": "2.1.0",
          "UpdateKeys": ["Nexus:1234@2.1.0"],
          "Dependencies": [ { "UniqueID": "Pathoschild.ContentPatcher", "IsRequired": false }, ],
        }
        """
        let dir = try tmp.makeMod("Lenient", manifest: nil)
        try (Data([0xEF, 0xBB, 0xBF]) + Data(json.utf8)).write(to: dir.appending(path: "manifest.json"))

        let mod = ManifestParser.parse(modFolder: dir)
        #expect(mod.parseError == nil)
        #expect(mod.name == "Lenient")
        #expect(mod.uniqueID == "me.lenient")
        #expect(mod.version == "2.1.0")
        #expect(mod.dependencies == [Dependency(uniqueID: "Pathoschild.ContentPatcher", isRequired: false)])
        #expect(mod.nexusURL?.absoluteString == "https://www.nexusmods.com/stardewvalley/mods/1234")
    }

    @Test func legacyVersionObject() throws {
        let tmp = try TempDir()
        let dir = try tmp.makeMod("Old", manifest: #"{"Name":"Old","Version":{"MajorVersion":1,"MinorVersion":4,"PatchVersion":2}}"#)
        #expect(ManifestParser.parse(modFolder: dir).version == "1.4.2")
    }

    @Test func missingAndBrokenManifests() throws {
        let tmp = try TempDir()
        let missing = ManifestParser.parse(modFolder: try tmp.makeMod(".NoManifest", manifest: nil))
        #expect(missing.status == .missingManifest)
        #expect(missing.displayName == "NoManifest (no manifest.json)")
        #expect(!missing.isEnabled)

        let broken = ManifestParser.parse(modFolder: try tmp.makeMod("Broken", manifest: "{ not json"))
        #expect(broken.status == .manifestError)
        #expect(broken.parseError != nil)
    }
}

@Suite struct ModManagerTests {
    @Test func scanFlagsMissingDependenciesOnlyForEnabledMods() throws {
        let tmp = try TempDir()
        let deps = #", "Dependencies": [{"UniqueID": "a.framework"}]"#
        try tmp.makeMod("Framework", manifest: manifest("A.Framework"))
        try tmp.makeMod("NeedsFramework", manifest: manifest("b", extra: deps))
        try tmp.makeMod("NeedsMissing", manifest: manifest("c", extra: #", "Dependencies": [{"UniqueID": "nope"}]"#))
        try tmp.makeMod(".DisabledNeedsMissing", manifest: manifest("d", extra: #", "Dependencies": [{"UniqueID": "nope"}]"#))
        try tmp.makeMod("[CP] Pack", manifest: manifest("e", extra: #", "ContentPackFor": {"UniqueID": "Pathoschild.ContentPatcher"}"#))

        let mods = try ModManager.forTesting(tmp.url).scan()
        let byID = Dictionary(uniqueKeysWithValues: mods.map { ($0.uniqueID, $0) })
        #expect(byID["b"]?.status == .enabled)             // dependency IDs are case-insensitive
        #expect(byID["c"]?.missingDependencies == ["nope"])
        #expect(byID["d"]?.status == .disabled)
        #expect(byID["e"]?.missingDependencies == ["Pathoschild.ContentPatcher"])
    }

    @Test func toggleRenamesWithLeadingDot() throws {
        let tmp = try TempDir()
        try tmp.makeMod("Toggle", manifest: manifest("t"))
        let manager = ModManager.forTesting(tmp.url)

        let mod = try #require(try manager.scan().first)
        let disabledURL = try manager.setEnabled(mod, false)
        #expect(disabledURL.lastPathComponent == ".Toggle")

        let disabled = try #require(try manager.scan().first)
        #expect(!disabled.isEnabled)
        try manager.setEnabled(disabled, true)
        #expect(try manager.scan().first?.folderName == "Toggle")
    }

    @Test func toggleRefusesToClobber() throws {
        let tmp = try TempDir()
        try tmp.makeMod("Dup", manifest: manifest("dup"))
        try tmp.makeMod(".Dup", manifest: manifest("dup"))
        let manager = ModManager.forTesting(tmp.url)
        let enabled = try #require(try manager.scan().first { $0.isEnabled })
        #expect(throws: ModManagerError.self) { try manager.setEnabled(enabled, false) }
    }

    @Test func installUnwrapsNestedFoldersAndSkipsMacOSXJunk() async throws {
        let tmp = try TempDir()
        let mods = tmp.url.appending(path: "Mods", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)

        // Download.zip/Wrapper/{ModA, ModB}, with a nested mod inside ModA that must not be split out.
        let staging = tmp.url.appending(path: "staging/Wrapper", directoryHint: .isDirectory)
        let modA = try tmp.makeMod("ModA", manifest: manifest("a"), in: staging)
        try tmp.makeMod("Nested", manifest: manifest("nested"), in: modA)
        try tmp.makeMod("ModB", manifest: manifest("b"), in: staging)
        let archive = try tmp.zip(staging, named: "Download.zip")

        let manager = ModManager.forTesting(mods)
        let prepared = try await manager.prepareInstall(archive: archive)
        #expect(prepared.conflicts.isEmpty)
        let result = await manager.commit(prepared, overwrite: false)

        #expect(Set(result.installed) == ["ModA", "ModB"])
        #expect(try manager.scan().map(\.folderName) == ["ModA", "ModB"])
    }

    @Test func installWithoutWrapperFolderUsesZipName() async throws {
        let tmp = try TempDir()
        let mods = tmp.url.appending(path: "Mods", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        let flat = try tmp.makeMod("flat", manifest: manifest("flat"))
        let archive = try tmp.zip(flat, named: "FlatMod 1.0.zip", keepParent: false)

        let manager = ModManager.forTesting(mods)
        let result = await manager.commit(try await manager.prepareInstall(archive: archive), overwrite: false)
        #expect(result.installed == ["FlatMod 1.0"])
    }

    @Test func updateKeepsDisabledStateAndConfig() async throws {
        let tmp = try TempDir()
        let mods = tmp.url.appending(path: "Mods", directoryHint: .isDirectory)
        let old = try tmp.makeMod(".Cheats", manifest: manifest("cheats"), in: mods)
        try Data(#"{"setting": true}"#.utf8).write(to: old.appending(path: "config.json"))

        let newVersion = try tmp.makeMod("Cheats", manifest: manifest("cheats", extra: #", "Description": "v2""#), in: tmp.url.appending(path: "staging"))
        let archive = try tmp.zip(newVersion, named: "Cheats.zip")
        let manager = ModManager.forTesting(mods)

        let skipPrepared = try await manager.prepareInstall(archive: archive)
        #expect(skipPrepared.conflicts == ["Cheats"])
        let skipped = await manager.commit(skipPrepared, overwrite: false)
        #expect(skipped.skipped == ["Cheats"])

        let replaced = await manager.commit(try await manager.prepareInstall(archive: archive), overwrite: true)
        #expect(replaced.installed == ["Cheats"])

        let mod = try #require(try manager.scan().first)
        #expect(mod.folderName == ".Cheats")
        #expect(mod.description == "v2")
        #expect(try String(contentsOf: mod.folderURL.appending(path: "config.json"), encoding: .utf8) == #"{"setting": true}"#)
    }

    @Test func badZipAndNonSMAPIZipReportErrors() async throws {
        let tmp = try TempDir()
        let manager = ModManager.forTesting(tmp.url)

        let bogus = tmp.url.appending(path: "bogus.zip")
        try Data("not a zip".utf8).write(to: bogus)
        await #expect(throws: ModManagerError.self) { try await manager.prepareInstall(archive: bogus) }

        let noManifest = try tmp.makeMod("XNBOnly", manifest: nil, in: tmp.url.appending(path: "staging"))
        let archive = try tmp.zip(noManifest, named: "xnb.zip")
        await #expect(throws: ModManagerError.self) { try await manager.prepareInstall(archive: archive) }
    }
}

@Suite struct ConfigStoreTests {
    @Test func storesSaveLinks() throws {
        let tmp = try TempDir()
        let store = ConfigStore(directory: tmp.url)
        #expect(store.loadSaveLinks().isEmpty)
        try store.saveSaveLinks(["Mats_1": SaveModSet(kind: .profile, name: "Modded"), "Vanilla_2": SaveModSet(kind: .collection, name: "None")])
        #expect(store.loadSaveLinks()["Mats_1"] == SaveModSet(kind: .profile, name: "Modded"))
    }

    @Test func readsPythonEraFilesAndPreservesUnknownKeys() throws {
        let tmp = try TempDir()
        try Data(#"{"mods_path": "/old/Mods", "future_key": 1}"#.utf8).write(to: tmp.url.appending(path: "config.json"))
        try Data(#"{"Solo": ["a", "b"]}"#.utf8).write(to: tmp.url.appending(path: "profiles.json"))

        let store = ConfigStore(directory: tmp.url)
        #expect(store.modsURL()?.path(percentEncoded: false) == "/old/Mods/")
        #expect(store.loadProfiles() == ["Solo": ["a", "b"]])

        try store.setModsURL(URL(filePath: "/new/Mods"))
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: tmp.url.appending(path: "config.json"))) as? [String: Any]
        #expect(saved?["mods_path"] as? String == "/new/Mods")
        #expect(saved?["future_key"] as? Int == 1)
    }
}
