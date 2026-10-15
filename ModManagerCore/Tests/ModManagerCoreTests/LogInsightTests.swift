import Foundation
import Testing
@testable import ModManagerCore

@Suite struct LogInsightTests {
    static let log = """
    [10:00:00 INFO  SMAPI] SMAPI 4.5.2 with Stardew Valley 1.6.15 build 24356 on macOS Unix 27.0.1
    [10:00:02 ERROR SMAPI] Skipped mods
    [10:00:02 ERROR SMAPI] --------------------------------------------------
    [10:00:02 ERROR SMAPI]    These mods could not be added to your game.
    [10:00:02 ERROR SMAPI]
    [10:00:02 ERROR SMAPI]    - Better Crafting 1.2.0 because it requires mods which aren't installed (leclair.Common, spacechase0.SpaceCore).
    [10:00:02 ERROR SMAPI]    - Fancy Mod 2.0.0 because it needs SMAPI 4.6.0 or later. Please update SMAPI.
    [10:00:02 ERROR SMAPI]    - Old Thing 1.0 because it's no longer compatible.
    [10:00:05 ALERT SMAPI] You can update SMAPI to 4.6.0: https://smapi.io
    [10:00:05 ALERT SMAPI] You can update 2 mods:
    [10:00:05 ALERT SMAPI]    Lookup Anything 1.53.0: https://www.nexusmods.com/stardewvalley/mods/541
    [10:00:05 ALERT SMAPI]    Generic Mod Config Menu 1.16.1: https://www.nexusmods.com/stardewvalley/mods/5098
    [10:00:06 INFO  SMAPI] Type 'help' for help.
    [10:01:00 ERROR Lookup Anything] This mod failed in the Input.ButtonsChanged event. Technical details:
    System.NullReferenceException: boom
    [10:01:01 ERROR Lookup Anything] This mod failed in the Input.ButtonsChanged event. Technical details:
    [10:01:02 ERROR Lookup Anything] This mod failed in the Display.Rendered event. Technical details:
    [10:01:03 ERROR game] Something the game itself did.
    """

    @Test func explainsSkippedModsErrorsAndUpdates() {
        let insights = SMAPILog(text: Self.log).insights
        let kinds = insights.map(\.kind)

        #expect(kinds.contains(.skippedMod(name: "Better Crafting", reason: "it requires mods which aren't installed (leclair.Common, spacechase0.SpaceCore)", missingIDs: ["leclair.Common", "spacechase0.SpaceCore"], needsSMAPI: nil)))
        #expect(kinds.contains { if case .skippedMod("Fancy Mod", _, _, "4.6.0") = $0 { true } else { false } })
        #expect(kinds.contains { if case .skippedMod("Old Thing", "it's no longer compatible", [], nil) = $0 { true } else { false } })
        #expect(kinds.contains(.modErrors(source: "Lookup Anything", count: 3, events: ["Input.ButtonsChanged", "Display.Rendered"])))
        #expect(kinds.contains(.smapiUpdate(version: "4.6.0", url: URL(string: "https://smapi.io"))))
        #expect(kinds.contains { if case .updatesAvailable(let list) = $0 { list.map(\.name) == ["Lookup Anything", "Generic Mod Config Menu"] && list[0].version == "1.53.0" } else { false } })
        #expect(!kinds.contains { if case .modErrors("game", _, _) = $0 { true } else { false } })  // the game's own errors aren't a mod's fault
    }

