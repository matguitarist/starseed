import Foundation
import Testing
@testable import ModManagerCore

@Suite struct ChangelogTests {
    let all = [
        ChangelogEntry(version: "1.0.0", lines: ["First release"]),
        ChangelogEntry(version: "1.1.0", lines: ["Added fish"]),
        ChangelogEntry(version: "1.2.0", lines: ["Fixed crash"]),
        ChangelogEntry(version: "1.3.0-beta", lines: ["Beta"]),
        ChangelogEntry(version: "2.0", lines: ["Big update"]),
    ]

    @Test func picksVersionsBetweenInstalledAndLatest() {
        let picked = Changelog.entries(all, after: "1.0.0", upTo: "1.2.0")
        #expect(picked.map(\.version) == ["1.2.0", "1.1.0"])
    }

    @Test func includesShortVersionsAndPrereleasesInRange() {
        let picked = Changelog.entries(all, after: "1.2.0", upTo: "2.0.0")
        #expect(picked.map(\.version) == ["2.0", "1.3.0-beta"])
    }

    @Test func unparsableVersionMatchesLatestOnly() {
        let odd = [ChangelogEntry(version: "Final", lines: ["x"]), ChangelogEntry(version: "Other", lines: ["y"])]
        #expect(Changelog.entries(odd, after: "1.0", upTo: "Final").map(\.version) == ["Final"])
    }

    @Test func mergesDuplicateFileChangelogs() {
        let merged = Changelog.merge([
            ("1.15.11", ["- Fixed fish", "Added tags"]),
            ("v1.15.11", ["Fixed fish"]),
            ("1.15.10", []),
        ])
        #expect(merged == [ChangelogEntry(version: "1.15.11", lines: ["Fixed fish", "Added tags"])])
    }

    @Test func cleansHTML() {
        #expect(Changelog.clean("<b>Fixed</b> crash &amp; freeze<br />") == "Fixed crash & freeze")
        #expect(Changelog.clean("* Added Leah's &quot;art&quot;") == "Added Leah's \"art\"")
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["LIVE_API_TESTS"] == "1"))
struct LiveChangelogTests {
    @Test func readsFileChangelogs() async throws {
        // Stardew Valley Expanded writes its changelog on each file.
        let client = NexusClient(apiKey: nil, appVersion: "test")
        let entries = try await client.changelog(forMod: 3753)
        let recent = Changelog.entries(entries, after: "1.15.9", upTo: "1.15.11")
        #expect(recent.first?.version == "1.15.11")
        #expect(recent.first?.lines.isEmpty == false)
        print(recent.map { "\($0.version): \($0.lines.count) lines" })
    }
}
