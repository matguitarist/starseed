// Save games and the mods they depend on.
//
// A save made with mods (e.g. on another computer) records traces of them:
//  - Stardew 1.6 mods prefix their item/NPC/location IDs with their UniqueID
//    ("FlashShifter.StardewValleyExpandedCP_..."), which SMAPI's mod database
//    can turn into a mod name and Nexus page: *detected* mods.
//  - Older-style content ("Custom_Ridgeside_PikaHouse", "EastScarp_Village")
//    has no UniqueID, but when the save is loaded without its mods SMAPI logs
//    "Ignored unknown location '...' in save data, including NPC '...'".
//    Those names are grouped and matched by Nexus search: *likely* mods.

import Foundation

public struct SaveGame: Identifiable, Hashable, Sendable {
    public let folder: URL
    public let farmerName: String
    public let farmName: String
    public let gameVersion: String?
    public let dateText: String?      // "Spring 1, Year 1"
    public let lastSaved: Date?

    public var id: String { folder.lastPathComponent }
    public var saveFile: URL { folder.appending(path: folder.lastPathComponent) }

    /// Where the game keeps saves on macOS.
    public static let defaultFolder = URL.homeDirectory.appending(path: ".config/StardewValley/Saves", directoryHint: .isDirectory)

    /// All saves, most recently saved first.
    public static func list(in folder: URL = defaultFolder) -> [SaveGame] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return entries.compactMap(load).sorted { ($0.lastSaved ?? .distantPast) > ($1.lastSaved ?? .distantPast) }
    }

    static func load(_ folder: URL) -> SaveGame? {
        let info = folder.appending(path: "SaveGameInfo")
        guard let text = try? String(contentsOf: info, encoding: .utf8) else { return nil }
        func tag(_ name: String) -> String? {
            guard let open = text.range(of: "<\(name)>"),
                  let close = text.range(of: "</\(name)>", range: open.upperBound..<text.endIndex)
            else { return nil }
            return String(text[open.upperBound..<close.lowerBound]).xmlUnescaped
        }
        let seasons = ["Spring", "Summer", "Fall", "Winter"]
        var dateText: String?
        if let day = tag("dayOfMonthForSaveGame"), let year = tag("yearForSaveGame"),
           let season = tag("seasonForSaveGame").flatMap(Int.init), seasons.indices.contains(season) {
            dateText = "\(seasons[season]) \(day), Year \(year)"
        }
        let modified = try? folder.appending(path: folder.lastPathComponent)
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return SaveGame(
            folder: folder,
            farmerName: tag("name") ?? folder.lastPathComponent,
            farmName: tag("farmName") ?? "",
            gameVersion: tag("gameVersion"),
            dateText: dateText,
            lastSaved: modified
        )
    }
}

/// A location the game dropped because the mod adding it isn't installed.
public struct UnknownLocation: Hashable, Sendable {
    public let name: String
    public let npcs: [String]
}

/// Unknown locations grouped by the mod they probably came from.
public struct MissingContentGroup: Identifiable, Hashable, Sendable {
    public let key: String            // "Ridgeside", "East Scarp", "LASV"...
    public let locations: [String]
    public let npcs: [String]

    public var id: String { key }

    /// What to search Nexus for, best guess first: the group name, then NPC names.
    public var searchTerms: [String] {
        [key] + npcs.prefix(3)
    }
}

extension SMAPILog {
    /// The save SMAPI loaded in this session ("Context: loaded save 'Mats_391030616'").
    public var loadedSaveID: String? {
        entries.lazy.compactMap { $0.message.firstMatch(of: /^Context: loaded save '([^']+)'/) }.first.map { String($0.1) }
    }

    /// "Ignored unknown location 'X' in save data[, including NPC(s) 'A', 'B']."
    public var unknownLocations: [UnknownLocation] {
        entries.compactMap { entry in
            guard entry.source == "game",
                  let match = entry.message.firstMatch(of: /^Ignored unknown location '([^']+)' in save data(?:, including NPCs? (.+?))?\.?$/)
            else { return nil }
            let npcs = match.2.map { list in
                list.matches(of: /'([^']+)'/).map { String($0.1) }
            } ?? []
            return UnknownLocation(name: String(match.1), npcs: npcs)
        }
    }
}

