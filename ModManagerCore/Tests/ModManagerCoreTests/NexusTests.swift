import Foundation
import Testing
@testable import ModManagerCore

@Suite struct NexusTests {
    @Test func parsesNXMLinks() throws {
        let link = try #require(NXMLink(url: URL(string: "nxm://stardewvalley/mods/1915/files/12345?key=abc&expires=1700000000&user_id=42")!))
        #expect(link == NXMLink(gameDomain: "stardewvalley", modID: 1915, fileID: 12345, key: "abc", expires: "1700000000"))

        let premium = try #require(NXMLink(url: URL(string: "nxm://StardewValley/mods/4/files/9")!))
        #expect(premium.gameDomain == "stardewvalley")
        #expect(premium.key == nil)

        #expect(NXMLink(url: URL(string: "nxm://stardewvalley/collections/abc/revisions/1")!) == nil)
        #expect(NXMLink(url: URL(string: "https://stardewvalley/mods/1/files/2")!) == nil)
    }

    @Test func parsesPastedNexusLinksAndNumbers() {
        #expect(NexusClient.modID(fromLinkOrNumber: "https://www.nexusmods.com/stardewvalley/mods/7286") == 7286)
        #expect(NexusClient.modID(fromLinkOrNumber: " https://www.nexusmods.com/stardewvalley/mods/7286?tab=files&file_id=1 ") == 7286)
        #expect(NexusClient.modID(fromLinkOrNumber: "nexusmods.com/games/stardewvalley/mods/1915") == 1915)
        #expect(NexusClient.modID(fromLinkOrNumber: "#7286") == 7286)
        #expect(NexusClient.modID(fromLinkOrNumber: "7286") == 7286)
        #expect(NexusClient.modID(fromLinkOrNumber: "https://www.nexusmods.com/skyrimspecialedition/mods/266") == nil)
        #expect(NexusClient.modID(fromLinkOrNumber: "ridgeside 2") == nil)
    }

    @Test func nexusIDFromUpdateKeys() {
        var mod = ModInfo(folderURL: URL(filePath: "/Mods/X"))
        mod.updateKeys = ["GitHub:a/b", " nexus: 2400@1.2.0"]
        #expect(mod.nexusModID == 2400)
        #expect(mod.nexusURL?.absoluteString == "https://www.nexusmods.com/stardewvalley/mods/2400")
    }

    @Test func nexusIDFromUpdateURL() {
        let nexus = ModUpdate(installedVersion: "1.0", version: "2.0", url: URL(string: "https://www.nexusmods.com/stardewvalley/mods/1915"))
        #expect(nexus.nexusModID == 1915)
        let github = ModUpdate(installedVersion: "1.0", version: "2.0", url: URL(string: "https://github.com/x/y/releases"))
        #expect(github.nexusModID == nil)
    }

    @Test func validatesVersionsForSMAPI() {
        for valid in ["1.0", "0.0.1", "1.2.3-beta.1", "1.2.3+build", "2.9.1"] {
            #expect(UpdateChecker.isValidSemanticVersion(valid), "\(valid)")
        }
        for invalid in ["?", "1", "1.2.3.4", "0.0.0", "1.0 beta", ""] {
            #expect(!UpdateChecker.isValidSemanticVersion(invalid), "\(invalid)")
        }
    }

    @Test func filesSortMainFirstThenNewest() {
        func file(_ id: Int, _ category: String, _ date: Int) -> NexusFile {
            NexusFile(fileId: id, name: "f\(id)", version: nil, category: category, sizeInBytes: "10", date: date, description: nil)
        }
        let files = [file(1, "OLD_VERSION", 300), file(2, "OPTIONAL", 200), file(3, "MAIN", 100), file(4, "MAIN", 150)]
        let sorted = files.sorted { ($0.categoryOrder, -$0.date) < ($1.categoryOrder, -$1.date) }
        #expect(sorted.map(\.fileId) == [4, 3, 2, 1])
        #expect(!files[0].isCurrent)
    }
}

