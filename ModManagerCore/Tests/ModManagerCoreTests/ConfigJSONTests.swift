import Foundation
import Testing
@testable import ModManagerCore

@Suite struct ConfigJSONTests {
    @Test func keepsKeyOrderAndNumbersAsWritten() throws {
        let text = """
        {
          "Zebra": true,
          "Apple": 1.50,
          "Controls": { "ToggleKey": "F5", "Speed": -3 },
          "List": [1, "two", null],
          "Emoji": "caf\\u00e9 \\ud83d\\ude00"
        }
        """
        let (value, hadComments) = try ConfigJSON.parse(Data(text.utf8))
        #expect(!hadComments)
        guard case .object(let members) = value else { Issue.record("not an object"); return }
        #expect(members.map(\.key) == ["Zebra", "Apple", "Controls", "List", "Emoji"])
        #expect(value["Apple"] == .number("1.50"))
        #expect(value["Controls"]?["Speed"] == .number("-3"))
        #expect(value["Emoji"] == .string("café 😀"))

        // Round trip keeps order and number text.
        let reparsed = try ConfigJSON.parse(Data(ConfigJSON.serialize(value).utf8)).value
        #expect(reparsed == value)
        #expect(ConfigJSON.serialize(value).contains(#""Apple": 1.50"#))
    }

    @Test func acceptsWhatSMAPIAccepts() throws {
        let text = "\u{FEFF}// settings\n{ /* block */ \"A\": 1, \"B\": [1, 2,], unquoted: 'single', }"
        let (value, hadComments) = try ConfigJSON.parse(Data(text.utf8))
        #expect(hadComments)
        #expect(value["unquoted"] == .string("single"))
        #expect(value["B"] == .array([.number("1"), .number("2")]))
    }

    @Test func reportsErrorsWithLineNumbers() {
        #expect(throws: JSONParseError.self) { try ConfigJSON.parse(Data("{\n  \"A\": tru\n}".utf8)) }
        do {
            _ = try ConfigJSON.parse(Data("{\n\n  \"A\" 1\n}".utf8))
        } catch let error as JSONParseError {
            #expect(error.line == 3)
        } catch {
            Issue.record("wrong error")
        }
    }

    @Test func escapesWhenSaving() {
        #expect(ConfigJSON.quoted("a\"b\\c\nd") == #""a\"b\\c\nd""#)
        #expect(ConfigJSON.isNumber("-1.5e3"))
        #expect(!ConfigJSON.isNumber("1."))
    }
}

