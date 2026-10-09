// After mods are removed, finds the requirements nothing else uses anymore
// (e.g. SpaceCore and tilesheet packs left behind by deleting East Scarp),
// so they can be offered for removal too.

import Foundation

public struct UnusedRequirement: Identifiable, Hashable, Sendable {
    public let mod: ModInfo
    /// Names of the removed mods (or other unused requirements) that needed it.
    public let neededBy: [String]

    public var id: String { mod.id }

    public init(mod: ModInfo, neededBy: [String]) {
        self.mod = mod
        self.neededBy = neededBy
    }
}

public enum UnusedRequirements {
    /// Mods in `remaining` that `removed` required and that no other remaining
    /// mod (enabled or not) still requires. Follows chains: a requirement only
    /// needed by another unused requirement is unused too. Only *required*
    /// dependencies and content-pack frameworks count, never optional ones;
    /// SMAPI's bundled mods are never suggested.
    public static func find(removed: [ModInfo], remaining: [ModInfo]) -> [UnusedRequirement] {
        func required(by mod: ModInfo) -> [String] {
            mod.dependencies.filter(\.isRequired).map { $0.uniqueID.lowercased() }
                + [mod.contentPackFor?.lowercased()].compactMap { $0 }
        }

        var gone = removed                       // removed mods + unused requirements found so far
        var unused: [UnusedRequirement] = []
        var changed = true
        while changed {
            changed = false
            let goneIDs = Set(gone.map(\.id))
            let stillHere = remaining.filter { !goneIDs.contains($0.id) }
            for candidate in stillHere {
                let id = candidate.uniqueID.lowercased()
                guard !id.isEmpty, !id.hasPrefix("smapi.") else { continue }
                let neededByGone = gone.filter { required(by: $0).contains(id) }
                guard !neededByGone.isEmpty else { continue }
                let stillNeeded = stillHere.contains { $0.id != candidate.id && required(by: $0).contains(id) }
                guard !stillNeeded else { continue }
                unused.append(UnusedRequirement(mod: candidate, neededBy: neededByGone.map(\.displayName)))
                gone.append(candidate)
                changed = true
            }
        }
        return unused
    }
}