    @Test func groupsAssetConflictsByMods() {
        let log = """
        [10:00:00 INFO  SMAPI] SMAPI 4.5.2 with Stardew Valley 1.6.15 build 24356 on macOS Unix 27.0.1
        [10:02:00 WARN  SMAPI] Multiple mods want to provide the 'Maps/Town' asset: Content Patcher (for the 'Leah's Cottage, Remade' content pack), Town Remix. An asset can't be loaded multiple times, so SMAPI will use the default asset instead. Uninstall one of the mods to fix this. (Message for modders: you should avoid AssetLoadPriority.Exclusive if possible to avoid conflicts.)
        [10:02:01 WARN  SMAPI] Multiple mods want to provide the 'Maps/Town' asset: Content Patcher (for the 'Leah's Cottage, Remade' content pack), Town Remix. An asset can't be loaded multiple times, so SMAPI will use the default asset instead. Uninstall one of the mods to fix this.
        [10:02:02 WARN  SMAPI] Multiple mods want to provide the 'Maps/Town_Fair' asset: Content Patcher (for the 'Leah's Cottage, Remade' content pack), Town Remix. An asset can't be loaded multiple times, so SMAPI will use the default asset instead. Uninstall one of the mods to fix this.
        """
        let conflicts = SMAPILog(text: log).insights.compactMap { insight -> ([String], [String])? in
            if case .assetConflict(let mods, let assets) = insight.kind { return (mods, assets) }
            return nil
        }
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.0 == ["Leah's Cottage, Remade", "Town Remix"])
        #expect(conflicts.first?.1 == ["Maps/Town", "Maps/Town_Fair"])
    }

    @Test func stripsVersionsFromNames() {
        #expect(SMAPILog.stripVersion("Better Crafting 1.2.0") == "Better Crafting")
        #expect(SMAPILog.stripVersion("Mod v2.1.0-beta.1") == "Mod")
        #expect(SMAPILog.stripVersion("Stardew Valley Expanded") == "Stardew Valley Expanded")
    }
}

@Suite struct PlayReportTests {
    @Test func summarizesProblemsButNotUpdates() {
        let report = SMAPILog(text: LogInsightTests.log).playReport(crashed: false)
        #expect(report.notLoaded == ["Better Crafting", "Fancy Mod", "Old Thing"])
        #expect(report.withErrors == ["Lookup Anything"])
        #expect(report.conflicts == 0)
        #expect(!report.isEmpty)
    }

    @Test func aCleanSessionIsEmpty() {
        let log = "[10:00:00 INFO  SMAPI] SMAPI 4.5.2 with Stardew Valley 1.6.15 build 24356 on macOS Unix 27.0.1\n[10:00:06 INFO  SMAPI] Type 'help' for help."
        #expect(SMAPILog(text: log).playReport(crashed: false).isEmpty)
        #expect(!SMAPILog(text: log).playReport(crashed: true).isEmpty)
    }
}

@Suite struct LoadedModsTests {
    static let log = """
    [10:00:00 INFO  SMAPI] SMAPI 4.5.2 with Stardew Valley 1.6.15 build 24356 on macOS Unix 27.0.1
    [10:00:02 INFO  SMAPI] Loaded 3 mods:
    [10:00:02 INFO  SMAPI]    Automate 2.6.1 by Pathoschild | Lets you automate crafting machines, fruit trees, and more by connecting them to chests.
    [10:00:02 INFO  SMAPI]    Console Commands 4.5.2 by SMAPI | Adds SMAPI console commands that let you manipulate the game.
    [10:00:02 INFO  SMAPI]    Stardew Valley Expanded 1.15.11 by FlashShifter, Esca, and kittycatcasey | Adds coded elements to the game
    [10:00:02 INFO  SMAPI]
    [10:00:02 INFO  SMAPI] Loaded 2 content packs:
    [10:00:02 INFO  SMAPI]    Stardew Valley Expanded 1.15.11 by FlashShifter | for Content Patcher | An expansive fanmade mod for ConcernedApe's Stardew Valley.
    [10:00:02 INFO  SMAPI]    Stardew Valley Expanded Farm Type Manager 1.15.11 by FlashShifter | for Farm Type Manager (FTM) | This FTM pack is for SVE!
    [10:00:02 WARN  SMAPI]    Changed save serializer
    [10:00:02 WARN  SMAPI]    --------------------------------------------------
    [10:00:02 WARN  SMAPI]       These mods change the save serializer.
    [10:00:03 INFO  SMAPI] Type 'help' for help.
    """

    @Test func listsLoadedModsAndContentPacks() {
        let loaded = SMAPILog(text: Self.log).loadedMods
        #expect(loaded.count == 5)
        #expect(loaded[0] == LoadedMod(name: "Automate", version: "2.6.1", author: "Pathoschild",
                                       description: "Lets you automate crafting machines, fruit trees, and more by connecting them to chests.", contentPackFor: nil))
        #expect(loaded[2].name == "Stardew Valley Expanded")
        #expect(loaded[2].author == "FlashShifter, Esca, and kittycatcasey")
        let packs = loaded.filter(\.isContentPack)
        #expect(packs.map(\.contentPackFor) == ["Content Patcher", "Farm Type Manager (FTM)"])
        #expect(packs[1].name == "Stardew Valley Expanded Farm Type Manager")
        #expect(packs[1].version == "1.15.11")
    }
}
