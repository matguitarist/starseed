import Foundation
import Testing
@testable import ModManagerCore

@Suite struct SaveAnalysisTests {
    // Lines from a real session that loaded a save made with mods that aren't installed.
    static let log = """
    [20:23:18 TRACE SMAPI] Context: loaded save 'Mats_391030616', starting spring 1 Y1, locale set to . Single-player.\r
    [20:23:18 WARN  game] Ignored unknown location 'Custom_MinecartCave' in save data.\r
    [20:23:18 WARN  game] Ignored unknown location 'Custom_AdditionalFarmCave' in save data.\r
    [20:23:18 WARN  game] Ignored unknown location 'Custom_AdditionalFarmCave2' in save data.\r
    [20:23:18 WARN  game] Ignored unknown location 'Custom_LASV_LunnaHouse' in save data, including NPC 'Lunna'.\r
    [20:23:18 WARN  game] Ignored unknown location 'Custom_LASV_GabbiHouse' in save data, including NPCs 'Gabbi', 'Gellos'.\r
    [20:23:18 WARN  game] Ignored unknown location 'EastScarp_Village' in save data.\r
    [20:23:18 WARN  game] Ignored unknown location 'EastScarp_VetHouse' in save data, including NPCs 'Eloise', 'Jacob', 'RichieTheMacaw'.\r
    [20:23:18 WARN  game] Ignored unknown location 'Custom_Ridgeside_PikaHouse' in save data, including NPCs 'Keahi', 'Pika'.\r
    [20:23:18 WARN  game] Ignored unknown location 'Custom_Ridgeside_IanHouse' in save data, including NPCs 'Ian', 'Sean'.\r
    [20:23:18 WARN  game] Ignored unknown location 'Custom_Ridgeside_RidgeFalls' in save data.\r
    """

    @Test func readsUnknownLocationsAndLoadedSave() {
        let log = SMAPILog(text: Self.log)
        #expect(log.loadedSaveID == "Mats_391030616")
        let locations = log.unknownLocations
        #expect(locations.count == 10)
        #expect(locations[3] == UnknownLocation(name: "Custom_LASV_LunnaHouse", npcs: ["Lunna"]))
        #expect(locations[6].npcs == ["Eloise", "Jacob", "RichieTheMacaw"])
    }

    @Test func groupsLocationsByMod() {
        let groups = SaveAnalyzer.group(SMAPILog(text: Self.log).unknownLocations)
        #expect(groups.map(\.key) == ["Ridgeside", "Additional Farm Cave", "LASV", "East Scarp", "Minecart Cave"])
        #expect(groups[0].npcs == ["Keahi", "Pika", "Ian", "Sean"])
        #expect(groups[2].searchTerms == ["LASV", "Lunna", "Gabbi", "Gellos"])
    }

    @Test func humanizesIdentifiers() {
        #expect(SaveAnalyzer.humanized("EastScarp") == "East Scarp")
        #expect(SaveAnalyzer.humanized("LASV") == "LASV")
        #expect(SaveAnalyzer.humanized("NPCHouse") == "NPC House")
    }

    @Test func findsModIDsInSaveFiles() throws {
        let tmp = try TempDir()
        let save = tmp.url.appending(path: "Farm_1")
        try Data("""
        <SaveGame xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <item><key><string>FlashShifter.StardewValleyExpandedCP_Sophia</string></key></item>
          <name>Mateo.SpecialOrders.AQ1_Objective</name>
          <modData><key>spacechase0.SpaceCore/Skills</key></modData>
          <name>(O)StardewValley.Thing_x</name>
        </SaveGame>
        """.utf8).write(to: save)
        let ids = try SaveAnalyzer.candidateModIDs(inSaveFile: save)
        #expect(ids["FlashShifter.StardewValleyExpandedCP"] == 1)
        #expect(ids["Mateo.SpecialOrders"] == 1)      // parent of Mateo.SpecialOrders.AQ1
        #expect(ids["spacechase0.SpaceCore"] == 1)
        #expect(ids.keys.allSatisfy { !$0.lowercased().hasPrefix("www") && !$0.hasPrefix("StardewValley.") })
    }

