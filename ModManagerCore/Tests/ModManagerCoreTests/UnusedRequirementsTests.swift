import Foundation
import Testing
@testable import ModManagerCore

@Suite struct UnusedRequirementsTests {
    func mod(_ id: String, requires: [String] = [], optional: [String] = [], packFor: String? = nil, enabled: Bool = true) -> ModInfo {
        var mod = ModInfo(folderURL: URL(filePath: "/Mods/" + (enabled ? "" : ".") + id))
        mod.uniqueID = id
        mod.name = id
        mod.dependencies = requires.map { Dependency(uniqueID: $0) } + optional.map { Dependency(uniqueID: $0, isRequired: false) }
        mod.contentPackFor = packFor
        return mod
    }

    @Test func suggestsOnlyRequirementsNothingElseUses() {
        let eastScarp = mod("Lemurkat.EastScarp", requires: ["spacechase0.SpaceCore", "hxw.tilesheets"], optional: ["Bouhm.NPCMapLocations"], packFor: "Pathoschild.ContentPatcher")
        let ridgeside = mod("Rafseazz.RSVCP", requires: ["spacechase0.SpaceCore"], packFor: "Pathoschild.ContentPatcher")
        let remaining = [
            ridgeside,
            mod("spacechase0.SpaceCore"),
            mod("hxw.tilesheets"),
            mod("Pathoschild.ContentPatcher"),
            mod("Bouhm.NPCMapLocations"),
        ]
        let unused = UnusedRequirements.find(removed: [eastScarp], remaining: remaining)
        #expect(unused.map(\.mod.uniqueID) == ["hxw.tilesheets"])         // SpaceCore and CP still needed by Ridgeside
        #expect(unused[0].neededBy == ["Lemurkat.EastScarp"])
        // NPC Map Locations was only optional: never suggested.
    }

    @Test func followsChainsAndKeepsWhatDisabledModsNeed() {
        let big = mod("a.BigMod", requires: ["b.Framework"])
        let framework = mod("b.Framework", requires: ["c.Library"])
        let library = mod("c.Library")
        let shared = mod("d.Shared")
        let disabledUser = mod("e.Disabled", requires: ["d.Shared"], enabled: false)
        let removed = [big, mod("f.Other", requires: ["d.Shared"])]
        let unused = UnusedRequirements.find(removed: removed, remaining: [framework, library, shared, disabledUser])
        #expect(unused.map(\.mod.uniqueID) == ["b.Framework", "c.Library"])  // library only needed by the framework
        #expect(unused[1].neededBy == ["b.Framework"])
        // d.Shared is still required by a disabled mod: kept.
    }

    @Test func neverSuggestsSMAPIsBundledMods() {
        let removed = [mod("x.Mod", requires: ["SMAPI.ConsoleCommands"])]
        #expect(UnusedRequirements.find(removed: removed, remaining: [mod("SMAPI.ConsoleCommands")]).isEmpty)
    }
}