@Suite struct DependencyTests {
    @Test func groupsMissingDependenciesAcrossMods() throws {
        let tmp = try TempDir()
        let needsCP = #", "ContentPackFor": {"UniqueID": "Pathoschild.ContentPatcher"}"#
        try tmp.makeMod("[CP] A", manifest: manifest("a", name: "Pack A", extra: needsCP))
        try tmp.makeMod("[CP] B", manifest: manifest("b", name: "Pack B", extra: needsCP))
        try tmp.makeMod("Needs Disabled", manifest: manifest("c", extra: #", "Dependencies": [{"UniqueID": "dep.off"}]"#))
        try tmp.makeMod(".Off", manifest: manifest("dep.off"))

        let missing = MissingDependency.find(in: try ModManager.forTesting(tmp.url).scan())
        #expect(missing.map(\.uniqueID) == ["Pathoschild.ContentPatcher", "dep.off"])
        #expect(missing[0].requiredBy == ["Pack A", "Pack B"])
        #expect(missing[0].disabledCopy == nil)
        #expect(missing[1].disabledCopy?.folderName == ".Off")
    }

    @Test func picksFileToInstall() {
        func file(_ id: Int, _ category: String, _ version: String, _ date: Int) -> NexusFile {
            NexusFile(fileId: id, name: "f\(id)", version: version, category: category, sizeInBytes: nil, date: date, description: nil)
        }
        let files = [
            file(1, "MAIN", "2.9.1", 300), file(2, "MAIN", "2.8.1", 200),  // e.g. latest + Android build
            file(3, "OPTIONAL", "3.0.0", 400), file(4, "OLD_VERSION", "2.0.0", 100),
        ]
        #expect(NexusFile.bestMatch(in: files)?.fileId == 1)
        #expect(NexusFile.bestMatch(in: files, version: "v2.8.1")?.fileId == 2)
        #expect(NexusFile.bestMatch(in: files, version: "9.9.9")?.fileId == 1)
        #expect(NexusFile.bestMatch(in: [file(5, "OPTIONAL", "1.0", 1)])?.fileId == 5)
        #expect(NexusFile.bestMatch(in: [file(6, "OLD_VERSION", "1.0", 1)]) == nil)
    }
}

@Suite struct ArchiveFormatTests {
    @Test func installsFrom7z() async throws {
        let tmp = try TempDir()
        let mods = tmp.url.appending(path: "Mods", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        let staging = tmp.url.appending(path: "staging", directoryHint: .isDirectory)
        try tmp.makeMod("SevenZipMod", manifest: manifest("seven"), in: staging)

        let archive = tmp.url.appending(path: "SevenZipMod.7z")
        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.arguments = ["--format", "7zip", "-cf", archive.path, "-C", staging.path, "SevenZipMod"]
        try tar.run()
        tar.waitUntilExit()

        let manager = ModManager.forTesting(mods)
        let result = await manager.commit(try await manager.prepareInstall(archive: archive), overwrite: false)
        #expect(result.installed == ["SevenZipMod"])
    }
}

/// Hits the real Nexus and SMAPI APIs. Run with LIVE_API_TESTS=1.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LIVE_API_TESTS"] == "1"))
struct LiveAPITests {
    @Test func searchesNexus() async throws {
        let client = NexusClient(apiKey: nil, appVersion: "test")
        let page = try await client.searchMods(query: "content patcher", sort: .endorsements, count: 5)
        #expect(page.mods.contains { $0.modId == 1915 })
        let files = try await client.files(forMod: 1915)
        #expect(files.first?.category == "MAIN")
        #expect(try await client.mod(id: 1915).name == "Content Patcher")
    }

    @Test func checksUpdatesViaSMAPI() async throws {
        var old = ModInfo(folderURL: URL(filePath: "/Mods/ContentPatcher"))
        old.uniqueID = "Pathoschild.ContentPatcher"
        old.version = "1.0.0"
        old.updateKeys = ["Nexus:1915"]
        var odd = ModInfo(folderURL: URL(filePath: "/Mods/Odd"))
        odd.uniqueID = "someone.odd"
        odd.version = "1.0 beta"  // would make SMAPI drop the whole batch
        let results = try await UpdateChecker().check([old, odd])
        #expect(results.updates["pathoschild.contentpatcher"]?.nexusModID == 1915)
        #expect(results.records["pathoschild.contentpatcher"]?.name == "Content Patcher")
    }

    @Test func resolvesDependencyIDsToNexus() async throws {
        let records = try await UpdateChecker().lookup(uniqueIDs: ["spacechase0.SpaceCore", "nobody.fake"])
        #expect(records["spacechase0.spacecore"]?.nexusID == 1348)
        #expect(records["nobody.fake"] == nil)
    }

    @Test func fetchesNexusRequirements() async throws {
        let requirements = try await NexusClient(apiKey: nil, appVersion: "test").requirements(forMod: 3753)
        #expect(requirements.contains { $0.modID == 1915 })  // SVE needs Content Patcher
    }
}

@Suite struct SMAPITests {
    @Test func comparesSemanticVersions() throws {
        let v = { (s: String) in try #require(SemanticVersion(s)) }
        #expect(try v("4.5.2") > v("4.1.10"))
        #expect(try v("4.0") == v("4.0.0"))
        #expect(try v("4.0.0-beta.2") < v("4.0.0"))
        #expect(try v("4.0.0-beta.2") < v("4.0.0-beta.10"))
        #expect(try v("v1.2.3+build") == v("1.2.3"))
        #expect(SemanticVersion("1.0 beta") == nil)
    }

    @Test func readsAssemblyInformationalVersion() throws {
        let tmp = try TempDir()
        // Two attribute blobs as .NET stores them: file version, then informational version.
        var bytes = Data([0x00, 0x01, 0x00, 0x07]) + Data("4.5.2.0".utf8) + Data([0x00, 0x00])
        bytes += Data([0x01, 0x00, 0x10]) + Data("4.5.2+821167e5c5".utf8) + Data([0x00, 0x00])
        let dll = tmp.url.appending(path: "StardewModdingAPI.dll")
        try bytes.write(to: dll)
        #expect(SMAPIInstallation.assemblyVersion(of: dll) == SemanticVersion("4.5.2"))
    }

    @Test func detectsInstallNextToMods() throws {
        let tmp = try TempDir()
        let mods = tmp.url.appending(path: "Mods", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        #expect(SMAPIInstallation.detect(modsURL: mods) == nil)

        try Data("not really a dll".utf8).write(to: tmp.url.appending(path: "StardewModdingAPI.dll"))
        try Data(#"{"targets": {"x": {"Stardew Valley/1.6.15.24356": {}}}}"#.utf8).write(to: tmp.url.appending(path: "Stardew Valley.deps.json"))
        var bundled = ModInfo(folderURL: mods.appending(path: "ConsoleCommands"))
        bundled.uniqueID = "SMAPI.ConsoleCommands"
        bundled.version = "4.5.2"

        let install = try #require(SMAPIInstallation.detect(modsURL: mods, bundledMods: [bundled]))
        #expect(install.version == SemanticVersion("4.5.2"))       // fallback via bundled mod
        #expect(install.gameVersion == SemanticVersion("1.6.15"))
    }

    @Test func parsesMinimumApiVersion() throws {
        let tmp = try TempDir()
        let dir = try tmp.makeMod("Needy", manifest: manifest("needy", extra: #", "MinimumApiVersion": "4.6.0""#))
        #expect(ManifestParser.parse(modFolder: dir).minimumApiVersion == "4.6.0")
    }
}

@Suite struct SMAPILogTests {
    static let sample = """
    [12:00:01 INFO  SMAPI] SMAPI 4.1.10 with Stardew Valley 1.6.15 build 24356 on macOS Unix 14.5.0
    [12:00:01 TRACE SMAPI] Mods go here: /Users/me/Mods
    [12:00:02 DEBUG SMAPI] Loading mods...
    [12:00:03 WARN  Content Patcher] Some patch could not be applied.
    [12:00:04 ERROR Cool Mod] This mod failed in the GameLoop.UpdateTicked event. Technical details:
    System.NullReferenceException: Object reference not set to an instance of an object.
       at CoolMod.ModEntry.OnUpdateTicked(Object sender, UpdateTickedEventArgs e)
    [12:00:05 ERROR Cool Mod] Failed again.
    [12:00:06 ALERT SMAPI] You can update 2 mods.
    """

    @Test func parsesEntriesLevelsAndContinuationLines() {
        let log = SMAPILog(text: Self.sample)
        #expect(log.entries.count == 7)
        #expect(log.smapiVersion == "4.1.10")
        #expect(log.gameVersion == "1.6.15")
        #expect(log.platform == "macOS Unix 14.5.0")
        #expect(log.entries[4].source == "Cool Mod")
        #expect(log.entries[4].message.contains("NullReferenceException"))
        #expect(log.entries[4].message.split(separator: "\n").count == 3)
        #expect(log.count(of: .error) == 2)
    }

    @Test func parsesCRLFLineEndings() {
        // SMAPI on macOS writes "\r\n", which Swift sees as a single Character.
        let log = SMAPILog(text: Self.sample.replacingOccurrences(of: "\n", with: "\r\n"))
        #expect(log.entries.count == 7)
        #expect(log.smapiVersion == "4.1.10")
        #expect(log.entries[4].message.split(whereSeparator: \.isNewline).count == 3)
    }

    @Test func clearsUpToAPointButKeepsVersions() {
        let log = SMAPILog(text: Self.sample)
        let cleared = log.droppingFirst(5)
        #expect(cleared.entries.map(\.level) == [.error, .alert])
        #expect(cleared.smapiVersion == "4.1.10")
        #expect(cleared.count(of: .warn) == 0)
        #expect(log.sessionKey == "12:00:01 SMAPI 4.1.10 with Stardew Valley 1.6.15 build 24356 on macOS Unix 14.5.0")
    }

    @Test func groupsProblemsBySource() {
        let problems = SMAPILog(text: Self.sample).problemsBySource
        #expect(problems.map(\.source) == ["SMAPI", "Cool Mod", "Content Patcher"])
        #expect(problems[1].count == 2)
        #expect(problems[2].worst == .warn)
    }
}

@Suite struct CollectionTests {
    @Test func parsesCollectionLinks() throws {
        let link = try #require(NXMCollectionLink(url: URL(string: "nxm://stardewvalley/collections/tckf0m/revisions/113")!))
        #expect(link.slug == "tckf0m")
        #expect(link.revision == 113)
        #expect(NXMCollectionLink(url: URL(string: "nxm://stardewvalley/mods/1/files/2")!) == nil)
        #expect(NXMLink(url: URL(string: "nxm://stardewvalley/collections/tckf0m/revisions/113")!) == nil)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["LIVE_API_TESTS"] == "1"))
struct LiveCollectionTests {
    @Test func browsesAndReadsCollections() async throws {
        let client = NexusClient(apiKey: nil, appVersion: "test")
        let page = try await client.searchCollections(query: "", sort: .endorsements, count: 3)
        #expect(page.totalCount > 100)
        let first = try #require(page.collections.first)
        let revision = try await client.collectionRevision(slug: first.slug)
        #expect(!revision.mods.isEmpty)
        #expect(revision.collection.name == first.name)
        #expect(try await client.searchCollections(query: "cozy", sort: .endorsements).totalCount > 0)
    }
}

@Suite struct SMAPIInstallerTests {
    @Test func unpacksSMAPIInstallerInsteadOfInstalling() async throws {
        let tmp = try TempDir()
        let mods = tmp.url.appending(path: "Mods", directoryHint: .isDirectory)
        let downloads = tmp.url.appending(path: "Downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        let installer = tmp.url.appending(path: "staging/SMAPI 9.9.9 installer", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: installer.appending(path: "internal"), withIntermediateDirectories: true)
        try Data("#!/bin/sh".utf8).write(to: installer.appending(path: "install on macOS.command"))
        let archive = try tmp.zip(installer, named: "SMAPI 9.9.9 installer.zip")

        do {
            _ = try await ModManager.forTesting(mods).prepareInstall(archive: archive, installerDestination: downloads)
            Issue.record("expected the installer to be reported")
        } catch let error as ModManagerError {
            #expect(error.revealURL?.lastPathComponent == "install on macOS.command")
            #expect(FileManager.default.fileExists(atPath: downloads.appending(path: "SMAPI 9.9.9 installer/install on macOS.command").path))
        }
    }
}

@Suite struct DownloadPageTests {
    @Test func prefersNexusThenSMAPIsReleasePage() {
        #expect(SMAPIModRecord.downloadPage(nexusID: 1348, mainURL: nil, modDropID: 1, gitHubRepo: nil, curseForgeID: nil) == nil)
        #expect(SMAPIModRecord.downloadPage(nexusID: nil, mainURL: "https://www.moddrop.com/stardew-valley/mod/5", modDropID: 9, gitHubRepo: nil, curseForgeID: nil)?.absoluteString
                == "https://www.moddrop.com/stardew-valley/mod/5")
    }

    @Test func buildsPagesFromSiteIDs() {
        #expect(SMAPIModRecord.downloadPage(nexusID: nil, mainURL: nil, modDropID: 793815, gitHubRepo: "a/b", curseForgeID: nil)?.absoluteString
                == "https://www.moddrop.com/stardew-valley/mod/793815")
        let gitHub = SMAPIModRecord.downloadPage(nexusID: nil, mainURL: nil, modDropID: nil, gitHubRepo: "Platonymous/Stardew-Valley-Mods", curseForgeID: nil)
        #expect(gitHub?.absoluteString == "https://github.com/Platonymous/Stardew-Valley-Mods/releases")
        #expect(SMAPIModRecord(uniqueID: "x", name: nil, nexusID: nil, downloadPage: gitHub).downloadSite == "GitHub")
        #expect(SMAPIModRecord.downloadPage(nexusID: nil, mainURL: nil, modDropID: nil, gitHubRepo: nil, curseForgeID: nil) == nil)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["LIVE_API_TESTS"] == "1"))
struct LiveBatchModTests {
    @Test func looksUpSeveralModsAtOnce() async throws {
        let mods = try await NexusClient(apiKey: nil, appVersion: "test").mods(ids: [1915, 3753, 999_999_999])
        #expect(Set(mods.map(\.modId)) == [1915, 3753])
        #expect(mods.allSatisfy { $0.thumbnailURL != nil })
    }
}