public enum SaveAnalyzer {
    /// Groups unknown locations by name prefix: "Custom_Ridgeside_PikaHouse"
    /// and "Custom_Ridgeside_IanHouse" -> "Ridgeside"; "EastScarp_Village"
    /// -> "East Scarp"; "Custom_AdditionalFarmCave2" -> "Additional Farm Cave".
    public static func group(_ locations: [UnknownLocation]) -> [MissingContentGroup] {
        var groups: [String: (locations: [String], npcs: [String])] = [:]
        var order: [String] = []
        for location in locations {
            let key = groupKey(for: location.name)
            if groups[key] == nil { order.append(key) }
            groups[key, default: ([], [])].locations.append(location.name)
            groups[key, default: ([], [])].npcs += location.npcs
        }
        return order.map { key in
            var seen = Set<String>()
            let npcs = groups[key]!.npcs.filter { seen.insert($0).inserted }
            return MissingContentGroup(key: key, locations: groups[key]!.locations, npcs: npcs)
        }
        .sorted { $0.locations.count > $1.locations.count }
    }

    static func groupKey(for location: String) -> String {
        var name = location
        if name.hasPrefix("Custom_") { name.removeFirst("Custom_".count) }
        let parts = name.split(separator: "_")
        // "Ridgeside_PikaHouse" -> "Ridgeside"; a single part is the whole name.
        var key = parts.count >= 2 ? String(parts[0]) : name
        while key.last?.isNumber == true { key.removeLast() }
        return humanized(key)
    }

    /// "EastScarp" -> "East Scarp", "AdditionalFarmCave" -> "Additional Farm Cave", "LASV" stays.
    static func humanized(_ identifier: String) -> String {
        var result = ""
        let characters = Array(identifier)
        for (index, character) in characters.enumerated() {
            if index > 0, character.isUppercase,
               characters[index - 1].isLowercase || (index + 1 < characters.count && characters[index + 1].isLowercase && characters[index - 1].isUppercase) {
                result.append(" ")
            }
            result.append(character)
        }
        return result
    }

    /// UniqueID-like prefixes in a save ("Author.ModName" before "_" or "/"),
    /// plus their shorter parents ("Mateo.SpecialOrders.AQ1" -> "Mateo.SpecialOrders"),
    /// with occurrence counts. Most are real mod IDs; SMAPI's database filters the rest.
    public static func candidateModIDs(inSaveFile file: URL) throws -> [String: Int] {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let text = String(decoding: data, as: UTF8.self) as NSString
        // NSRegularExpression is far faster than Swift Regex on a 20+ MB save.
        let regex = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9.])([A-Za-z][A-Za-z0-9\-]*(?:\.[A-Za-z0-9\-]+){1,4})(?=[_/])"#)
        var counts: [String: Int] = [:]
        regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let range = match?.range(at: 1) else { return }
            counts[text.substring(with: range), default: 0] += 1
        }
        var candidates: [String: Int] = [:]
        for (id, count) in counts where !isIgnoredNamespace(id) {
            var parts = id.split(separator: ".")
            while parts.count >= 2 {
                candidates[parts.joined(separator: "."), default: 0] += count
                parts.removeLast()
            }
        }
        return candidates
    }

    private static func isIgnoredNamespace(_ id: String) -> Bool {
        let lower = id.lowercased()
        return ["www.", "http", "stardewvalley.", "microsoft.", "system.", "xna."].contains { lower.hasPrefix($0) }
            || lower.hasSuffix(".org") || lower.hasSuffix(".com") || lower.hasSuffix(".xml")
    }
}

extension NexusMod {
    /// Translations rank high in name searches but aren't the mod itself.
    public var isLikelyTranslation: Bool {
        let lower = name.lowercased()
        let markers = ["translation", "chinese", " cn", "(cn", "russian", "spanish", "español", "portugu", "french", "français",
                       "german", "deutsch", "korean", "japanese", "italian", "polish", "turkish", "thai", "vietnamese",
                       "indonesian", "ukrain", "中文", "русск"]
        return markers.contains { lower.contains($0) } || lower.hasSuffix(" cn")
    }
}

