// Persistent app settings (where your Stardew "Mods" folder lives) and
// profiles. Settings live in:
//
//     ~/Library/Application Support/StardewModManager/
//
// The file formats match the original Python version, so existing
// config.json / profiles.json files keep working.

import Foundation

public enum AppConstants {
    /// Stardew Valley's Steam AppID, used for the launch button.
    public static let steamAppID = "413150"

    /// Default Steam install location for Stardew Valley on macOS. Matches
    /// SMAPI's own "Mods go here: ..." log line, so it's a safe first guess.
    public static let defaultSteamModsURL = URL.homeDirectory.appending(
        path: "Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS/Mods",
        directoryHint: .isDirectory
    )
}

public struct ConfigStore: Sendable {
    public let directory: URL

    public static let defaultDirectory = URL.applicationSupportDirectory
        .appending(path: "StardewModManager", directoryHint: .isDirectory)

    public init(directory: URL = ConfigStore.defaultDirectory) {
        self.directory = directory
    }

    private var configURL: URL { directory.appending(path: "config.json") }
    private var profilesURL: URL { directory.appending(path: "profiles.json") }
    private var saveLinksURL: URL { directory.appending(path: "save-links.json") }

    // MARK: Mods folder

    /// The configured Mods folder, or nil if never set.
    public func modsURL() -> URL? {
        guard let raw = loadConfig()["mods_path"] as? String, !raw.isEmpty else { return nil }
        return URL(filePath: raw, directoryHint: .isDirectory)
    }

    public func setModsURL(_ url: URL) throws {
        var config = loadConfig()
        config["mods_path"] = (url.path(percentEncoded: false) as NSString).standardizingPath  // no trailing slash
        let data = try JSONSerialization.data(
            withJSONObject: config,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try write(data, to: configURL)
    }

    /// Loads the whole config as a loose dictionary so unknown keys survive a save.
    private func loadConfig() -> [String: Any] {
        guard let data = try? Data(contentsOf: configURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }  // missing or garbled -> defaults
        return dict
    }

    // MARK: Profiles

    /// Profiles map a profile name -> unique IDs that should be ENABLED when
    /// that profile is applied.
    public func loadProfiles() -> [String: [String]] {
        guard let data = try? Data(contentsOf: profilesURL),
              let profiles = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return profiles
    }

    public func saveProfiles(_ profiles: [String: [String]]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(try encoder.encode(profiles), to: profilesURL)
    }

    // MARK: Save links

    /// Which profile or collection each save uses, keyed by save folder name.
    public func loadSaveLinks() -> [String: SaveModSet] {
        guard let data = try? Data(contentsOf: saveLinksURL),
              let links = try? JSONDecoder().decode([String: SaveModSet].self, from: data)
        else { return [:] }
        return links
    }

    public func saveSaveLinks(_ links: [String: SaveModSet]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(try encoder.encode(links), to: saveLinksURL)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// The mods a save is played with: a profile or a My Collections list.
public struct SaveModSet: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case profile, collection
    }

    public var kind: Kind
    public var name: String

    public init(kind: Kind, name: String) {
        self.kind = kind
        self.name = name
    }
}
