// Works out which required dependencies are missing across all enabled mods.

import Foundation

public struct MissingDependency: Identifiable, Hashable, Sendable {
    public let uniqueID: String
    /// Display names of the enabled mods that need it.
    public let requiredBy: [String]
    /// The dependency is installed but disabled; enabling it is enough.
    public let disabledCopy: ModInfo?

    public var id: String { uniqueID.lowercased() }

    public init(uniqueID: String, requiredBy: [String], disabledCopy: ModInfo?) {
        self.uniqueID = uniqueID
        self.requiredBy = requiredBy
        self.disabledCopy = disabledCopy
    }

    /// Groups each enabled mod's `missingDependencies` (filled in by
    /// `ModManager.scan()`) by dependency, sorted by how many mods need it.
    public static func find(in mods: [ModInfo]) -> [MissingDependency] {
        var neededBy: [String: (uniqueID: String, mods: [String])] = [:]
        for mod in mods where mod.isEnabled {
            for dependency in mod.missingDependencies {
                neededBy[dependency.lowercased(), default: (dependency, [])].mods.append(mod.displayName)
            }
        }
        return neededBy.map { key, value in
            MissingDependency(
                uniqueID: value.uniqueID,
                requiredBy: value.mods.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                disabledCopy: mods.first { !$0.isEnabled && $0.uniqueID.lowercased() == key }
            )
        }
        .sorted { ($0.requiredBy.count, $1.uniqueID) > ($1.requiredBy.count, $0.uniqueID) }
    }
}

extension NexusFile {
    /// Picks the file to install for a mod: a current main file whose version
    /// matches `version` if given, otherwise the newest main file, otherwise
    /// the newest current file of any kind.
    public static func bestMatch(in files: [NexusFile], version: String? = nil) -> NexusFile? {
        func normalized(_ value: String?) -> String {
            (value ?? "").lowercased().trimmingCharacters(in: .whitespaces).trimmingPrefix("v").description
        }
        let current = files.filter(\.isCurrent).sorted { $0.date > $1.date }
        let main = current.filter { $0.category == "MAIN" }
        if let version {
            let wanted = normalized(version)
            if let exact = main.first(where: { normalized($0.version) == wanted }) ?? current.first(where: { normalized($0.version) == wanted }) {
                return exact
            }
        }
        return main.first ?? current.first
    }
}
