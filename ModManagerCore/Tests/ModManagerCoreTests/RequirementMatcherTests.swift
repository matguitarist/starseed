import Foundation
import Testing
@testable import ModManagerCore

@Suite struct RequirementMatcherTests {
    /// East Scarp's (#5787) Nexus requirements, as the API returns them.
    static let eastScarp = [
        NexusRequirement(modID: 1915, name: "Content Patcher", notes: nil, externalURL: nil),
        NexusRequirement(modID: 3231, name: "Farm Type Manager (FTM)", notes: nil, externalURL: nil),
        NexusRequirement(modID: 9599, name: "Lumisteria Tilesheets - Indoor", notes: nil, externalURL: nil),
        NexusRequirement(modID: 10448, name: "Lumisteria Tilesheets - Outdoor", notes: nil, externalURL: nil),
        NexusRequirement(modID: 14493, name: "Mapping Extensions and Extra Properties (MEEP)", notes: nil, externalURL: nil),
        NexusRequirement(modID: 1348, name: "SpaceCore", notes: nil, externalURL: nil),
        NexusRequirement(modID: 20139, name: "HxW Tilesheets", notes: nil, externalURL: nil),
    ]

    @Test func matchesEastScarpsMissingTilesheets() {
        func match(_ id: String) -> Int? { RequirementMatcher.bestMatch(for: id, among: Self.eastScarp)?.modID }
        #expect(match("Lumisteria.LumiTilesheetsIndoor") == 9599)
        #expect(match("Lumisteria.TtilesheetsOutdoor") == 10448)   // the manifest's typo
        #expect(match("hxw.tilesheets") == 20139)
        #expect(match("spacechase0.SpaceCore") == 1348)
        #expect(match("DecidedlyHuman.MappingExtensionsAndExtraProperties") == 14493)
        #expect(match("Pathoschild.ContentPatcher") == 1915)
    }

    @Test func doesNotGuessWhenUnclear() {
        #expect(RequirementMatcher.bestMatch(for: "Someone.Tilesheets", among: Self.eastScarp) == nil)  // 3 tilesheet mods: ambiguous
        #expect(RequirementMatcher.bestMatch(for: "DN.SnS", among: Self.eastScarp) == nil)
    }

    @Test func tokenizesUniqueIDs() {
        #expect(RequirementMatcher.tokens(ofUniqueID: "Lumisteria.LumiTilesheetsIndoor") == ["lumisteria", "lumi", "tilesheets", "indoor", "lumitilesheetsindoor"])
        #expect(RequirementMatcher.tokens(ofUniqueID: "hxw.tilesheets") == ["hxw", "tilesheets"])
    }
}