/// Read-only check against a real Mods folder: REAL_MODS=/path/to/Mods
@Suite(.enabled(if: ProcessInfo.processInfo.environment["REAL_MODS"] != nil))
struct RealConfigTests {
    @Test func realConfigsRoundTrip() throws {
        let mods = URL(filePath: ProcessInfo.processInfo.environment["REAL_MODS"]!)
        let configs = (FileManager.default.enumerator(at: mods, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.lastPathComponent == "config.json" }
        #expect(!configs.isEmpty)
        for file in configs {
            let value = try ConfigJSON.parse(Data(contentsOf: file)).value
            let again = try ConfigJSON.parse(Data(ConfigJSON.serialize(value).utf8)).value
            #expect(again == value, "\(file.path)")
            // Same data as Foundation's parser sees (order aside).
            let ours = try JSONSerialization.jsonObject(with: Data(ConfigJSON.serialize(value).utf8)) as? NSDictionary
            let theirs = try JSONSerialization.jsonObject(with: Data(contentsOf: file), options: .json5Allowed) as? NSDictionary
            #expect(ours == theirs, "\(file.lastPathComponent) in \(file.deletingLastPathComponent().lastPathComponent)")
        }
    }
}

/// Read-only: prints how a real Mods folder is grouped. REAL_MODS=/path/to/Mods
@Suite(.enabled(if: ProcessInfo.processInfo.environment["REAL_MODS"] != nil))
struct RealGroupingTests {
    @Test func printGroups() throws {
        let mods = try ModManager(modsURL: URL(filePath: ProcessInfo.processInfo.environment["REAL_MODS"]!)).scan()
        for group in ModGrouping.groups(mods, nexusID: \.nexusModID) {
            print("▸ \(group.name) [\(group.mods.count)]: " + group.mods.map(\.folderName).joined(separator: " · "))
        }
    }
}

/// Read-only: prints missing requirements of a real Mods folder and what SMAPI's database knows about them.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["REAL_MODS"] != nil))
struct RealRequirementTests {
    @Test func printMissing() async throws {
        let mods = try ModManager(modsURL: URL(filePath: ProcessInfo.processInfo.environment["REAL_MODS"]!)).scan()
        let missing = MissingDependency.find(in: mods)
        let records = (try? await UpdateChecker().lookup(uniqueIDs: missing.map(\.uniqueID))) ?? [:]
        for dep in missing {
            let record = records[dep.uniqueID.lowercased()]
            print("✱ \(dep.uniqueID) — name: \(record?.name ?? "?") nexus: \(record?.nexusID.map(String.init) ?? "?") — needed by \(dep.requiredBy.joined(separator: ", "))")
        }
        // Same steps as AppModel.resolveFromNexusRequirements.
        let allRecords = (try? await UpdateChecker().check(mods).records) ?? [:]
        let groups = ModGrouping.groups(mods) { $0.nexusModID ?? allRecords[$0.uniqueID.lowercased()]?.nexusID }
        let client = NexusClient(apiKey: nil, appVersion: "test")
        for dep in missing where records[dep.uniqueID.lowercased()]?.nexusID == nil {
            for name in dep.requiredBy {
                guard let needing = mods.first(where: { $0.displayName == name }),
                      let group = groups.first(where: { $0.mods.contains { $0.id == needing.id } }),
                      let page = group.mods.lazy.compactMap({ $0.nexusModID ?? allRecords[$0.uniqueID.lowercased()]?.nexusID }).first
                else { print("  ? no Nexus page for \(name)"); continue }
                let reqs = try await client.requirements(forMod: page)
                let match = RequirementMatcher.bestMatch(for: dep.uniqueID, among: reqs)
                print("→ \(dep.uniqueID) via #\(page) (\(group.name)): \(match.map { "\($0.name) #\($0.modID!)" } ?? "no match")")
            }
        }
        for mod in mods where mod.uniqueID.lowercased().contains("eastscarp") || mod.uniqueID == "ES.BarberShop" {
            print("• \(mod.relativePath) [\(mod.uniqueID)] enabled=\(mod.isEnabled) status=\(mod.status.rawValue) missing=\(mod.missingDependencies)")
        }
    }
}

/// Read-only: what deleting East Scarp would leave unused. REAL_MODS=/path/to/Mods
@Suite(.enabled(if: ProcessInfo.processInfo.environment["REAL_MODS"] != nil))
struct RealUnusedTests {
    @Test func whatIfEastScarpIsDeleted() throws {
        let mods = try ModManager(modsURL: URL(filePath: ProcessInfo.processInfo.environment["REAL_MODS"]!)).scan()
        for family in ["eastscarp", "ridgeside", "rsv"] {
            let removed = mods.filter { $0.uniqueID.lowercased().contains(family) || $0.uniqueID == "ES.BarberShop" && family == "eastscarp" }
            guard !removed.isEmpty else { continue }
            let remaining = mods.filter { mod in !removed.contains { $0.id == mod.id } }
            let unused = UnusedRequirements.find(removed: removed, remaining: remaining)
            print("◆ delete \(family) (\(removed.count) parts) → suggest: " + (unused.isEmpty ? "nothing" : unused.map { "\($0.mod.displayName) [needed by \($0.neededBy.joined(separator: ", "))]" }.joined(separator: "; ")))
        }
    }
}
