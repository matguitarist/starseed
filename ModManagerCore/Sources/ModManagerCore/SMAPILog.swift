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
        entries.reserveCapacity(text.utf8.count / 80)
        // Hand-written line scanner: a Regex per line takes seconds on a
        // 50,000-line log. Splitting on bytes also handles SMAPI's CRLF line
        // endings (Swift treats "\r\n" as one Character).
        let bytes = Array(text.utf8)
        var lineStart = 0
        var index = 0
        while index <= bytes.count {
            if index == bytes.count || bytes[index] == 0x0A {
                var lineEnd = index
                if lineEnd > lineStart, bytes[lineEnd - 1] == 0x0D { lineEnd -= 1 }
                let line = bytes[lineStart..<lineEnd]
                if let entry = Self.parseEntry(line, id: entries.count) {
                    entries.append(entry)
                } else if !line.isEmpty, !entries.isEmpty {
                    entries[entries.count - 1].message += "\n" + String(decoding: line, as: UTF8.self)
                }
                lineStart = index + 1
            }
            index += 1
        }
        self.entries = entries

        // "SMAPI 4.1.10 with Stardew Valley 1.6.15 build 24356 on macOS Unix 14.5.0"
        let header = entries.lazy.filter { $0.message.hasPrefix("SMAPI ") }.compactMap {
            $0.message.firstMatch(of: /^SMAPI (\S+) with Stardew Valley (\S+)(?: build \d+)? on (.+)$/)
        }.first
        smapiVersion = header.map { String($0.1) }
        gameVersion = header.map { String($0.2) }
        platform = header.map { String($0.3) }
    }

    /// "[HH:MM:SS LEVEL Source] message", or nil for continuation lines.
    private static func parseEntry(_ line: ArraySlice<UInt8>, id: Int) -> LogEntry? {
        let start = line.startIndex
        // "[" + "HH:MM:SS" + " "
        guard line.count >= 16, line[start] == UInt8(ascii: "["), line[start + 9] == UInt8(ascii: " "),
              line[start + 3] == UInt8(ascii: ":"), line[start + 6] == UInt8(ascii: ":")
        else { return nil }
        for offset in [1, 2, 4, 5, 7, 8] where !(0x30...0x39).contains(line[start + offset]) { return nil }

        // Level: 4-5 capitals, then spaces.
        var cursor = start + 10
        let levelStart = cursor
        while cursor < line.endIndex, (0x41...0x5A).contains(line[cursor]) { cursor += 1 }
        guard let level = LogLevel(rawValue: String(decoding: line[levelStart..<cursor], as: UTF8.self)),
              cursor < line.endIndex, line[cursor] == UInt8(ascii: " ")
        else { return nil }
        while cursor < line.endIndex, line[cursor] == UInt8(ascii: " ") { cursor += 1 }

        // Source up to "]".
        let sourceStart = cursor
        while cursor < line.endIndex, line[cursor] != UInt8(ascii: "]") { cursor += 1 }
        guard cursor < line.endIndex, cursor > sourceStart else { return nil }
        let source = String(decoding: line[sourceStart..<cursor], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        cursor += 1
        if cursor < line.endIndex, line[cursor] == UInt8(ascii: " ") { cursor += 1 }

        return LogEntry(
            id: id,
            time: String(decoding: line[(start + 1)..<(start + 9)], as: UTF8.self),
            level: level,
            source: source,
            message: String(decoding: line[cursor...], as: UTF8.self)
        )
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
