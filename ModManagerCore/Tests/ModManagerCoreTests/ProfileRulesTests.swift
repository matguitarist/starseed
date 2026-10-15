import Foundation
import Testing
@testable import ModManagerCore

@Suite struct ProfileRulesTests {
    @Test func tracksEnabledModsAndKeepsUninstalledOnes() {
        let saved = ["Pathoschild.ContentPatcher", "FlashShifter.SVE", "Other.FromAnotherMac"]
        let installed: Set<String> = ["pathoschild.contentpatcher", "flashshifter.sve", "spacechase0.spacecore"]
        // SVE turned off, SpaceCore turned on.
        let updated = ProfileRules.tracked(saved: saved, enabled: ["Pathoschild.ContentPatcher", "spacechase0.SpaceCore"], installed: installed)
        #expect(updated == ["Pathoschild.ContentPatcher", "spacechase0.SpaceCore", "Other.FromAnotherMac"])
    }

    @Test func reportsNoChangeIgnoringCaseAndOrder() {
        let saved = ["A.One", "B.Two"]
        #expect(ProfileRules.tracked(saved: saved, enabled: ["b.two", "a.ONE"], installed: ["a.one", "b.two"]) == nil)
    }

    @Test func findsTheProfileMatchingTheEnabledMods() {
        let profiles = ["Vanilla": ["SMAPI.ConsoleCommands"], "Default": ["SMAPI.ConsoleCommands", "A.One"], "Also": ["a.one", "smapi.consolecommands"]]
        #expect(ProfileRules.matching(profiles, enabled: ["A.One", "SMAPI.ConsoleCommands"]) == "Also")  // first by name
        #expect(ProfileRules.matching(profiles, enabled: ["X.Y"]) == nil)
    }

    @Test func picksAnUnusedName() {
        let taken: Set<String> = ["Default", "Default 2"]
        #expect(ProfileRules.uniqueName("Default", taken: taken.contains, numbered: { "Default \($0)" }) == "Default 3")
        #expect(ProfileRules.uniqueName("Vanilla", taken: taken.contains, numbered: { "Vanilla \($0)" }) == "Vanilla")
    }

    @Test func mergesAndRemovesWithoutDuplicates() {
        #expect(ProfileRules.merged(["A.One", "B.Two"], adding: ["b.two", "C.Three"]) == ["A.One", "B.Two", "C.Three"])
        #expect(ProfileRules.removing(["b.TWO"], from: ["A.One", "B.Two"]) == ["A.One"])
    }

    @Test func keepsOnlySMAPIsOwnModsForAnEmptyProfile() {
        #expect(ProfileRules.smapiBundled(["SMAPI.ConsoleCommands", "Pathoschild.ContentPatcher", "SMAPI.SaveBackup"]) == ["SMAPI.ConsoleCommands", "SMAPI.SaveBackup"])
    }

    @Test func linksSavesPlayedDuringTheSession() {
        let launch = Date(timeIntervalSince1970: 1_000_000)
        let saves: [(id: String, lastSaved: Date?)] = [
            ("New_1", launch.addingTimeInterval(600)),      // new farm
            ("Old_2", launch.addingTimeInterval(-3600)),    // not played
            ("Linked_3", launch.addingTimeInterval(300)),   // keeps its profile
            ("Played_4", launch.addingTimeInterval(1200)),
        ]
        #expect(ProfileRules.savesToLink(saved: saves, since: launch, linked: ["Linked_3"]) == ["New_1", "Played_4"])
    }

    @Test func groupsSavesByProfileInUseFirst() {
        let groups = ProfileRules.groupedSaves(
            ["a", "b", "c", "d", "e"],
            links: ["a": "SVE", "b": "Default", "c": "Gone", "d": "SVE"],
            order: ["Default", "SVE", "Vanilla"],
            active: "SVE"
        )
        #expect(groups.map(\.profile) == ["SVE", "Default", nil])
        #expect(groups.map(\.saves) == [["a", "d"], ["b"], ["c", "e"]])
    }

}
