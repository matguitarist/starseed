// Installs or updates SMAPI with its official installer, without its
// Terminal window: downloads the latest release from GitHub and runs
// `SMAPI.Installer --install --no-prompt --game-path <folder>`.

import Foundation

public struct SMAPIRelease: Sendable, Equatable {
    public let version: SemanticVersion
    public let installerURL: URL
}

public enum SMAPIInstaller {
    public enum Phase: Sendable, Equatable {
        case downloading(Double)
        case installing
    }

    static let latestReleaseURL = URL(string: "https://api.github.com/repos/Pathoschild/SMAPI/releases/latest")!

    /// The newest SMAPI release on GitHub.
    public static func latestRelease(session: URLSession = .shared) async throws -> SMAPIRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ModManagerError("Couldn't reach SMAPI's releases on GitHub (HTTP \(http.statusCode)).")
        }
        return try parseRelease(data)
    }

    /// Picks the plain installer zip ("SMAPI-4.5.2-installer.zip", not the
    /// "double-zipped" one meant for sites that unzip uploads).
    static func parseRelease(_ data: Data) throws -> SMAPIRelease {
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: String
            }
            let tag_name: String
            let assets: [Asset]
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let version = SemanticVersion(release.tag_name),
              let asset = release.assets.first(where: { $0.name.wholeMatch(of: /SMAPI-[\d.]+(-[\w.]+)?-installer\.zip/) != nil }),
              let url = URL(string: asset.browser_download_url)
        else { throw ModManagerError("SMAPI's latest release has no installer for this app to run.") }
        return SMAPIRelease(version: version, installerURL: url)
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
        _ = try await run("/usr/bin/ditto", ["-x", "-k", zip.path(percentEncoded: false), extracted.path(percentEncoded: false)])
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
    static func run(_ executable: String, _ arguments: [String], in directory: URL? = nil) async throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        process.standardInput = FileHandle.nullDevice  // never wait for a key press
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let handle = output.fileHandleForReading
            let reader = Task.detached { handle.readDataToEndOfFile() }
            process.terminationHandler = { _ in
                Task { continuation.resume(returning: String(decoding: await reader.value, as: UTF8.self)) }
            }
            do {
                try process.run()
            } catch {
                reader.cancel()
                continuation.resume(throwing: error)
            }
        }
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
