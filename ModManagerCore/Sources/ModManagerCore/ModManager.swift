// All filesystem operations on the Mods folder live here, kept separate from
// the SwiftUI code so the logic can be tested on its own.
//
// Enable/disable convention: SMAPI skips any folder in Mods whose name starts
// with a dot. We toggle that dot to enable/disable a mod without ever moving
// files out of the Mods folder.

import Foundation

/// Expected, user-facing problems (bad zip, missing folder, name clash, etc).
public struct ModManagerError: LocalizedError, Sendable {
    public let message: String
    /// A file worth showing in Finder alongside the message (e.g. the SMAPI installer).
    public let revealURL: URL?

    public init(_ message: String, revealURL: URL? = nil) {
        self.message = message
        self.revealURL = revealURL
    }

    public var errorDescription: String? { message }
}

public struct InstallResult: Sendable {
    public var installed: [String] = []   // mod names installed/updated
    public var skipped: [String] = []     // mod names the user chose not to overwrite
    public var errors: [String] = []      // human-readable error messages

    public init() {}

    public var isEmpty: Bool { installed.isEmpty && skipped.isEmpty && errors.isEmpty }

    public mutating func merge(_ other: InstallResult) {
        installed += other.installed
        skipped += other.skipped
        errors += other.errors
    }
}

/// A zip that has been extracted to a temp folder and inspected, but not yet
/// copied into Mods. Lets the UI ask about name collisions before committing.
public struct PreparedInstall: Sendable {
    public struct Mod: Sendable {
        public let name: String    // destination folder name in Mods
        let source: URL
        /// The installed copy this replaces (matched by UniqueID, so it's
        /// found even inside a subfolder), if any.
        let existing: URL?
    }

    public let archiveName: String
    public let mods: [Mod]
    public let conflicts: [String]  // names already present (enabled or disabled)
    let workDirectory: URL

    /// Remove the extracted temp files. Safe to call more than once.
    public func discard() {
        try? FileManager.default.removeItem(at: workDirectory)
    }
}

public struct ModManager: Sendable {
    public let modsURL: URL
    /// How deleted/replaced mod folders are disposed of. Moves to the Trash by
    /// default; tests swap in a plain delete.
    let recycle: @Sendable (URL) throws -> Void
    /// Keeps replaced versions for rollback (nil: they go to `recycle`).
    let archive: ModArchive?

    public init(
        modsURL: URL,
        archive: ModArchive? = nil,
        recycle: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.modsURL = modsURL
        self.archive = archive
        self.recycle = recycle
    }

    // MARK: Scanning

    /// Finds every mod in Mods/ the way SMAPI does: a folder with a
    /// manifest.json is a mod; a folder without one is searched for mods
    /// (e.g. Mods/Expansions/SVE). Top-level folders with no mod anywhere
    /// inside are listed as "missing manifest".
    public func scan() throws -> [ModInfo] {
        guard Self.isDirectory(modsURL) else {
            throw ModManagerError("Mods folder does not exist:\n\(modsURL.path(percentEncoded: false))")
        }
        var mods: [ModInfo] = []
        try collect(in: modsURL, containerPath: [], into: &mods)
        Self.markDuplicates(&mods)
        Self.markMissingDependencies(&mods)
        return mods
    }

    private static let maxNesting = 4

