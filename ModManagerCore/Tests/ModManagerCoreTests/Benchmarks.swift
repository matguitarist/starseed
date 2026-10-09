import Foundation
import Testing
@testable import ModManagerCore

/// Timing of the hot paths on a big setup. Run with BENCH=1 (release: swift test -c release).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BENCH"] == "1"), .serialized)
struct Benchmarks {
    static func time(_ label: String, repeat count: Int = 1, _ body: () throws -> Void) rethrows {
        let start = ContinuousClock.now
        for _ in 0..<count { try body() }
        let each = (ContinuousClock.now - start) / count
        print("⏱ \(label): \(each.formatted(.units(allowed: [.milliseconds, .microseconds], width: .narrow)))")
    }

    static func bigModsFolder(_ tmp: TempDir) throws -> URL {
        let mods = tmp.url.appending(path: "Mods", directoryHint: .isDirectory)
        for i in 0..<300 {
            let deps = i % 3 == 0 ? #", "Dependencies": [{"UniqueID": "author.mod\#(i + 1)"}, {"UniqueID": "missing.dep\#(i % 7)", "IsRequired": \#(i % 2 == 0)}]"# : ""
            let pack = i % 5 == 0 ? #", "ContentPackFor": {"UniqueID": "Pathoschild.ContentPatcher"}"# : ""
            let folder = i % 10 == 0 ? "[CP] Mod \(i / 10)" : (i % 10 == 1 ? "Mod \(i / 10) Code" : "Mod\(i)")
            try tmp.makeMod(folder, manifest: manifest("author.mod\(i)", name: "Mod \(i)", version: "1.\(i % 9).0", extra: #", "UpdateKeys": ["Nexus:\#(1000 + i)"]"# + deps + pack), in: i % 4 == 0 ? mods.appending(path: "Group\(i % 8)") : mods)
        }
        return mods
    }

    static func bigLog(lines: Int) -> String {
        var text = "[10:00:00 INFO  SMAPI] SMAPI 4.5.2 with Stardew Valley 1.6.15 build 24356 on macOS Unix 27.0.1\r\n"
        let levels = ["TRACE", "DEBUG", "INFO ", "WARN ", "ERROR"]
        for i in 0..<lines {
            let level = levels[i % 5]
            text += "[10:\(String(format: "%02d", (i / 60) % 60)):\(String(format: "%02d", i % 60)) \(level) Mod \(i % 40)] Message number \(i) with some text in it\r\n"
            if i % 50 == 0 { text += "   at Some.Stack.Trace.Line(\(i))\r\n" }
        }
        return text
    }

    @Test func modScanAndDerivedData() throws {
        let tmp = try TempDir()
        let mods = try Self.bigModsFolder(tmp)
        let manager = ModManager(modsURL: mods)
        var scanned: [ModInfo] = []
        try Self.time("scan 300 mods", repeat: 5) { scanned = try manager.scan() }
        #expect(scanned.count == 300)
        Self.time("group 300 mods", repeat: 20) { _ = ModGrouping.groups(scanned, nexusID: \.nexusModID) }
        Self.time("missing dependencies", repeat: 20) { _ = MissingDependency.find(in: scanned) }
        Self.time("duplicate groups", repeat: 20) { _ = ModManager.duplicateGroups(in: scanned) }
    }

    @Test func logParsingAndAnalysis() {
        let text = Self.bigLog(lines: 50_000)
        var log = SMAPILog(text: "")
        Self.time("parse 50k-line log") { log = SMAPILog(text: text) }
        #expect(log.entries.count == 50_001)
        Self.time("count(of:) × 6 levels") { for level in LogLevel.allCases { _ = log.count(of: level) } }
        Self.time("problemsBySource") { _ = log.problemsBySource }
        Self.time("insights") { _ = log.insights }
        Self.time("unknownLocations") { _ = log.unknownLocations }
    }
}