/// A Nexus mod matched to a save's mod ID or missing content.
public struct ModMatch: Hashable, Sendable {
    public enum Confidence: Int, Comparable, Sendable {
        case byName = 0     // name search; check before installing
        case byAuthor = 1   // the ID's author uploaded a mod with this name
        case confirmed = 2  // SMAPI's mod database knows this UniqueID
        case chosen = 3     // picked by the user (pasted Nexus link)

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let modID: Int
    public let name: String
    public let author: String?
    public let confidence: Confidence
    public let matchedTerm: String

    public init(modID: Int, name: String, author: String?, confidence: Confidence, matchedTerm: String) {
        self.modID = modID
        self.name = name
        self.author = author
        self.confidence = confidence
        self.matchedTerm = matchedTerm
    }
}

extension SaveAnalyzer {
    /// "StardewValleyExpandedCP" -> "Stardew Valley Expanded" (drops a
    /// trailing framework tag like CP/JA/FTM), "MoreGrass" -> "More Grass".
    static func modName(fromUniqueID id: String) -> String {
        var last = String(id.split(separator: ".").last ?? Substring(id))
        if let match = last.firstMatch(of: /[a-z](CP|JA|FTM|MFM|AT|CS|STF|BETAS|DGA)$/) {
            last.removeLast(match.1.count)
        }
        return humanized(last)
    }

    /// Every word of `term` starts a word of `name` ("Vendor Portraits" ~
    /// "Portraits for Vendors"); rejects substring hits like "LASV" in "AtlasV".
    static func wordsMatch(_ term: String, _ name: String) -> Bool {
        func words(_ text: String) -> [String] {
            text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
        let nameWords = words(name)
        let termWords = words(term)
        return !termWords.isEmpty && termWords.allSatisfy { word in nameWords.contains { $0.hasPrefix(word) } }
    }

    /// The ID's author segment loosely matches a Nexus author: same first
    /// letter and its letters appear in order ("DolphINaF" ~ "Dolphin Is Not a Fish").
    static func authorMatches(_ segment: String, _ author: String?) -> Bool {
        guard let author else { return false }
        let a = segment.lowercased().filter { $0.isLetter || $0.isNumber }
        let b = author.lowercased().filter { $0.isLetter || $0.isNumber }
        guard let first = a.first, b.first == first else { return false }
        var remaining = b[...]
        for character in a {
            guard let index = remaining.firstIndex(of: character) else { return false }
            remaining = remaining[remaining.index(after: index)...]
        }
        return true
    }
}

extension NexusClient {
    /// Finds the Nexus mod for a UniqueID SMAPI doesn't know (content packs
    /// mostly): first among mods uploaded by the ID's author, then by name
    /// with a loose author check. Nil rather than a wild guess.
    public func findMod(forUniqueID id: String) async throws -> ModMatch? {
        let segments = id.split(separator: ".").map(String.init)
        guard segments.count >= 2 else { return nil }
        let author = segments[0]
        let name = SaveAnalyzer.modName(fromUniqueID: id)

        let byUploader = try await searchMods(query: "", sort: .endorsements, count: 50, uploader: author)
        if let mod = byUploader.mods.first(where: { SaveAnalyzer.wordsMatch(name, $0.name) }) {
            return ModMatch(modID: mod.modId, name: mod.name, author: mod.author, confidence: .byAuthor, matchedTerm: name)
        }

        let byName = try await searchMods(query: name, sort: .endorsements, count: 10)
        if let mod = byName.mods.first(where: {
            !$0.isLikelyTranslation && SaveAnalyzer.wordsMatch(name, $0.name) && SaveAnalyzer.authorMatches(author, $0.author)
        }) {
            return ModMatch(modID: mod.modId, name: mod.name, author: mod.author, confidence: .byName, matchedTerm: name)
        }
        return nil
    }

    /// Best Nexus match for a group of missing content: tries the group
    /// name, then its NPC names, skipping translations and partial-word hits.
    public func likelyMod(for group: MissingContentGroup) async throws -> ModMatch? {
        for term in group.searchTerms {
            let page = try await searchMods(query: term, sort: .endorsements, count: 10)
            if let mod = page.mods.first(where: { !$0.isLikelyTranslation && SaveAnalyzer.wordsMatch(term, $0.name) }) {
                return ModMatch(modID: mod.modId, name: mod.name, author: mod.author, confidence: .byName, matchedTerm: term)
            }
        }
        return nil
    }
}

extension String {
    var xmlUnescaped: String {
        replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
