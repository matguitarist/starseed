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
