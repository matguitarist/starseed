// Parses SMAPI's console log (SMAPI-latest.txt).
//
// Each entry starts with "[HH:mm:ss LEVEL Source] message"; lines without
// that prefix (stack traces, multi-line messages) continue the previous entry.

import Foundation

public enum LogLevel: String, CaseIterable, Comparable, Sendable {
    case trace = "TRACE"
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case alert = "ALERT"

    private var rank: Int { Self.allCases.firstIndex(of: self)! }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }

    public var title: String {
        switch self {
        case .trace: "Trace"
        case .debug: "Debug"
        case .info: "Info"
        case .warn: "Warning"
        case .error: "Error"
        case .alert: "Alert"
        }
    }
}

public struct LogEntry: Identifiable, Hashable, Sendable {
    public let id: Int          // position in the log
    public let time: String
    public let level: LogLevel
    public let source: String   // "SMAPI", "game", or a mod's name
    public var message: String

    public var isProblem: Bool { level >= .warn }
}

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
        var entries: [LogEntry] = []
        // SMAPI writes CRLF line endings, and Swift treats "\r\n" as one
        // Character, so split on any newline rather than on "\n".
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if let match = line.wholeMatch(of: /\[(\d{2}:\d{2}:\d{2}) (TRACE|DEBUG|INFO|WARN|ERROR|ALERT) +([^\]]+)\] ?(.*)/),
               let level = LogLevel(rawValue: String(match.2)) {
                entries.append(LogEntry(
                    id: entries.count,
                    time: String(match.1),
                    level: level,
                    source: match.3.trimmingCharacters(in: .whitespaces),
                    message: String(match.4)
                ))
            } else if !line.isEmpty, !entries.isEmpty {
                entries[entries.count - 1].message += "\n" + line
            }
        }
        self.entries = entries

        // "SMAPI 4.1.10 with Stardew Valley 1.6.15 build 24356 on macOS Unix 14.5.0"
        let header = entries.lazy.compactMap {
            $0.message.firstMatch(of: /^SMAPI (\S+) with Stardew Valley (\S+)(?: build \d+)? on (.+)$/)
        }.first
        smapiVersion = header.map { String($0.1) }
        gameVersion = header.map { String($0.2) }
        platform = header.map { String($0.3) }
    }

    private init(entries: [LogEntry], smapiVersion: String?, gameVersion: String?, platform: String?) {
        self.entries = entries
        self.smapiVersion = smapiVersion
        self.gameVersion = gameVersion
        self.platform = platform
    }

    /// Identifies one game session: SMAPI starts a new SMAPI-latest.txt on
    /// every launch, so its first line (with its timestamp) changes.
    public var sessionKey: String? {
        entries.first.map { "\($0.time) \($0.message)" }
    }

    /// The log without its first `count` entries, for "Clear": only messages
    /// logged afterwards remain. The session's version info is kept.
    public func droppingFirst(_ count: Int) -> SMAPILog {
        SMAPILog(entries: Array(entries.dropFirst(count)), smapiVersion: smapiVersion, gameVersion: gameVersion, platform: platform)
    }

    public static func load(from url: URL) throws -> SMAPILog {
        let data = try Data(contentsOf: url)
        return SMAPILog(text: String(decoding: data, as: UTF8.self))
    }

    public func count(of level: LogLevel) -> Int {
        entries.lazy.filter { $0.level == level }.count
    }

    /// Warnings and errors grouped by source, worst and most frequent first.
    public var problemsBySource: [(source: String, worst: LogLevel, count: Int)] {
        var groups: [String: (worst: LogLevel, count: Int)] = [:]
        for entry in entries where entry.isProblem {
            let current = groups[entry.source] ?? (entry.level, 0)
            groups[entry.source] = (max(current.worst, entry.level), current.count + 1)
        }
        return groups
            .map { (source: $0.key, worst: $0.value.worst, count: $0.value.count) }
            .sorted { ($0.worst, $0.count) > ($1.worst, $1.count) }
    }
}
