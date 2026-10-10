import Foundation
import Testing
@testable import ModManagerCore

@Suite struct SubfolderTests {
    @Test func findsModsInsideFoldersLikeSMAPI() throws {
        let tmp = try TempDir()
        let expansions = tmp.url.appending(path: "Expansions", directoryHint: .isDirectory)
        try tmp.makeMod("SVE", manifest: manifest("sve"), in: expansions)
        try tmp.makeMod("[CP] Deep", manifest: manifest("deep"), in: expansions.appending(path: "More"))
        try tmp.makeMod("Top", manifest: manifest("top"))
        try tmp.makeMod("Broken", manifest: nil)                         // no mod inside: listed as missing manifest
        try tmp.makeMod("Off", manifest: manifest("off"), in: tmp.url.appending(path: ".Disabled Group"))

        let mods = try ModManager.forTesting(tmp.url).scan()
        let byID = Dictionary(uniqueKeysWithValues: mods.map { ($0.id, $0) })
        #expect(Set(byID.keys) == ["Expansions/SVE", "Expansions/More/[CP] Deep", "Top", "Broken", ".Disabled Group/Off"])
        #expect(byID["Expansions/SVE"]?.isEnabled == true)
        #expect(byID["Broken"]?.status == .missingManifest)
        #expect(byID[".Disabled Group/Off"]?.isEnabled == false)  // disabled by its folder
    }

    @Test func enablingAModInADisabledFolderEnablesTheFolder() throws {
        let tmp = try TempDir()
        try tmp.makeMod("Off", manifest: manifest("off"), in: tmp.url.appending(path: ".Group"))
        let manager = ModManager.forTesting(tmp.url)
        let mod = try #require(try manager.scan().first)
        let url = try manager.setEnabled(mod, true)
        #expect(manager.relativeID(for: url) == "Group/Off")
        #expect(try manager.scan().first?.isEnabled == true)
    }

    @Test func updatesReplaceTheCopyInsideASubfolder() async throws {
        let tmp = try TempDir()
        let mods = tmp.url.appending(path: "Mods", directoryHint: .isDirectory)
        try tmp.makeMod("Automate", manifest: manifest("Pathoschild.Automate", version: "1.0.0"), in: mods.appending(path: "QoL"))
        let update = try tmp.makeMod("Automate 2", manifest: manifest("Pathoschild.Automate", extra: #", "Description": "new""#), in: tmp.url.appending(path: "staging"))
        let archive = try tmp.zip(update, named: "Automate.zip")

        let manager = ModManager.forTesting(mods)
        let prepared = try await manager.prepareInstall(archive: archive)
        #expect(prepared.conflicts == ["Automate 2"])  // matched by UniqueID despite another folder name
        _ = await manager.commit(prepared, overwrite: true)
        let installed = try manager.scan()
        #expect(installed.map(\.id) == ["QoL/Automate"])  // replaced in place, no duplicate at the top level
        #expect(installed.first?.description == "new")
    }
}

@Suite struct DuplicateTests {
    @Test func flagsEnabledDuplicatesOnly() throws {
        let tmp = try TempDir()
        try tmp.makeMod("CP old", manifest: manifest("Pathoschild.ContentPatcher", version: "2.0.0"))
        try tmp.makeMod("CP new", manifest: manifest("pathoschild.contentpatcher", version: "2.9.1"))
        try tmp.makeMod(".CP disabled", manifest: manifest("Pathoschild.ContentPatcher"))
        let mods = try ModManager.forTesting(tmp.url).scan()
        let groups = ModManager.duplicateGroups(in: mods)
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)
        #expect(groups[0].allSatisfy { $0.status == .duplicate })
        #expect(ModManager.preferredCopy(among: groups[0])?.folderName == "CP new")
    }
}

@Suite struct GroupingTests {
    func mod(_ folder: String, id: String, container: [String] = [], keys: [String] = []) -> ModInfo {
        var mod = ModInfo(folderURL: URL(filePath: "/Mods/" + (container + [folder]).joined(separator: "/")))
        mod.uniqueID = id
        mod.containerPath = container
        mod.updateKeys = keys
        return mod
    }

    @Test func groupsSVEPartsByNameAndKeepsOthersApart() {
        let mods = [
            mod("[CP] Stardew Valley Expanded", id: "FlashShifter.StardewValleyExpandedCP"),
            mod("[FTM] Stardew Valley Expanded", id: "FlashShifter.SVE-FTM"),
            mod("Stardew Valley Expanded Code", id: "FlashShifter.SVECode"),
            mod("Automate", id: "Pathoschild.Automate", keys: ["Nexus:1063"]),
            mod("ContentPatcher", id: "Pathoschild.ContentPatcher", keys: ["Nexus:1915"]),
            mod("ConsoleCommands", id: "SMAPI.ConsoleCommands"),
            mod("SaveBackup", id: "SMAPI.SaveBackup"),
        ]
        let groups = ModGrouping.groups(mods, nexusID: \.nexusModID)
        let sve = groups.first { $0.mods.count == 3 }
        #expect(sve?.name == "Stardew Valley Expanded")
        #expect(groups.count == 5)  // SVE + 4 single mods
    }

