// Installs or updates SMAPI with its official installer, without its
// Terminal window: downloads the latest release from GitHub and runs
// `SMAPI.Installer --install --no-prompt --game-path <folder>`.

import Foundation
import ArchiveKit
import DownloadKit
import ProcessKit

public struct SMAPIRelease: Sendable, Equatable {
    public let version: SemanticVersion
    public let installerURL: URL
}

public enum SMAPIInstaller {
    public enum Phase: Sendable, Equatable {
        case downloading(Double)
        case installing
    }

    /// The newest SMAPI release on GitHub.
    public static func latestRelease() async throws -> SMAPIRelease {
        let release: GitHubRelease
        do {
            release = try await GitHubRelease.latest(owner: "Pathoschild", repo: "SMAPI", options: FileDownloader.options)
        } catch let error as DownloadError {
            if let status = error.status {
                throw ModManagerError("Couldn't reach SMAPI's releases on GitHub (HTTP \(status)).")
            }
            if case .badResponse = error {
                throw ModManagerError("SMAPI's latest release has no installer for this app to run.")
            }
            throw error
        }
        return try installer(in: release)
    }

    /// Picks the plain installer zip ("SMAPI-4.5.2-installer.zip", not the
    /// "double-zipped" one meant for sites that unzip uploads).
    static func installer(in release: GitHubRelease) throws -> SMAPIRelease {
        guard let version = SemanticVersion(release.tag),
              let asset = release.assets.first(where: { $0.name.wholeMatch(of: /SMAPI-[\d.]+(-[\w.]+)?-installer\.zip/) != nil })
        else { throw ModManagerError("SMAPI's latest release has no installer for this app to run.") }
        return SMAPIRelease(version: version, installerURL: asset.url)
    }

    /// Whether `folder` is the game's folder (Contents/MacOS for Steam).
    public static func isGameFolder(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: "Stardew Valley.dll").path(percentEncoded: false))
    }

    /// SMAPI's installer (like the game) is an Intel app: Apple silicon Macs
    /// need Rosetta. Anyone who has played the game has it.
    public static var needsRosetta: Bool {
        #if arch(arm64)
        return !FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
        #else
        return false
        #endif
    }

    /// Downloads `release` and installs it into `gameFolder`. Replaces an
    /// older SMAPI and re-hooks the game's launcher after a game update.
    public static func install(
        _ release: SMAPIRelease,
        gameFolder: URL,
        progress: @escaping @Sendable (Phase) -> Void
    ) async throws {
        guard isGameFolder(gameFolder) else {
            throw ModManagerError("This doesn't look like the game's folder: \(gameFolder.path(percentEncoded: false))")
        }
        guard !needsRosetta else {
            throw ModManagerError("SMAPI's installer needs Rosetta. Install it by running “softwareupdate --install-rosetta” in Terminal, then try again.")
        }

        progress(.downloading(0))
        let zip = try await FileDownloader.download(release.installerURL) { progress(.downloading($0)) }
        let work = zip.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: work) }

        progress(.installing)
        let extracted = work.appending(path: "installer", directoryHint: .isDirectory)
        do {
            try await Zip.unpack(zip, into: extracted)
        } catch {
            throw ModManagerError(archive: error)
        }
        guard let executable = findInstaller(in: extracted) else {
            throw ModManagerError("The SMAPI download doesn't contain its macOS installer.")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))

        let output = try await run(
            executable.path(percentEncoded: false),
            ["--install", "--no-prompt", "--game-path", gameFolder.path(percentEncoded: false)],
            in: executable.deletingLastPathComponent()
        )
        try checkResult(output)
    }

    /// "SMAPI 4.5.2 installer/internal/macOS/SMAPI.Installer".
    static func findInstaller(in folder: URL) -> URL? {
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in items where url.lastPathComponent == "SMAPI.Installer"
            && url.deletingLastPathComponent().lastPathComponent == "macOS" {
            return url
        }
        return nil
    }

    /// The installer exits normally even when it fails, so read its output.
    static func checkResult(_ output: String) throws {
        if output.contains("SMAPI is installed!") { return }
        // Its errors are printed in red without a prefix: show the last lines.
        let lines = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.allSatisfy { $0 == "-" } }
        let detail = lines.suffix(4).joined(separator: "\n")
        throw ModManagerError(verbatim: detail.isEmpty ? "SMAPI's installer didn't finish." : detail)
    }

    /// Runs a tool and returns its combined output, whatever its exit status.
    /// stdin is /dev/null, so the installer never waits for a key press.
    static func run(_ executable: String, _ arguments: [String], in directory: URL? = nil) async throws -> String {
        try await Shell.run(executable, arguments, options: Shell.Options(directory: directory, stderr: .merged)).text
    }
}

extension SMAPIInstallation {
    /// Whether the game's launcher starts SMAPI. A game update from Steam
    /// replaces it, so the game then starts without mods although SMAPI's
    /// files are still there; installing SMAPI again fixes it.
    public var isLauncherHooked: Bool {
        let launcher = gameFolder.appending(path: "StardewValley")
        guard let handle = try? FileHandle(forReadingFrom: launcher) else { return true }  // unknown layout: don't warn
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        return String(decoding: head, as: UTF8.self).contains("StardewModdingAPI")
    }
}