    @Test func readsSaveGameInfo() throws {
        let tmp = try TempDir()
        let folder = tmp.url.appending(path: "Mats_123", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("<Farmer><name>Mat</name><farmName>Mat&apos;s</farmName><dayOfMonthForSaveGame>20</dayOfMonthForSaveGame><seasonForSaveGame>2</seasonForSaveGame><yearForSaveGame>1</yearForSaveGame><gameVersion>1.6.13</gameVersion></Farmer>".utf8)
            .write(to: folder.appending(path: "SaveGameInfo"))
        try Data().write(to: folder.appending(path: "Mats_123"))
        let save = try #require(SaveGame.list(in: tmp.url).first)
        #expect(save.farmName == "Mat's")
        #expect(save.dateText == "Fall 20, Year 1")
        #expect(save.gameVersion == "1.6.13")
    }

    @Test func matchesWordsAndAuthors() {
        #expect(SaveAnalyzer.wordsMatch("Vendor Portraits", "They Deserve It Too - Portraits for Vendors"))
        #expect(!SaveAnalyzer.wordsMatch("LASV", "AtlasV Collection Catalogue"))
        #expect(SaveAnalyzer.authorMatches("DolphINaF", "Dolphin Is Not a Fish"))
        #expect(!SaveAnalyzer.authorMatches("Mateo", "Pathoschild"))
        #expect(SaveAnalyzer.modName(fromUniqueID: "FlashShifter.StardewValleyExpandedCP") == "Stardew Valley Expanded")
        #expect(SaveAnalyzer.modName(fromUniqueID: "spacechase0.SpaceCore") == "Space Core")
    }

    @Test func spotsTranslations() {
        func mod(_ name: String) -> NexusMod {
            NexusMod(modId: 1, name: name, summary: nil, author: nil, version: nil, downloads: nil, endorsements: nil, thumbnailUrl: nil, pictureUrl: nil, updatedAt: nil)
        }
        #expect(mod("Grampleton Fields CN").isLikelyTranslation)
        #expect(mod("Ridgeside Village - Chinese").isLikelyTranslation)
        #expect(!mod("Ridgeside Village").isLikelyTranslation)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["LIVE_API_TESTS"] == "1"))
struct LiveSaveTests {
    @Test func matchesMissingContentOnNexus() async throws {
        let client = NexusClient(apiKey: nil, appVersion: "test")
        let groups = SaveAnalyzer.group(SMAPILog(text: SaveAnalysisTests.log).unknownLocations)
        let ridgeside = try await client.likelyMod(for: groups.first { $0.key == "Ridgeside" }!)
        #expect(ridgeside?.modID == 7286)
        let lasv = try await client.likelyMod(for: groups.first { $0.key == "LASV" }!)
        #expect(lasv?.name.contains("Lunna") == true)  // found through its NPC, not "AtlasV"
        #expect(lasv?.matchedTerm == "Lunna")
    }

    @Test func findsContentPacksByAuthorAndName() async throws {
        let client = NexusClient(apiKey: nil, appVersion: "test")
        #expect(try await client.findMod(forUniqueID: "FlashShifter.StardewValleyExpandedCP")?.modID == 3753)
        #expect(try await client.findMod(forUniqueID: "Sonozuki.MoreGrass")?.modID == 5398)
        #expect(try await client.findMod(forUniqueID: "DolphINaF.VendorPortraits")?.modID == 20414)
        #expect(try await client.findMod(forUniqueID: "Mateo.SpecialOrders") == nil)  // an NPC's data, not a mod
    }

    @Test func confirmsSaveModIDsWithSMAPI() async throws {
        let records = try await UpdateChecker().lookup(uniqueIDs: ["FlashShifter.SVECode", "Mateo.SpecialOrders"])
        #expect(records["flashshifter.svecode"]?.nexusID == 3753)
        #expect(records["mateo.specialorders"] == nil)
    }
}
