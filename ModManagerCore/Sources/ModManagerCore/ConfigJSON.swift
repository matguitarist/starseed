// An order-preserving JSON reader/writer for mods' config.json files.
// Foundation's JSONSerialization loses key order, which makes edited configs
// hard to compare with a mod's documentation. Like SMAPI (Json.NET), the
// reader accepts a UTF-8 BOM, // and /* */ comments, and trailing commas.

import Foundation

public indirect enum JSONValue: Equatable, Sendable {
    public struct Member: Equatable, Sendable {
        public var key: String
        public var value: JSONValue

        public init(key: String, value: JSONValue) {
            self.key = key
            self.value = value
        }
    }

    case object([Member])
    case array([JSONValue])
    case string(String)
    /// Kept as written ("1.5", "-3", "1e3") so saving doesn't reformat numbers.
    case number(String)
    case bool(Bool)
    case null

    public subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }
}

public struct JSONParseError: LocalizedError, Sendable {
    public let message: String
    public let line: Int
    public var errorDescription: String? { String(localized: "Line \(line): \(message)", bundle: .module) }
}

public enum ConfigJSON {
    /// Parses JSON (with comments/trailing commas). `hadComments` reports
    /// whether saving would drop comments.
    public static func parse(_ data: Data) throws -> (value: JSONValue, hadComments: Bool) {
        var bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        var parser = Parser(bytes: bytes)
        let value = try parser.parseDocument()
        return (value, parser.sawComment)
    }

    /// Pretty-printed with 2-space indentation, like most mods ship it.
    public static func serialize(_ value: JSONValue) -> String {
        var out = ""
        write(value, indent: 0, into: &out)
        return out + "\n"
    }

    private static func write(_ value: JSONValue, indent: Int, into out: inout String) {
        let pad = String(repeating: "  ", count: indent)
        let inner = String(repeating: "  ", count: indent + 1)
        switch value {
        case .object(let members):
            guard !members.isEmpty else { out += "{}"; return }
            out += "{\n"
            for (index, member) in members.enumerated() {
                out += inner + quoted(member.key) + ": "
                write(member.value, indent: indent + 1, into: &out)
                out += index < members.count - 1 ? ",\n" : "\n"
            }
            out += pad + "}"
        case .array(let items):
            guard !items.isEmpty else { out += "[]"; return }
            out += "[\n"
            for (index, item) in items.enumerated() {
                out += inner
                write(item, indent: indent + 1, into: &out)
                out += index < items.count - 1 ? ",\n" : "\n"
            }
            out += pad + "]"
        case .string(let text): out += quoted(text)
        case .number(let text): out += text
        case .bool(let flag): out += flag ? "true" : "false"
        case .null: out += "null"
        }
    }

    static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case let s where s.value < 0x20: out += String(format: "\\u%04x", s.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// Whether `text` is a valid JSON number (for validating edits).
    public static func isNumber(_ text: String) -> Bool {
        text.wholeMatch(of: /-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/) != nil
    }
}

private struct Parser {
    let bytes: [UInt8]
    var index = 0
    var sawComment = false

    init(bytes: [UInt8]) { self.bytes = bytes }

    var line: Int { bytes[..<min(index, bytes.count)].filter { $0 == UInt8(ascii: "\n") }.count + 1 }

    func fail(_ message: String.LocalizationValue) -> JSONParseError {
        JSONParseError(message: String(localized: message, bundle: .module), line: line)
    }

    mutating func parseDocument() throws -> JSONValue {
        let value = try parseValue()
        skipWhitespace()
        guard index == bytes.count else { throw fail("Unexpected text after the end of the file") }
        return value
    }

