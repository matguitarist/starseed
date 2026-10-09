// SMAPI itself: semantic versions, detecting the installed SMAPI and game
// versions, and comparing them with what mods need.

import Foundation

/// A SMAPI-style semantic version ("1.2", "1.2.3", "1.2.3-beta.1+build").
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces).trimmingPrefix("v")
        guard let match = trimmed.wholeMatch(of: /(\d+)\.(\d+)(?:\.(\d+))?(?:-([0-9A-Za-z.\-]+))?(?:\+[0-9A-Za-z.\-]+)?/),
              let major = Int(match.1), let minor = Int(match.2)
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = match.3.flatMap { Int($0) } ?? 0
        self.prerelease = match.4.map(String.init)
    }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "")
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) {
            return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil), (nil, _): return false  // a release sorts after its prereleases
        case (_, nil): return true
        case let (l?, r?): return l.compare(r, options: .numeric) == .orderedAscending
        }
    }
}

/// The SMAPI install next to the Mods folder (Contents/MacOS for Steam on Mac).
public struct SMAPIInstallation: Sendable, Equatable {
    public let gameFolder: URL
    public let version: SemanticVersion?
    public let gameVersion: SemanticVersion?

    /// Nil when there's no SMAPI next to the Mods folder.
    public static func detect(modsURL: URL, bundledMods: [ModInfo] = []) -> SMAPIInstallation? {
        let folder = modsURL.deletingLastPathComponent()
        let dll = folder.appending(path: "StardewModdingAPI.dll")
        guard FileManager.default.fileExists(atPath: dll.path(percentEncoded: false)) else { return nil }

        // SMAPI's bundled mods always carry SMAPI's own version.
        let bundledVersion = bundledMods
            .first { ["smapi.consolecommands", "smapi.savebackup"].contains($0.uniqueID.lowercased()) }
            .flatMap { SemanticVersion($0.version) }

        return SMAPIInstallation(
            gameFolder: folder,
            version: assemblyVersion(of: dll) ?? bundledVersion,
            gameVersion: gameVersion(in: folder)
        )
    }

    /// Reads [AssemblyInformationalVersion] (e.g. "4.5.2+821167e") from a .NET
    /// assembly. Custom-attribute string blobs are stored as 0x01 0x00, a
    /// length byte, then UTF-8; we take the first semantic version found that
    /// way, preferring one with build metadata (the informational version).
    static func assemblyVersion(of dll: URL) -> SemanticVersion? {
        guard let data = try? Data(contentsOf: dll, options: .mappedIfSafe) else { return nil }
        let bytes = [UInt8](data)
        var candidates: [(text: String, hasBuild: Bool)] = []
        var index = 0
        while index + 3 < bytes.count {
            if bytes[index] == 0x01, bytes[index + 1] == 0x00 {
                let length = Int(bytes[index + 2])
                let start = index + 3
                if (5...64).contains(length), start + length <= bytes.count,
                   let text = String(bytes: bytes[start..<start + length], encoding: .utf8),
                   text.first?.isNumber == true,
                   text.wholeMatch(of: /\d+\.\d+\.\d+(?:-[0-9A-Za-z.\-]+)?(?:\+[0-9A-Za-z.\-]+)?/) != nil {
                    candidates.append((text, text.contains("+")))
                }
            }
            index += 1
        }
        let best = candidates.first(where: \.hasBuild) ?? candidates.first
        return best.flatMap { SemanticVersion($0.text) }
    }

    /// "Stardew Valley/1.6.15.24356" in Stardew Valley.deps.json.
    static func gameVersion(in folder: URL) -> SemanticVersion? {
        guard let text = try? String(contentsOf: folder.appending(path: "Stardew Valley.deps.json"), encoding: .utf8),
              let match = text.firstMatch(of: /"Stardew Valley\/(\d+\.\d+\.\d+)/)
        else { return nil }
        return SemanticVersion(String(match.1))
    }
}
