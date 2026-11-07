// SMAPI's console log (SMAPI-latest.txt), read with LogKit.
//
// Each entry starts with "[HH:mm:ss LEVEL Source] message"; lines without
// that prefix (stack traces, multi-line messages) continue the previous entry.
// LogKit's `BracketLogParser` reads that format; this adds what SMAPI's
// messages say (versions, insights, loaded mods, the save).

@_exported import LogKit
import Foundation

public struct SMAPILog: Sendable {
    public let entries: [LogEntry]
    public let smapiVersion: String?
    public let gameVersion: String?
    public let platform: String?

    /// Where SMAPI writes its logs on macOS and Linux.
    public static let defaultFolder = URL.homeDirectory.appending(path: ".config/StardewValley/ErrorLogs", directoryHint: .isDirectory)
    public static var latestLogURL: URL { defaultFolder.appending(path: "SMAPI-latest.txt") }
    public static var crashLogURL: URL { defaultFolder.appending(path: "SMAPI-crash.txt") }

    public init(text: String) {
        self.init(entries: BracketLogParser().parse(text).entries)
    }

    public init(entries: [LogEntry]) {
        self.entries = entries
        // "SMAPI 4.1.10 with Stardew Valley 1.6.15 build 24356 on macOS Unix 14.5.0"
        let header = entries.lazy.filter { $0.message.hasPrefix("SMAPI ") }.compactMap {
            $0.message.firstMatch(of: /^SMAPI (\S+) with Stardew Valley (\S+)(?: build \d+)? on (.+)$/)
        }.first
        smapiVersion = header.map { String($0.1) }
        gameVersion = header.map { String($0.2) }
        platform = header.map { String($0.3) }
    }

    public static func load(from url: URL) throws -> SMAPILog {
        let data = try Data(contentsOf: url)
        return SMAPILog(text: String(decoding: data, as: UTF8.self))
    }

    /// The parser for the log viewer: SMAPI's lines, with the versions as
    /// metadata and the insights in plain words. `describe` gives an
    /// insight's title and detail in the person's language (the app has the
    /// strings, and the names of mods it looked up).
    public static func parser(
        describe: @escaping @Sendable (SMAPIInsight) -> (title: String, detail: String) = { ($0.id, "") }
    ) -> BracketLogParser {
        BracketLogParser { document in
            let log = SMAPILog(entries: document.entries)
            document.metadata = log.metadata
            document.insights = log.insights.map { insight in
                let text = describe(insight)
                return LogInsight(id: insight.id, level: insight.level, title: text.title, detail: text.detail,
                                  source: insight.source)
            }
        }
    }

    /// For the viewer's header: "SMAPI 4.1.10", "Stardew Valley 1.6.15", the platform.
    public var metadata: [LogMetadata] {
        var items: [LogMetadata] = []
        if let smapiVersion { items.append(LogMetadata("SMAPI \(smapiVersion)", symbol: "gearshape.2")) }
        if let gameVersion { items.append(LogMetadata("Stardew Valley \(gameVersion)", symbol: "leaf")) }
        if let platform { items.append(LogMetadata(platform, symbol: "desktopcomputer")) }
        return items
    }
}
