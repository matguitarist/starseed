// What changed between the installed version of a mod and its update,
// from Nexus. Authors write changelogs on the mod page (REST, key needed)
// or per file (GraphQL); many use only one of the two.

import Foundation

public struct ChangelogEntry: Hashable, Sendable {
    public let version: String
    public let lines: [String]

    public init(version: String, lines: [String]) {
        self.version = version
        self.lines = lines
    }
}

public enum Changelog {
    /// Entries newer than `installed`, up to and including `latest`, newest
    /// first. Versions that don't parse are kept only when they match `latest`.
    public static func entries(_ all: [ChangelogEntry], after installed: String, upTo latest: String) -> [ChangelogEntry] {
        let from = SemanticVersion(installed)
        let to = SemanticVersion(latest)
        let picked = all.filter { entry in
            guard let version = SemanticVersion(entry.version) else {
                return normalized(entry.version) == normalized(latest)
            }
            if let from, version <= from { return false }
            if let to, version > to { return false }
            return true
        }
        return sorted(picked)
    }

    /// Newest first; unparsable versions last.
    static func sorted(_ entries: [ChangelogEntry]) -> [ChangelogEntry] {
        entries.sorted { a, b in
            switch (SemanticVersion(a.version), SemanticVersion(b.version)) {
            case let (x?, y?): x > y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.version.localizedStandardCompare(b.version) == .orderedDescending
            }
        }
    }

    /// Merges per-file changelogs: several files (main + optional) usually
    /// repeat the same lines for a version.
    static func merge(_ pairs: [(version: String, lines: [String])]) -> [ChangelogEntry] {
        var order: [String] = []
        var byVersion: [String: [String]] = [:]
        for (version, lines) in pairs {
            let key = normalized(version)
            guard !key.isEmpty else { continue }
            if byVersion[key] == nil { order.append(key); byVersion[key] = [] }
            for line in lines.map(clean) where !line.isEmpty && !byVersion[key]!.contains(line) {
                byVersion[key]!.append(line)
            }
        }
        return order.compactMap { key in
            let lines = byVersion[key] ?? []
            return lines.isEmpty ? nil : ChangelogEntry(version: key, lines: lines)
        }
    }

    static func normalized(_ version: String) -> String {
        version.trimmingCharacters(in: .whitespaces).trimmingPrefix("v").trimmingPrefix("V").description
    }

    /// Nexus changelog lines can hold BBCode-ish HTML: "<br />", "&amp;", "<b>".
    static func clean(_ line: String) -> String {
        var text = line.replacingOccurrences(of: "<br />", with: " ")
            .replacingOccurrences(of: "<br/>", with: " ")
            .replacingOccurrences(of: "<br>", with: " ")
        // Drop tags.
        var out = ""
        var inTag = false
        for char in text {
            if char == "<" { inTag = true } else if char == ">" && inTag { inTag = false } else if !inTag { out.append(char) }
        }
        text = out
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#039;", "'"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        // "- Fixed X" / "* Fixed X": the UI draws its own bullets.
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.first, first == "-" || first == "*" || first == "•" {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return text
    }
}

extension NexusClient {
    /// The mod's changelog, newest first: the mod page's changelog when an API
    /// key is set and it has one, otherwise the files' changelogs.
    public func changelog(forMod modID: Int) async throws -> [ChangelogEntry] {
        if apiKey != nil, let page = try? await pageChangelog(forMod: modID), !page.isEmpty {
            return page
        }
        return try await fileChangelog(forMod: modID)
    }

    func pageChangelog(forMod modID: Int) async throws -> [ChangelogEntry] {
        // {"1.2.0": ["Fixed X", "Added Y"], ...}; an empty mod returns [].
        let data = try await restData("games/\(Self.gameDomain)/mods/\(modID)/changelogs.json")
        guard let map = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [] }
        return Changelog.sorted(Changelog.merge(map.map { ($0.key, $0.value) }))
    }

    func fileChangelog(forMod modID: Int) async throws -> [ChangelogEntry] {
        struct File: Decodable {
            let version: String?
            let changelogText: [String]?
        }
        struct Response: Decodable { let modFiles: [File] }
        let response: Response = try await graphQL(
            """
            query Changelog($modId: ID!, $gameId: ID!) {
              modFiles(modId: $modId, gameId: $gameId) { version changelogText }
            }
            """,
            variables: ["modId": String(modID), "gameId": String(Self.gameID)]
        )
        return Changelog.sorted(Changelog.merge(response.modFiles.map { ($0.version ?? "", $0.changelogText ?? []) }))
    }
}
