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
            let name = members.map { strippedName($0.bareFolderName) }.min { $0.count < $1.count } ?? members[0].displayName
            return ModGroup(id: "group:" + members.map(\.id).sorted().joined(separator: "|"), name: name, mods: members, isFolder: false)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Folder name without framework tags: "[CP] Stardew Valley Expanded",
    /// "Stardew Valley Expanded Code" -> "Stardew Valley Expanded".
    static func strippedName(_ folderName: String) -> String {
        var name = folderName
            .replacing(/^\s*[\[(][^\])]*[\])]\s*/, with: "")   // leading "[CP] " / "(FTM) "
            .replacing(/\s*[\[(][^\])]*[\])]\s*$/, with: "")   // trailing " [CP]"
        let suffixes = ["code", "cp", "ftm", "ja", "at", "mfm", "dga", "stf", "bfav", "assets", "content", "c#", "smapi"]
        var words = name.split(separator: " ")
        while words.count > 1, let last = words.last, suffixes.contains(last.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "-_"))) {
            words.removeLast()
        }
        name = words.joined(separator: " ")
        return name.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-_")))
    }

    static func baseName(_ folderName: String) -> String {
        strippedName(folderName).lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