    @Test func groupsBySharedNexusIDAndFolder() {
        let mods = [
            mod("[CP] Fancy", id: "a.FancyCP", keys: ["Nexus:42"]),
            mod("Fancy Framework", id: "a.Fancy", keys: ["Nexus:42"]),
            mod("One", id: "x.One", container: ["Expansions"]),
            mod("Two", id: "x.Two", container: ["Expansions"]),
        ]
        let groups = ModGrouping.groups(mods, nexusID: \.nexusModID)
        #expect(groups.first { $0.isFolder }?.mods.count == 2)
        #expect(groups.first { $0.isFolder }?.name == "Expansions")
        #expect(groups.contains { !$0.isFolder && $0.mods.count == 2 })
    }

    @Test func groupsSameAuthorFamiliesButNotLookalikes() {
        let mods = [
            mod("East Scarp Core", id: "Lemurkat.EastScarp"),
            mod("East Scarp NPCs", id: "Lemurkat.EastScarpNPCs"),
            mod("East Scarp FTM", id: "Lemurkat.EastScarpe.FTM"),
            mod("East Scarp C#", id: "Lemurkat.EastScarpCode"),
            mod("ContentPatcher", id: "Pathoschild.ContentPatcher"),
            mod("Content Patcher Animations", id: "spacechase0.ContentPatcherAnimations"),
            mod("Automate", id: "Pathoschild.Automate"),
        ]
        let groups = ModGrouping.groups(mods, nexusID: { _ in nil })
        #expect(groups.first { $0.mods.count == 4 }?.mods.allSatisfy { $0.uniqueID.hasPrefix("Lemurkat") } == true)
        #expect(groups.filter { $0.mods.count == 1 }.count == 3)  // CP, CP Animations, Automate stay apart
    }

    @Test func stripsFrameworkTags() {
        #expect(ModGrouping.strippedName("[CP] Stardew Valley Expanded") == "Stardew Valley Expanded")
        #expect(ModGrouping.strippedName("Stardew Valley Expanded Code") == "Stardew Valley Expanded")
        #expect(ModGrouping.strippedName("Ridgeside Village [CP]") == "Ridgeside Village")
        #expect(ModGrouping.strippedName("SpaceCore") == "SpaceCore")
    }
}

@Suite struct ArchiveTests {
    @Test func keepsReplacedVersionsAndReverts() async throws {
        let tmp = try TempDir()
        let mods = tmp.url.appending(path: "Mods", directoryHint: .isDirectory)
        let old = try tmp.makeMod(".Lookup", manifest: manifest("Pathoschild.LookupAnything", version: "1.0.0"), in: mods)
        try Data(#"{"key": "F1"}"#.utf8).write(to: old.appending(path: "config.json"))
        let archive = ModArchive(directory: tmp.url.appending(path: "Archive"), keep: 2, recycle: { try FileManager.default.removeItem(at: $0) })
        let manager = ModManager(modsURL: mods, archive: archive, recycle: { try FileManager.default.removeItem(at: $0) })

        // Update to 2.0.0: 1.0.0 goes to the archive.
        let new = try tmp.makeMod("Lookup", manifest: manifest("Pathoschild.LookupAnything", version: "2.0.0"), in: tmp.url.appending(path: "staging"))
        _ = await manager.commit(try await manager.prepareInstall(archive: try tmp.zip(new, named: "Lookup.zip")), overwrite: true)
        let versions = archive.versions(of: "Pathoschild.LookupAnything")
        #expect(versions.map(\.version) == ["1.0.0"])

        // Change a setting, then revert: 1.0.0 is back, still disabled, with the current settings.
        let installed = try #require(try manager.scan().first)
        #expect(installed.version == "2.0.0")
        try Data(#"{"key": "F2"}"#.utf8).write(to: installed.folderURL.appending(path: "config.json"))
        try archive.restore(versions[0], replacing: installed)

        let reverted = try #require(try manager.scan().first)
        #expect(reverted.version == "1.0.0")
        #expect(reverted.folderName == ".Lookup")
        #expect(try String(contentsOf: reverted.folderURL.appending(path: "config.json"), encoding: .utf8) == #"{"key": "F2"}"#)
        #expect(archive.versions(of: "Pathoschild.LookupAnything").map(\.version) == ["2.0.0"])  // can switch back
    }

    @Test func listsSizesAndRemovesKeptVersions() throws {
        let tmp = try TempDir()
        let archive = ModArchive(directory: tmp.url.appending(path: "Archive"), keep: 3, recycle: { try FileManager.default.removeItem(at: $0) })
        for (id, version) in [("a.One", "1.0.0"), ("b.Two", "1.0.0")] {
            let folder = try tmp.makeMod(id, manifest: manifest(id, version: version), in: tmp.url.appending(path: "staging"))
            try Data(repeating: 7, count: 100_000).write(to: folder.appending(path: "big.bin"))
            try archive.store(folder)
        }
        let versions = archive.allVersions()
        #expect(Set(versions.map(\.version)) == ["1.0.0"])
        #expect(versions.count == 2)
        #expect(DiskUsage.size(of: archive.directory) >= 200_000)

        try archive.remove(versions[0])
        #expect(archive.allVersions().count == 1)
        #expect(!FileManager.default.fileExists(atPath: versions[0].folder.deletingLastPathComponent().deletingLastPathComponent().path))
    }
}
