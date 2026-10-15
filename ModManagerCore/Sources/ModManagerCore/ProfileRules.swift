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
}
