// Turns SMAPI's log messages into plain-language findings with something
// to do about each: skipped mods (and why), mods that keep erroring, and
// SMAPI's "you can update" alerts.

import Foundation

public struct LogInsight: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// SMAPI didn't load a mod. `missingIDs`: required mods that aren't
        /// installed; `needsSMAPI`: the SMAPI version it wants.
        case skippedMod(name: String, reason: String, missingIDs: [String], needsSMAPI: String?)
        /// A mod logged errors while the game ran.
        case modErrors(source: String, count: Int, events: [String])
        /// SMAPI found newer versions of installed mods.
        case updatesAvailable([AvailableUpdate])
        /// SMAPI itself has an update.
        case smapiUpdate(version: String, url: URL?)
    }

    public struct AvailableUpdate: Hashable, Sendable {
        public let name: String
        public let version: String
        public let url: URL?
    }

    public let kind: Kind
    public let level: LogLevel

    public var id: String {
        switch kind {
        case .skippedMod(let name, _, _, _): "skipped:\(name)"
        case .modErrors(let source, _, _): "errors:\(source)"
        case .updatesAvailable: "updates"
        case .smapiUpdate: "smapi-update"
        }
    }
}

extension SMAPILog {
    public var insights: [LogInsight] {
        var skipped: [LogInsight] = []
        var updates: [LogInsight.AvailableUpdate] = []
        var smapiUpdate: LogInsight?
        var errorsBySource: [String: (count: Int, events: [String])] = [:]
        var inUpdateList = false

        for entry in entries {
            // Multi-line messages: SMAPI's lists are one entry per line.
            let message = entry.message

            // "   - Better Crafting 1.2.0 because it requires mods which aren't installed (leclair.Common)."
            if entry.source == "SMAPI", entry.level >= .warn, message.contains(" because "),
               let match = message.firstMatch(of: /^\s*-\s+(.+?)\s+because\s+(.+?)\.?\s*$/) {
                let name = Self.stripVersion(String(match.1))
                let reason = String(match.2)
                var missing: [String] = []
                if let ids = reason.firstMatch(of: /(?:requires|needs) mods which aren't installed \((.+)\)/) {
                    missing = ids.1.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        .map { $0.components(separatedBy: " ").first ?? $0 }
                }
                let smapi = reason.firstMatch(of: /SMAPI (\d+\.\d+(?:\.\d+)?)(?: or later)?/).map { String($0.1) }
                    ?? (reason.localizedCaseInsensitiveContains("newer version of SMAPI") ? "" : nil)
                skipped.append(LogInsight(kind: .skippedMod(name: name, reason: reason, missingIDs: missing, needsSMAPI: smapi), level: entry.level))
                continue
            }

            // "You can update SMAPI to 4.6.0: https://smapi.io"
            if message.hasPrefix("You can update SMAPI"), let match = message.firstMatch(of: /^You can update SMAPI to (\S+?):?\s+(https?:\/\/\S+)/) {
                smapiUpdate = LogInsight(kind: .smapiUpdate(version: String(match.1), url: URL(string: String(match.2))), level: entry.level)
                continue
            }

            // "You can update 2 mods:" followed by "   Name 1.2.3: https://…"
            if message.hasPrefix("You can update"), message.contains("mod") {
                inUpdateList = true
                continue
            }
            if inUpdateList {
                if entry.level == .alert, let match = message.firstMatch(of: /^\s+(.+?)\s+(\S+?):\s+(https?:\/\/\S+)\s*$/) {
                    updates.append(.init(name: String(match.1), version: String(match.2), url: URL(string: String(match.3))))
                    continue
                }
                inUpdateList = false
            }

            // Errors from mods (not SMAPI or the game itself).
            if entry.level >= .error, entry.source != "SMAPI", entry.source != "game" {
                var current = errorsBySource[entry.source] ?? (0, [])
                current.count += 1
                if message.contains("failed in the"), let event = message.firstMatch(of: /failed in the (\S+?) event/), !current.events.contains(String(event.1)) {
                    current.events.append(String(event.1))
                }
                errorsBySource[entry.source] = current
            }
        }

        var insights = skipped
        insights += errorsBySource
            .sorted { $0.value.count > $1.value.count }
            .map { LogInsight(kind: .modErrors(source: $0.key, count: $0.value.count, events: $0.value.events), level: .error) }
        if let smapiUpdate { insights.append(smapiUpdate) }
        if !updates.isEmpty { insights.append(LogInsight(kind: .updatesAvailable(updates), level: .alert)) }
        return insights
    }

    /// "Better Crafting 1.2.0" -> "Better Crafting".
    static func stripVersion(_ name: String) -> String {
        name.replacing(/\s+v?\d+(\.\d+)+(-[0-9A-Za-z.\-]+)?$/, with: "")
    }
}
