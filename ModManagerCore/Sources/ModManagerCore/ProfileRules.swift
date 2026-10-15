// The rules behind profiles (named sets of enabled mods, one always in
// use). Pure functions on UniqueIDs, so they can be tested; the app keeps
// the profiles and applies the results to the Mods folder.
//
// UniqueIDs compare case-insensitively, like SMAPI.

import Foundation

public enum ProfileRules {
    /// The profile's mods after the user changed which are on: the enabled
    /// mods, plus the profile's mods that aren't installed (from another Mac,
    /// or not downloaded yet), which stay in it. Nil when nothing changed.
    public static func tracked(saved: [String], enabled: [String], installed: Set<String>) -> [String]? {
        let installedKeys = Set(installed.map { $0.lowercased() })
        let notInstalled = saved.filter { !installedKeys.contains($0.lowercased()) }
        let updated = unique(enabled + notInstalled)
        return keys(updated) == keys(saved) ? nil : updated
    }

    /// A profile whose mods are exactly the enabled ones (first by name).
    public static func matching(_ profiles: [String: [String]], enabled: [String]) -> String? {
        let wanted = keys(enabled)
        return profiles.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .first { keys(profiles[$0] ?? []) == wanted }
    }

    /// `base`, or `numbered(2)`, `numbered(3)`… when taken.
    public static func uniqueName(_ base: String, taken: (String) -> Bool, numbered: (Int) -> String) -> String {
        guard taken(base) else { return base }
        var counter = 2
        while taken(numbered(counter)) { counter += 1 }
        return numbered(counter)
    }

    /// `existing` with `adding` appended, without duplicates.
    public static func merged(_ existing: [String], adding: [String]) -> [String] {
        unique(existing + adding)
    }

    /// `ids` without `removing` (e.g. new downloads that belong elsewhere).
    public static func removing(_ removing: [String], from ids: [String]) -> [String] {
        let gone = keys(removing)
        return ids.filter { !gone.contains($0.lowercased()) }
    }

    /// SMAPI's own mods (Console Commands, Save Backup): kept on in a
    /// profile that starts with no mods.
    public static func smapiBundled(_ ids: [String]) -> [String] {
        ids.filter { $0.lowercased().hasPrefix("smapi.") }
    }

    static func keys(_ ids: [String]) -> Set<String> {
        Set(ids.map { $0.lowercased() })
    }

    static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    // MARK: Saves

    /// Saves to link to the profile a session was played with: the ones
    /// saved during it (new farms included) that aren't linked yet. A save
    /// already linked keeps its profile.
    public static func savesToLink(saved: [(id: String, lastSaved: Date?)], since launch: Date, linked: Set<String>) -> [String] {
        saved.filter { save in
            guard let date = save.lastSaved, !linked.contains(save.id) else { return false }
            return date >= launch.addingTimeInterval(-5)
        }.map(\.id)
    }

    /// Saves grouped by profile: the profile in use first, then the others
    /// in `order`, then the unlinked ones (nil). Links to deleted profiles
    /// count as unlinked. Saves keep their order inside each group.
    public static func groupedSaves(_ ids: [String], links: [String: String], order: [String], active: String?) -> [(profile: String?, saves: [String])] {
        let known = Set(order)
        var groups: [String?: [String]] = [:]
        for id in ids {
            let profile = links[id].flatMap { known.contains($0) ? $0 : nil }
            groups[profile, default: []].append(id)
        }
        let names = (active.map { [$0] } ?? []) + order.filter { $0 != active }
        return names.compactMap { name in groups[name].map { (Optional(name), $0) } }
            + (groups[nil].map { [(nil, $0)] } ?? [])
    }

}
