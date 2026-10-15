// Plain data types for a SMAPI mod, plus turning a mod folder's manifest.json
// into a ModInfo.
//
// SMAPI's manifest schema reference:
// https://stardewvalleywiki.com/Modding:Modder_Guide/APIs/Manifest

import Foundation

public struct Dependency: Hashable, Sendable {
    public var uniqueID: String
    public var isRequired: Bool

    public init(uniqueID: String, isRequired: Bool = true) {
        self.uniqueID = uniqueID
        self.isRequired = isRequired
    }
}

public enum ModStatus: String, Sendable, CaseIterable {
    case enabled = "Enabled"
    case disabled = "Disabled"
    case missingDependency = "Missing dependency"
    case needsNewerSMAPI = "Needs newer SMAPI"
    case duplicate = "Duplicate"
    case missingManifest = "Missing manifest"
    case manifestError = "Manifest error"
}

public struct ModInfo: Identifiable, Hashable, Sendable {
    public var folderURL: URL                 // absolute path to the mod's folder right now
    public var name: String
    public var version = "?"
    public var author = "?"
    public var description = ""
    public var uniqueID = ""
    public var contentPackFor: String?
    public var dependencies: [Dependency] = []
    public var updateKeys: [String] = []
    public var hasManifest = true
    public var parseError: String?
    public var missingDependencies: [String] = []  // filled in by ModManager.scan()
    public var minimumApiVersion: String?          // minimum SMAPI version from the manifest
    public var needsNewerSMAPI = false             // set by the app once SMAPI's version is known
    /// Folders between Mods/ and this mod's folder ("Expansions" for
    /// Mods/Expansions/SVE). SMAPI searches folders without a manifest.
    public var containerPath: [String] = []
    /// Another enabled folder has the same UniqueID; SMAPI skips both.
    public var isDuplicate = false

    public init(folderURL: URL) {
        self.folderURL = folderURL
        self.name = String(folderURL.lastPathComponent.drop { $0 == "." })
    }

    /// Path relative to Mods/ ("Expansions/SVE"), unique, so it doubles as the ID.
    public var id: String { relativePath }

    public var relativePath: String { (containerPath + [folderName]).joined(separator: "/") }

    /// Current folder name, e.g. ".CJBCheats" if disabled.
    public var folderName: String { folderURL.lastPathComponent }

    /// Folder name without SMAPI's leading-dot "disabled" marker.
    public var bareFolderName: String { String(folderName.drop { $0 == "." }) }

    /// SMAPI skips any folder whose name starts with a dot, including the
    /// folders it's inside.
    public var isEnabled: Bool { !folderName.hasPrefix(".") && !isDisabledByContainer }

    /// Inside a dot-prefixed (disabled) folder.
    public var isDisabledByContainer: Bool { containerPath.contains { $0.hasPrefix(".") } }

    public var displayName: String {
        hasManifest ? name : "\(bareFolderName) (no manifest.json)"
    }

    /// UpdateKeys often look like "Nexus:2400" or "Nexus:2400@1.2.0".
    public var nexusModID: Int? {
        for key in updateKeys {
            // "Nexus:2400@1.2.0" -> 2400 (plain parsing: called very often).
            let parts = key.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "nexus" else { continue }
            let digits = parts[1].drop { $0 == " " }.prefix { $0.isASCII && $0.isNumber }
            if let id = Int(digits) { return id }
        }
        return nil
    }

    /// Direct link to the mod's Nexus page, if its manifest names one.
    public var nexusURL: URL? {
        nexusModID.map(NexusClient.modPageURL)
    }

    public var status: ModStatus {
        if !hasManifest { return .missingManifest }
        if parseError != nil { return .manifestError }
        if isDuplicate { return .duplicate }
        if !missingDependencies.isEmpty { return .missingDependency }
        if needsNewerSMAPI && isEnabled { return .needsNewerSMAPI }
        return isEnabled ? .enabled : .disabled
    }
}

public enum ManifestParser {
    /// Build a ModInfo from a mod's folder, reading manifest.json if present.
    public static func parse(modFolder: URL) -> ModInfo {
        var mod = ModInfo(folderURL: modFolder)
        let manifestURL = modFolder.appending(path: "manifest.json", directoryHint: .notDirectory)

        guard FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            mod.hasManifest = false
            return mod
        }

        let json: [String: Any]
        do {
            json = try readJSONObject(at: manifestURL)
        } catch {
            let detail = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
            mod.parseError = "Invalid JSON: \(detail ?? error.localizedDescription)"
            return mod
        }

        // SMAPI (via Json.NET) matches manifest keys case-insensitively, so we do too.
        let manifest = CaseInsensitiveJSON(json)
        mod.name = manifest.string("Name") ?? mod.name
        mod.version = versionString(manifest["Version"]) ?? "?"
        mod.author = manifest.string("Author") ?? "?"
        mod.description = manifest.string("Description") ?? ""
        mod.uniqueID = manifest.string("UniqueID") ?? ""
        mod.contentPackFor = manifest.object("ContentPackFor")?.string("UniqueID")
        mod.updateKeys = (manifest["UpdateKeys"] as? [Any])?.compactMap { $0 as? String } ?? []
        mod.minimumApiVersion = manifest.string("MinimumApiVersion")
        mod.dependencies = (manifest["Dependencies"] as? [Any] ?? []).compactMap { entry in
            guard let dict = entry as? [String: Any] else { return nil }
            let dep = CaseInsensitiveJSON(dict)
            guard let id = dep.string("UniqueID"), !id.isEmpty else { return nil }
            return Dependency(uniqueID: id, isRequired: dep["IsRequired"] as? Bool ?? true)
        }
        return mod
    }

    /// manifest.json files in the wild are sometimes saved with a UTF-8 BOM,
    /// contain // or /* */ comments, or have trailing commas. SMAPI tolerates
    /// all of these; JSON5 mode plus BOM stripping covers them.
    static func readJSONObject(at url: URL) throws -> [String: Any] {
        var data = try Data(contentsOf: url)
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            data.removeFirst(3)
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed])
        guard let dict = object as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt, userInfo: [
                NSDebugDescriptionErrorKey: "manifest.json is not a JSON object",
            ])
        }
        return dict
    }

    /// Versions are usually "1.2.3", but very old manifests use
    /// {"MajorVersion": 1, "MinorVersion": 2, "PatchVersion": 3}.
    private static func versionString(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let dict as [String: Any]:
            let parts = CaseInsensitiveJSON(dict)
            let numbers = ["MajorVersion", "MinorVersion", "PatchVersion"].map {
                (parts[$0] as? NSNumber)?.stringValue ?? "0"
            }
            return numbers.joined(separator: ".")
        default:
            return nil
        }
    }
}

/// Read-only view over a JSON object with case-insensitive key lookup.
private struct CaseInsensitiveJSON {
    let storage: [String: Any]

    init(_ storage: [String: Any]) { self.storage = storage }

    subscript(key: String) -> Any? {
        storage[key] ?? storage.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    func string(_ key: String) -> String? { self[key] as? String }

    func object(_ key: String) -> CaseInsensitiveJSON? {
        (self[key] as? [String: Any]).map(CaseInsensitiveJSON.init)
    }
}

extension ModInfo {
    /// Console Commands or Save Backup: optional mods SMAPI installs with
    /// itself. Other mods don't need them.
    public var isBundledWithSMAPI: Bool {
        ["smapi.consolecommands", "smapi.savebackup"].contains(uniqueID.lowercased())
    }
}
