// The mods and content packs SMAPI says it loaded, from the log's
// "Loaded 7 mods:" and "Loaded 2 content packs:" lists.

import Foundation

public struct LoadedMod: Hashable, Sendable, Identifiable {
    public let name: String
    public let version: String
    public let author: String?
    public let description: String?
    /// The framework a content pack is for ("Content Patcher"); nil for mods.
    public let contentPackFor: String?

    public var isContentPack: Bool { contentPackFor != nil }
    public var id: String { "\(isContentPack ? "pack" : "mod"):\(name)" }
}

extension SMAPILog {
    /// What SMAPI loaded in this session, mods first then content packs.
    /// Empty when the log stopped before SMAPI listed them.
    public var loadedMods: [LoadedMod] {
        var result: [LoadedMod] = []
        var inList: Bool? = nil  // nil: not in a list; false: mods; true: content packs
        var listLevel = LogLevel.info
        for entry in entries where entry.source == "SMAPI" {
            let message = entry.message
            if message.hasPrefix("Loaded "), message.hasSuffix(":") {
                if message.contains(" content pack") { inList = true; listLevel = entry.level; continue }
                if message.contains(" mod") { inList = false; listLevel = entry.level; continue }
            }
            guard let isPack = inList else { continue }
            // List lines are indented, at the list's level, and name a mod
            // with a version; anything else (e.g. the warning after it) ends it.
            guard entry.level == listLevel, message.first?.isWhitespace == true,
                  let mod = Self.parseLoaded(message, contentPack: isPack), !mod.version.isEmpty
            else {
                inList = nil
                continue
            }
            result.append(mod)
        }
        return result
    }

    /// "   Name 1.2.3 by Author | for Framework | Description" (the "for"
    /// part only for content packs; author and description are optional).
    static func parseLoaded(_ line: String, contentPack: Bool) -> LoadedMod? {
        let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " | ")
        guard let head = parts.first, !head.isEmpty else { return nil }
        var framework: String?
        var rest = Array(parts.dropFirst())
        if contentPack, let first = rest.first, first.hasPrefix("for ") {
            framework = String(first.dropFirst(4))
            rest.removeFirst()
        }
        let description = rest.isEmpty ? nil : rest.joined(separator: " | ")

        var nameAndVersion = head
        var author: String?
        if let range = head.range(of: " by ") {
            nameAndVersion = String(head[..<range.lowerBound])
            author = String(head[range.upperBound...])
        }
        var name = nameAndVersion
        var version = ""
        if let space = nameAndVersion.lastIndex(of: " "), nameAndVersion[nameAndVersion.index(after: space)...].first?.isNumber == true {
            name = String(nameAndVersion[..<space])
            version = String(nameAndVersion[nameAndVersion.index(after: space)...])
        }
        return LoadedMod(name: name, version: version, author: author, description: description,
                         contentPackFor: contentPack ? (framework ?? "") : nil)
    }
}
