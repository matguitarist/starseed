// Groups the parts of multi-folder mods into one entry. Stardew Valley
// Expanded, for example, installs "[CP] Stardew Valley Expanded",
// "[FTM] Stardew Valley Expanded" and "Stardew Valley Expanded Code";
// disabling just one part breaks the mod.

import Foundation

public struct ModGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let mods: [ModInfo]
    /// A real folder in Mods/ that holds the parts (vs. parts matched by name).
    public let isFolder: Bool

    public var isGroup: Bool { mods.count > 1 || isFolder }

    public init(id: String, name: String, mods: [ModInfo], isFolder: Bool) {
        self.id = id
        self.name = name
        self.mods = mods
        self.isFolder = isFolder
    }
}

public enum ModGrouping {
    /// Every mod in exactly one group; single mods are one-member groups.
    /// Parts are grouped when they sit in the same folder inside Mods/, share
    /// a Nexus number, or have the same name once framework tags are removed
    /// ("[CP] X", "X Code" -> "X"). SMAPI's bundled mods are never grouped.
    public static func groups(_ mods: [ModInfo], nexusID: (ModInfo) -> Int?) -> [ModGroup] {
        var parent = Array(mods.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }

        var firstWithKey: [String: Int] = [:]
        for (index, mod) in mods.enumerated() {
            var keys: [String] = []
            if let folder = mod.containerPath.first {
                keys.append("folder:" + folder.lowercased())
            } else if !mod.uniqueID.lowercased().hasPrefix("smapi.") {
                if let id = nexusID(mod) { keys.append("nexus:\(id)") }
                let base = baseName(mod.bareFolderName)
                if base.count >= 4 { keys.append("name:" + base) }
            }
            for key in keys {
                if let other = firstWithKey[key] { union(index, other) } else { firstWithKey[key] = index }
            }
        }

        // Same author and one name starts the other ("Lemurkat.EastScarp" and
        // "Lemurkat.EastScarpNPCs"; "East Scarp" and "East Scarp Core").
        // Requiring the same author keeps "Content Patcher" and another
        // author's "Content Patcher Animations" apart.
        let candidates = mods.indices.filter { mods[$0].containerPath.isEmpty && !mods[$0].uniqueID.lowercased().hasPrefix("smapi.") && !mods[$0].uniqueID.isEmpty }
        let keys = Dictionary(uniqueKeysWithValues: candidates.map { ($0, familyKeys(mods[$0])) })
        for (position, a) in candidates.enumerated() {
            for b in candidates[(position + 1)...] where find(a) != find(b) {
                guard let ka = keys[a], let kb = keys[b], ka.author == kb.author else { continue }
                if isNamePrefix(ka.idName, kb.idName) || isWordPrefix(ka.folderWords, kb.folderWords) {
                    union(a, b)
                }
            }
        }

        let clusters = Dictionary(grouping: mods.indices, by: find)
        return clusters.values.map { indices in
            let members = indices.map { mods[$0] }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            if let folder = members.first?.containerPath.first, members.allSatisfy({ $0.containerPath.first == folder }) {
                let name = String(folder.drop { $0 == "." })
                return ModGroup(id: "folder:" + folder, name: name, mods: members, isFolder: true)
            }
            if members.count == 1 {
                return ModGroup(id: members[0].id, name: members[0].displayName, mods: members, isFolder: false)
            }
            // Name the group after its shortest tag-free folder name ("Stardew Valley Expanded").
            // Prefer readable names ("Ridgeside Village" over "RidgesideVillage").
            let names = members.map { strippedName($0.bareFolderName) }
            let readable = names.filter { $0.contains(" ") }
            let name = (readable.isEmpty ? names : readable).min { $0.count < $1.count } ?? members[0].displayName
            return ModGroup(id: "group:" + members.map(\.id).sorted().joined(separator: "|"), name: name, mods: members, isFolder: false)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Folder name without framework tags: "[CP] Stardew Valley Expanded",
    /// "Stardew Valley Expanded Code" -> "Stardew Valley Expanded".
    static func strippedName(_ folderName: String) -> String {
        // Plain string handling, not Regex: this runs for every mod on every refresh.
        var name = folderName.trimmingCharacters(in: .whitespaces)
        if let first = name.first, first == "[" || first == "(",
           let close = name.firstIndex(of: first == "[" ? "]" : ")") {
            name = String(name[name.index(after: close)...]).trimmingCharacters(in: .whitespaces)  // "[CP] X"
        }
        if let last = name.last, last == "]" || last == ")",
           let open = name.lastIndex(of: last == "]" ? "[" : "("), open != name.startIndex {
            name = String(name[..<open]).trimmingCharacters(in: .whitespaces)  // "X [CP]"
        }
        let suffixes = ["code", "cp", "ftm", "ja", "at", "mfm", "dga", "stf", "bfav", "assets", "content", "c#", "smapi"]
        var words = name.split(separator: " ")
        while words.count > 1, let last = words.last, suffixes.contains(last.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "-_"))) {
            words.removeLast()
        }
        name = words.joined(separator: " ")
        return name.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-_")))
    }

    private struct FamilyKeys {
        let author: String
        let idName: String          // "eastscarpnpcs" from "Lemurkat.EastScarpNPCs"
        let folderWords: [String]   // ["east", "scarp", "npcs"]
    }

    private static func familyKeys(_ mod: ModInfo) -> FamilyKeys {
        let segments = mod.uniqueID.lowercased().split(separator: ".")
        let idName = segments.dropFirst().joined().filter { $0.isLetter || $0.isNumber }
        let words = strippedName(mod.bareFolderName).lowercased()
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return FamilyKeys(author: segments.first.map(String.init) ?? "", idName: idName, folderWords: words)
    }

    /// One ID name starts the other and is long enough to mean something.
    private static func isNamePrefix(_ a: String, _ b: String) -> Bool {
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        return short.count >= 6 && long.hasPrefix(short)
    }

    /// One folder name's words start the other's (at least two words).
    private static func isWordPrefix(_ a: [String], _ b: [String]) -> Bool {
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        return short.count >= 2 && Array(long.prefix(short.count)) == short
    }

    static func baseName(_ folderName: String) -> String {
        strippedName(folderName).lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