    mutating func skipWhitespace() {
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                index += 1
            } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "/") {
                sawComment = true
                while index < bytes.count, bytes[index] != 0x0A { index += 1 }
            } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "*") {
                sawComment = true
                index += 2
                while index + 1 < bytes.count, !(bytes[index] == UInt8(ascii: "*") && bytes[index + 1] == UInt8(ascii: "/")) { index += 1 }
                index = min(index + 2, bytes.count)
            } else {
                return
            }
        }
    }

    mutating func parseValue() throws -> JSONValue {
        skipWhitespace()
        guard index < bytes.count else { throw fail("Unexpected end of file") }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""), UInt8(ascii: "'"): return .string(try parseString())
        case UInt8(ascii: "t"): try expect("true"); return .bool(true)
        case UInt8(ascii: "f"): try expect("false"); return .bool(false)
        case UInt8(ascii: "n"): try expect("null"); return .null
        default: return .number(try parseNumber())
        }
    }

    mutating func expect(_ word: String) throws {
        let utf8 = Array(word.utf8)
        guard index + utf8.count <= bytes.count, Array(bytes[index..<index + utf8.count]) == utf8 else {
            throw fail("Expected \(word)")
        }
        index += utf8.count
    }

    mutating func parseObject() throws -> JSONValue {
        index += 1  // {
        var members: [JSONValue.Member] = []
        while true {
            skipWhitespace()
            guard index < bytes.count else { throw fail("Unclosed {") }
            if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
            let key = try parseKey()
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw fail("Expected : after \"\(key)\"") }
            index += 1
            members.append(.init(key: key, value: try parseValue()))
            skipWhitespace()
            guard index < bytes.count else { throw fail("Unclosed {") }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }  // trailing comma allowed
            if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
            throw fail("Expected , or } after \"\(key)\"")
        }
    }

    mutating func parseKey() throws -> String {
        if bytes[index] == UInt8(ascii: "\"") || bytes[index] == UInt8(ascii: "'") { return try parseString() }
        // Unquoted keys (JSON5 / Json.NET leniency).
        let start = index
        while index < bytes.count, (bytes[index] >= 0x30 && bytes[index] <= 0x39) || (bytes[index] | 0x20 >= 0x61 && bytes[index] | 0x20 <= 0x7A) || bytes[index] == UInt8(ascii: "_") || bytes[index] == UInt8(ascii: "$") {
            index += 1
        }
        guard index > start else { throw fail("Expected a key") }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    mutating func parseArray() throws -> JSONValue {
        index += 1  // [
        var items: [JSONValue] = []
        while true {
            skipWhitespace()
            guard index < bytes.count else { throw fail("Unclosed [") }
            if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            items.append(try parseValue())
            skipWhitespace()
            guard index < bytes.count else { throw fail("Unclosed [") }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            throw fail("Expected , or ]")
        }
    }

    mutating func parseString() throws -> String {
        let quote = bytes[index]
        index += 1
        var raw: [UInt8] = []
        while index < bytes.count, bytes[index] != quote {
            if bytes[index] == UInt8(ascii: "\\"), index + 1 < bytes.count {
                index += 1
                switch bytes[index] {
                case UInt8(ascii: "n"): raw.append(0x0A)
                case UInt8(ascii: "t"): raw.append(0x09)
                case UInt8(ascii: "r"): raw.append(0x0D)
                case UInt8(ascii: "b"): raw.append(0x08)
                case UInt8(ascii: "f"): raw.append(0x0C)
                case UInt8(ascii: "u"):
                    guard index + 4 < bytes.count,
                          let code = UInt32(String(decoding: bytes[index + 1...index + 4], as: UTF8.self), radix: 16)
                    else { throw fail("Bad \\u escape") }
                    index += 4
                    var scalarValue = code
                    // Surrogate pair: 😀
                    if (0xD800...0xDBFF).contains(code), index + 6 < bytes.count, bytes[index + 1] == UInt8(ascii: "\\"), bytes[index + 2] == UInt8(ascii: "u"),
                       let low = UInt32(String(decoding: bytes[index + 3...index + 6], as: UTF8.self), radix: 16), (0xDC00...0xDFFF).contains(low) {
                        scalarValue = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        index += 6
                    }
                    raw += Array(String(Unicode.Scalar(scalarValue).map(Character.init) ?? "?").utf8)
                default: raw.append(bytes[index])  // \" \\ \/ \'
                }
            } else {
                raw.append(bytes[index])
            }
            index += 1
        }
        guard index < bytes.count else { throw fail("Unclosed string") }
        index += 1
        return String(decoding: raw, as: UTF8.self)
    }

    mutating func parseNumber() throws -> String {
        let start = index
        while index < bytes.count, "+-0123456789.eE".utf8.contains(bytes[index]) { index += 1 }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        guard ConfigJSON.isNumber(text) || Double(text) != nil else { throw fail("Unexpected value “\(text.isEmpty ? String(UnicodeScalar(bytes[index])) : text)”") }
        return text
    }
}