    private func collect(in folder: URL, containerPath: [String], into mods: inout [ModInfo]) throws {
        // No .skipsHiddenFiles: disabled mods are dot-folders and must be listed.
        let entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter(Self.isDirectory)
            .filter { $0.lastPathComponent != "__MACOSX" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for entry in entries {
            let hasManifest = FileManager.default.fileExists(atPath: entry.appending(path: "manifest.json").path(percentEncoded: false))
            if hasManifest {
                var mod = ManifestParser.parse(modFolder: entry)
                mod.containerPath = containerPath
                mods.append(mod)
            } else if containerPath.count < Self.maxNesting, Self.containsMod(entry, depth: Self.maxNesting - containerPath.count) {
                try collect(in: entry, containerPath: containerPath + [entry.lastPathComponent], into: &mods)
            } else if containerPath.isEmpty {
                mods.append(ManifestParser.parse(modFolder: entry))  // shows as "missing manifest"
            }
        }
    }

    private static func containsMod(_ folder: URL, depth: Int) -> Bool {
        guard depth > 0, let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return false }
        return children.filter(isDirectory).contains { child in
            FileManager.default.fileExists(atPath: child.appending(path: "manifest.json").path(percentEncoded: false))
                || containsMod(child, depth: depth - 1)
        }
    }

    /// Enabled folders sharing a UniqueID: SMAPI refuses to load any of them.
    static func markDuplicates(_ mods: inout [ModInfo]) {
        var counts: [String: Int] = [:]
        for mod in mods where mod.isEnabled && !mod.uniqueID.isEmpty {
            counts[mod.uniqueID.lowercased(), default: 0] += 1
        }
        for index in mods.indices {
            let id = mods[index].uniqueID.lowercased()
            mods[index].isDuplicate = mods[index].isEnabled && !id.isEmpty && counts[id, default: 0] > 1
        }
    }

    /// Groups of enabled duplicates (2+ folders with one UniqueID each).
    public static func duplicateGroups(in mods: [ModInfo]) -> [[ModInfo]] {
        Dictionary(grouping: mods.filter(\.isDuplicate)) { $0.uniqueID.lowercased() }
            .values
            .map { $0.sorted { $0.relativePath < $1.relativePath } }
            .sorted { $0[0].displayName < $1[0].displayName }
    }

