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
    /// The mod's config.json, as written (comments included). Absent in
    /// lists made before settings were saved, and for mods without one.
    public var settings: String?

    public var id: String { uniqueID.lowercased() }

    public init(name: String, uniqueID: String, version: String, author: String?, nexusID: Int?, enabled: Bool, settings: String? = nil) {
        self.name = name
        self.uniqueID = uniqueID
        self.version = version
        self.author = author
        self.nexusID = nexusID
        self.enabled = enabled
        self.settings = settings
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
        smapiVersion: String?,
        includeSettings: Bool = true
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
                    enabled: mod.isEnabled,
                    settings: includeSettings ? Self.settings(of: mod) : nil
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

// MARK: Mod settings

extension ModList {
    /// A mod's config.json text, if it has a reasonably sized one.
    static func settings(of mod: ModInfo) -> String? {
        let url = mod.folderURL.appending(path: "config.json")
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= 512 * 1024,
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return text
    }

    /// Installed mods whose settings differ from the list's, with the
    /// settings to write. Only mods the list has settings for count.
    public func settingsChanges(for installed: [ModInfo]) -> [(mod: ModInfo, settings: String)] {
        let byID = Dictionary(mods.compactMap { entry in entry.settings.map { (entry.id, $0) } }, uniquingKeysWith: { first, _ in first })
        return installed.compactMap { mod in
            guard let wanted = byID[mod.uniqueID.lowercased()] else { return nil }
            let current = Self.settings(of: mod)
            return current?.trimmingCharacters(in: .whitespacesAndNewlines) == wanted.trimmingCharacters(in: .whitespacesAndNewlines)
                ? nil : (mod, wanted)
        }
    }

    public var settingsCount: Int { mods.filter { $0.settings != nil }.count }

    /// Writes settings to a mod's config.json, keeping the old file as
    /// config.json.bak. Settings that don't parse are refused.
    public static func apply(settings: String, to mod: ModInfo) throws {
        _ = try ConfigJSON.parse(Data(settings.utf8))
        let url = mod.folderURL.appending(path: "config.json")
        if let previous = try? Data(contentsOf: url) {
            try? previous.write(to: mod.folderURL.appending(path: "config.json.bak"))
        }
        try Data(settings.utf8).write(to: url, options: .atomic)
    }
}
