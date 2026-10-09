// "My Collections": named snapshots of the installed mods (with versions and
// Nexus numbers) that can be exported as a .json file and imported on
// another computer, then installed from Nexus or applied like a profile.

import Foundation

public struct ModListEntry: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var uniqueID: String
    public var version: String
    public var author: String?
    public var nexusID: Int?
    public var enabled: Bool

    public var id: String { uniqueID.lowercased() }

    public init(name: String, uniqueID: String, version: String, author: String?, nexusID: Int?, enabled: Bool) {
        self.name = name
        self.uniqueID = uniqueID
        self.version = version
        self.author = author
        self.nexusID = nexusID
        self.enabled = enabled
    }
}

public struct ModList: Codable, Hashable, Identifiable, Sendable {
    // Kept from the app's former name so older exports still import.
    public static let formatName = "stardew-mod-manager/mod-list"

    public var format = ModList.formatName
    public var formatVersion = 1
    public var name: String
    public var createdAt: Date
    public var gameVersion: String?
    public var smapiVersion: String?
    public var mods: [ModListEntry]

    public var id: String { name }

    public init(name: String, createdAt: Date = .now, gameVersion: String?, smapiVersion: String?, mods: [ModListEntry]) {
        self.name = name
        self.createdAt = createdAt
        self.gameVersion = gameVersion
        self.smapiVersion = smapiVersion
        self.mods = mods
    }

    /// Snapshot of installed mods. SMAPI's bundled mods are left out (they
    /// come with SMAPI), as are folders without a valid manifest.
    public static func snapshot(
        name: String,
        of mods: [ModInfo],
        nexusID: (ModInfo) -> Int?,
        gameVersion: String?,
        smapiVersion: String?
    ) -> ModList {
        let entries = mods
            .filter { !$0.uniqueID.isEmpty && $0.parseError == nil && !$0.uniqueID.lowercased().hasPrefix("smapi.") }
            .map { mod in
                ModListEntry(
                    name: mod.name,
                    uniqueID: mod.uniqueID,
                    version: mod.version,
                    author: mod.author == "?" ? nil : mod.author,
                    nexusID: nexusID(mod),
                    enabled: mod.isEnabled
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return ModList(name: name, gameVersion: gameVersion, smapiVersion: smapiVersion, mods: entries)
    }

    // MARK: Files

    public static func decode(from data: Data) throws -> ModList {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let list = try decoder.decode(ModList.self, from: data)
        guard list.format == formatName else {
            throw ModManagerError("This file isn't a Starseed mod list.")
        }
        return list
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// A file name for exporting: "My Farm Mods.json".
    public var suggestedFileName: String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".json"
    }
}

/// How one entry of a list compares to the Mods folder.
public enum ModListEntryState: Equatable, Sendable {
    case installed
    case disabled
    case olderInstalled(String)  // installed version is older than the list's
    case newerInstalled(String)
    case missing

    public static func of(_ entry: ModListEntry, in mods: [ModInfo]) -> ModListEntryState {
        guard let installed = mods.first(where: { $0.uniqueID.caseInsensitiveCompare(entry.uniqueID) == .orderedSame }) else {
            return .missing
        }
        if let wanted = SemanticVersion(entry.version), let have = SemanticVersion(installed.version), have != wanted {
            return have < wanted ? .olderInstalled(installed.version) : .newerInstalled(installed.version)
        }
        return installed.isEnabled ? .installed : .disabled
    }
}

/// Saved mod lists in Application Support, one .json file per list.
public struct ModListStore: Sendable {
    public let directory: URL

    public static let defaultDirectory = ConfigStore.defaultDirectory.appending(path: "Collections", directoryHint: .isDirectory)

    public init(directory: URL = ModListStore.defaultDirectory) {
        self.directory = directory
    }

    public func list() -> [ModList] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { try? ModList.decode(from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Saves (or replaces) a list, keyed by its name.
    public func save(_ list: ModList) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try list.encoded().write(to: directory.appending(path: list.suggestedFileName), options: .atomic)
    }

    public func delete(_ list: ModList) throws {
        let file = directory.appending(path: list.suggestedFileName)
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            try FileManager.default.trashItem(at: file, resultingItemURL: nil)
        }
    }
}