    /// Which copy to keep: the highest version, then the most recently modified.
    public static func preferredCopy(among copies: [ModInfo]) -> ModInfo? {
        copies.max { a, b in
            let va = SemanticVersion(a.version), vb = SemanticVersion(b.version)
            if let va, let vb, va != vb { return va < vb }
            let da = (try? a.folderURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.folderURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
    }

    /// Flag any required dependency (including the framework a content pack is
    /// for) that isn't present & enabled. Disabled mods aren't flagged, since
    /// SMAPI won't load them anyway.
    static func markMissingDependencies(_ mods: inout [ModInfo]) {
        let enabledIDs = Set(mods.filter { $0.isEnabled && !$0.uniqueID.isEmpty }.map { $0.uniqueID.lowercased() })
        for index in mods.indices {
            guard mods[index].isEnabled else {
                mods[index].missingDependencies = []
                continue
            }
            var required = mods[index].dependencies.filter(\.isRequired).map(\.uniqueID)
            if let framework = mods[index].contentPackFor {
                required.insert(framework, at: 0)
            }
            mods[index].missingDependencies = required.filter { !enabledIDs.contains($0.lowercased()) }
        }
    }

    // MARK: Enable / disable / delete

    /// Rename the mod's folder to add/remove the leading dot. Enabling a mod
    /// inside a disabled folder (".Expansions/SVE") also enables that folder,
    /// since SMAPI skips everything in it. Returns the mod's new URL.
    @discardableResult
    public func setEnabled(_ mod: ModInfo, _ enabled: Bool) throws -> URL {
        var parent = mod.folderURL.deletingLastPathComponent()
        if enabled && mod.isDisabledByContainer {
            parent = modsURL
            for component in mod.containerPath {
                let current = parent.appending(path: component, directoryHint: .isDirectory)
                if component.hasPrefix(".") {
                    let bare = String(component.drop { $0 == "." })
                    parent = parent.appending(path: bare, directoryHint: .isDirectory)
                    try rename(current, to: parent)
                } else {
                    parent = current
                }
            }
        }
        let current = parent.appending(path: mod.folderName, directoryHint: .isDirectory)
        let newName = enabled ? mod.bareFolderName : "." + mod.bareFolderName
        guard newName != mod.folderName else { return current }  // already in that state
        let newURL = parent.appending(path: newName, directoryHint: .isDirectory)
        try rename(current, to: newURL)
        return newURL
    }

    private func rename(_ url: URL, to newURL: URL) throws {
        if FileManager.default.fileExists(atPath: newURL.path(percentEncoded: false)) {
            throw ModManagerError("Can't rename — a folder named '\(newURL.lastPathComponent)' already exists.")
        }
        try FileManager.default.moveItem(at: url, to: newURL)
    }

    /// "Expansions/SVE" for a URL inside Mods/; matches `ModInfo.id`.
    public func relativeID(for url: URL) -> String {
        let base = modsURL.standardizedFileURL.pathComponents
        let parts = url.standardizedFileURL.pathComponents
        return parts.starts(with: base) ? parts.dropFirst(base.count).joined(separator: "/") : url.lastPathComponent
    }

    /// Moves the mod's folder to the Trash so it can be restored from Finder.
    public func moveToTrash(_ mod: ModInfo) throws {
        try recycle(mod.folderURL)
    }

    // MARK: Installing from a downloaded .zip

    /// Archive formats we can extract: zip via ditto, the rest via bsdtar (libarchive).
    public static let archiveExtensions: Set<String> = ["zip", "7z", "rar", "tar", "gz", "tgz"]

    /// Extract an archive and find the mod folder(s) inside it. Runs off the main thread.
    ///
    /// SMAPI's own download is an installer, not a mod: it's unpacked into
    /// `installerDestination` (Downloads) and reported via `revealURL`.
    public func prepareInstall(archive: URL, installerDestination: URL = .downloadsDirectory) async throws -> PreparedInstall {
        let fm = FileManager.default
        let archiveName = archive.lastPathComponent
        let work = fm.temporaryDirectory.appending(path: "sdv_mod_\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        do {
            try await Self.extract(archive, to: work)
        } catch {
            try? fm.removeItem(at: work)
            throw ModManagerError("\(archiveName) is not a valid archive (or is damaged).")
        }

        let installed = (try? scan()) ?? []
        let mods = Self.findModRoots(in: work).map { root in
            // A zip with manifest.json at its top level has no wrapper folder;
            // name the mod after the zip instead of our temp directory.
            let name = root.lastPathComponent == work.lastPathComponent
                ? archive.deletingPathExtension().lastPathComponent
                : root.lastPathComponent
            // Match an installed copy by UniqueID first (it may live in a
            // subfolder or under another folder name), then by folder name.
            let uniqueID = ManifestParser.parse(modFolder: root).uniqueID
            let byID = uniqueID.isEmpty ? nil : installed.first { $0.uniqueID.caseInsensitiveCompare(uniqueID) == .orderedSame }
            return PreparedInstall.Mod(name: name, source: root, existing: byID?.folderURL ?? existingFolder(named: name))
        }

        guard !mods.isEmpty else {
            if let installer = Self.findSMAPIInstaller(in: work) {
                let folder = try Self.moveToUniqueLocation(installer.deletingLastPathComponent(), in: installerDestination)
                try? fm.removeItem(at: work)
                throw ModManagerError(
                    "This is the SMAPI installer, not a mod. It's been unpacked to your Downloads folder: "
                        + "double-click “\(installer.lastPathComponent)” (or right-click → Open) and follow the steps, then quit the game first if it's running.",
                    revealURL: folder.appending(path: installer.lastPathComponent)
                )
            }
            try? fm.removeItem(at: work)
            throw ModManagerError(
                "No manifest.json found anywhere inside \(archiveName) — "
                    + "this may not be a SMAPI mod (could be an XNB/content-only mod)."
            )
        }

        return PreparedInstall(
            archiveName: archiveName,
            mods: mods,
            conflicts: mods.filter { $0.existing != nil }.map(\.name),
            workDirectory: work
        )
    }

    /// Copy a prepared install into Mods. When `overwrite` is false, mods that
    /// already exist are skipped. Replaced mods go to the Trash, keep their
    /// enabled/disabled state, and keep their config.json settings.
    public func commit(_ prepared: PreparedInstall, overwrite: Bool) async -> InstallResult {
        defer { prepared.discard() }
        let fm = FileManager.default
        var result = InstallResult()

        for mod in prepared.mods {
            var destination = modsURL.appending(path: mod.name, directoryHint: .isDirectory)
            var savedConfig: Data?

            if let existing = mod.existing, fm.fileExists(atPath: existing.path(percentEncoded: false)) {
                guard overwrite else {
                    result.skipped.append(mod.name)
                    continue
                }
                savedConfig = try? Data(contentsOf: existing.appending(path: "config.json"))
                do {
                    if let archive {
                        try archive.store(existing)  // keep for "Revert"
                    } else {
                        try recycle(existing)
                    }
                } catch {
                    result.errors.append("\(mod.name): couldn't remove old version — \(error.localizedDescription)")
                    continue
                }
                destination = existing  // preserve previous enabled/disabled state
            }

            do {
                try fm.copyItem(at: mod.source, to: destination)
                let configURL = destination.appending(path: "config.json")
                if let savedConfig, !fm.fileExists(atPath: configURL.path(percentEncoded: false)) {
                    try savedConfig.write(to: configURL)
                }
                result.installed.append(mod.name)
            } catch {
                result.errors.append("\(mod.name): \(error.localizedDescription)")
            }
        }
        return result
    }

    /// The existing folder for a mod name, whether enabled ("Name") or disabled (".Name").
    func existingFolder(named name: String) -> URL? {
        [name, "." + name]
            .map { modsURL.appending(path: $0, directoryHint: .isDirectory) }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// Folders that directly contain a manifest.json. Handles the common case
    /// where Nexus zips wrap the real mod folder in an extra directory. Like
    /// SMAPI, we don't look for mods nested inside another mod's folder.
    static func findModRoots(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        else { return [] }

        var roots: [URL] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == "__MACOSX" {
                enumerator.skipDescendants()
            } else if url.lastPathComponent.caseInsensitiveCompare("manifest.json") == .orderedSame {
                roots.append(url.deletingLastPathComponent())
            }
        }

        roots.sort { $0.pathComponents.count < $1.pathComponents.count }
        var topLevel: [URL] = []
        for root in roots where !topLevel.contains(where: { root.path.hasPrefix($0.path + "/") }) {
            topLevel.append(root)
        }
        return topLevel
    }

    /// SMAPI's installer ships "install on macOS.command" (older: "install on Mac.command").
    static func findSMAPIInstaller(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent.lowercased().hasPrefix("install on mac") {
            return url
        }
        return nil
    }

    /// Moves `item` into `folder`, adding " 2", " 3"... if the name is taken.
    private static func moveToUniqueLocation(_ item: URL, in folder: URL) throws -> URL {
        let fm = FileManager.default
        let base = item.lastPathComponent
        var destination = folder.appending(path: base)
        var counter = 2
        while fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            destination = folder.appending(path: "\(base) \(counter)")
            counter += 1
        }
        try fm.moveItem(at: item, to: destination)
        return destination
    }

    private static func extract(_ archive: URL, to destination: URL) async throws {
        let source = archive.path(percentEncoded: false)
        let target = destination.path(percentEncoded: false)
        if archive.pathExtension.lowercased() == "zip" {
            try await run("/usr/bin/ditto", ["-x", "-k", source, target])
        } else {
            // macOS's tar is bsdtar/libarchive, which also reads 7z and RAR.
            try await run("/usr/bin/tar", ["-xf", source, "-C", target])
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ModManagerError("\(executable) exited with status \(finished.terminationStatus)"))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) && isDir.boolValue
    }
}
