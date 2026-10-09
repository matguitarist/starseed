// Matches a missing dependency's UniqueID to an entry of the requiring mod's
// Nexus "Requirements" list. Tilesheet and content packs are often missing
// from SMAPI's mod database, but the mod that needs them names them on its
// Nexus page: "Lumisteria.LumiTilesheetsIndoor" -> "Lumisteria Tilesheets -
// Indoor" (#9599), even with typos like "Lumisteria.TtilesheetsOutdoor".

import Foundation

public enum RequirementMatcher {
    /// The requirement that best matches `uniqueID`, or nil if none clearly does.
    public static func bestMatch(for uniqueID: String, among requirements: [NexusRequirement]) -> NexusRequirement? {
        let idTokens = tokens(ofUniqueID: uniqueID)
        let scored = requirements.compactMap { requirement -> (NexusRequirement, Int)? in
            guard requirement.modID != nil else { return nil }
            let nameTokens = tokens(ofName: requirement.name)
            let score = idTokens.filter { token in nameTokens.contains { matches(token, $0) } }.count
            return score > 0 ? (requirement, score) : nil
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }) else { return nil }
        // Ambiguous (two equally good candidates) or too weak: no guess.
        let tied = scored.filter { $0.1 == best.1 }.count > 1
        let strongEnough = best.1 >= 2 || (idTokens.count == 1 && best.1 == 1)
        return tied || !strongEnough ? nil : best.0
    }

    /// "Lumisteria.LumiTilesheetsIndoor" -> ["lumisteria", "lumi", "tilesheets", "indoor", "lumitilesheetsindoor"].
    static func tokens(ofUniqueID id: String) -> [String] {
        var result: [String] = []
        for segment in id.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let words = splitCamelCase(String(segment))
            result += words
            if words.count > 1 { result.append(segment.lowercased()) }  // "hxw", "lumitilesheetsindoor"
        }
        let ignored: Set = ["cp", "ja", "ftm", "smapi", "mod", "the"]
        var seen = Set<String>()
        return result.filter { !ignored.contains($0) && seen.insert($0).inserted }
    }

    /// "Lumisteria Tilesheets - Indoor" -> ["lumisteria", "tilesheets", "indoor"].
    static func tokens(ofName name: String) -> [String] {
        name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func splitCamelCase(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        let chars = Array(text)
        for (index, char) in chars.enumerated() {
            let startsWord = index > 0 && char.isUppercase
                && (chars[index - 1].isLowercase || (index + 1 < chars.count && chars[index + 1].isLowercase))
            if startsWord, !current.isEmpty {
                words.append(current.lowercased())
                current = ""
            }
            current.append(char)
        }
        if !current.isEmpty { words.append(current.lowercased()) }
        return words
    }

    /// Same word, an abbreviation ("lumi" ~ "lumisteria"), or a one-letter typo in a long word.
    static func matches(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if min(a.count, b.count) >= 3, a.hasPrefix(b) || b.hasPrefix(a) { return true }
        return min(a.count, b.count) >= 5 && editDistance(a, b) <= 1
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...max(b.count, 1) where !b.isEmpty {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
