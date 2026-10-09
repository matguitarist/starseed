// Save backups: zip files with one or more save folders at their root, the
// same layout SMAPI's Save Backup mod uses, so its daily backups (in the
// game folder's save-backups/) can be listed and restored too.

import Foundation

public struct SaveBackup: Identifiable, Hashable, Sendable {
    public let url: URL
    public let date: Date
    /// Save folder names inside the zip ("Mats_391030616").
    public let saveIDs: [String]
    /// "Farm name (Farmer)" per save ID, read from each SaveGameInfo.
    public let saveNames: [String: String]
    public let byteCount: Int64
    /// Made by SMAPI's Save Backup mod rather than this app.
    public let isSMAPIBackup: Bool

    public var id: URL { url }

    /// The label part of "2026-10-08 20.22.05 - Before restore.zip".
    public var label: String {
        let name = url.deletingPathExtension().lastPathComponent
        if let range = name.range(of: " - ") { return String(name[range.upperBound...]) }
        return name
    }
}

public struct SaveBackupStore: Sendable {
    public let directory: URL
    public let smapiDirectory: URL?
    public let savesFolder: URL
    let recycle: @Sendable (URL) throws -> Void

    public static let defaultDirectory = ConfigStore.defaultDirectory.appending(path: "SaveBackups", directoryHint: .isDirectory)

    /// - Parameter gameFolder: where SMAPI's Save Backup mod writes `save-backups/`.
    public init(
        directory: URL = SaveBackupStore.defaultDirectory,
        gameFolder: URL? = nil,
        savesFolder: URL = SaveGame.defaultFolder,
        recycle: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.directory = directory
        self.smapiDirectory = gameFolder?.appending(path: "save-backups", directoryHint: .isDirectory)
        self.savesFolder = savesFolder
        self.recycle = recycle
    }

    // MARK: Listing

    /// All backups (this app's and SMAPI's), newest first.
    public func list() async -> [SaveBackup] {
        var backups: [SaveBackup] = []
        for (folder, isSMAPI) in [(directory, false), (smapiDirectory, true)] {
            guard let folder,
                  let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            else { continue }
            for file in files where file.pathExtension.lowercased() == "zip" {
                if let backup = await Self.inspect(file, isSMAPIBackup: isSMAPI) {
                    backups.append(backup)
                }
            }
        }
        return backups.sorted { $0.date > $1.date }
    }

    static func inspect(_ zip: URL, isSMAPIBackup: Bool) async -> SaveBackup? {
        guard let listing = try? await Archive.run("/usr/bin/zipinfo", ["-1", zip.path(percentEncoded: false)]) else { return nil }
        // Top-level folders that contain a SaveGameInfo are saves.
        var ids: [String] = []
        for line in listing.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "/")
            if parts.count == 2, parts[1] == "SaveGameInfo", !ids.contains(String(parts[0])) {
                ids.append(String(parts[0]))
            }
        }
        guard !ids.isEmpty else { return nil }

        var names: [String: String] = [:]
        for id in ids {
            if let info = try? await Archive.run("/usr/bin/unzip", ["-p", zip.path(percentEncoded: false), "\(id)/SaveGameInfo"]) {
                let farm = info.xmlTag("farmName").map { "\($0) Farm" } ?? id
                var name = info.xmlTag("name").map { "\(farm) (\($0))" } ?? farm
                // The in-game date tells apart saves with the same farm name.
                let seasons = ["Spring", "Summer", "Fall", "Winter"]
                if let day = info.xmlTag("dayOfMonthForSaveGame"), let year = info.xmlTag("yearForSaveGame"),
                   let season = info.xmlTag("seasonForSaveGame").flatMap(Int.init), seasons.indices.contains(season) {
                    name += " · \(seasons[season]) \(day), Year \(year)"
                }
                names[id] = name
            }
        }
        let values = try? zip.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return SaveBackup(
            url: zip,
            date: values?.contentModificationDate ?? .distantPast,
            saveIDs: ids.sorted(),
            saveNames: names,
            byteCount: Int64(values?.fileSize ?? 0),
            isSMAPIBackup: isSMAPIBackup
        )
    }

    // MARK: Backing up

    /// Zips the given save folders into one backup.
    @discardableResult
    public func backUp(saveIDs: [String], label: String) async throws -> SaveBackup {
        let fm = FileManager.default
        let existing = saveIDs.filter { fm.fileExists(atPath: savesFolder.appending(path: $0).path(percentEncoded: false)) }
        guard !existing.isEmpty else { throw ModManagerError("There are no saves to back up.") }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let safeLabel = label.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var zip = directory.appending(path: "\(formatter.string(from: .now)) - \(safeLabel).zip")
        var counter = 2
        while fm.fileExists(atPath: zip.path(percentEncoded: false)) {
            zip = directory.appending(path: "\(formatter.string(from: .now)) - \(safeLabel) \(counter).zip")
            counter += 1
        }

        // -r recurse, -q quiet, -X no extra file attributes; run inside the
        // Saves folder so each save is a top-level folder in the zip.
        _ = try await Archive.run("/usr/bin/zip", ["-r", "-q", "-X", zip.path(percentEncoded: false)] + existing, in: savesFolder)
        guard let backup = await Self.inspect(zip, isSMAPIBackup: false) else {
            throw ModManagerError("The backup was created but couldn't be read back.")
        }
        return backup
    }

    // MARK: Restoring

    /// Restores saves from a backup (all of them when `saveIDs` is nil). The
    /// current versions are first backed up ("Before restore") and moved to
    /// the Trash, so a restore can always be undone.
    public func restore(_ backup: SaveBackup, saveIDs: [String]? = nil) async throws {
        let fm = FileManager.default
        let ids = saveIDs ?? backup.saveIDs
        guard !ids.isEmpty, Set(ids).isSubset(of: backup.saveIDs) else {
            throw ModManagerError("That backup doesn't contain the selected save.")
        }

        let current = ids.filter { fm.fileExists(atPath: savesFolder.appending(path: $0).path(percentEncoded: false)) }
        if !current.isEmpty {
            try await backUp(saveIDs: current, label: "Before restore")
        }

        let work = fm.temporaryDirectory.appending(path: "sdv_restore_\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        _ = try await Archive.run("/usr/bin/ditto", ["-x", "-k", backup.url.path(percentEncoded: false), work.path(percentEncoded: false)])

        try fm.createDirectory(at: savesFolder, withIntermediateDirectories: true)
        for id in ids {
            let source = work.appending(path: id, directoryHint: .isDirectory)
            let destination = savesFolder.appending(path: id, directoryHint: .isDirectory)
            guard fm.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
            if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
                try recycle(destination)
            }
            try fm.moveItem(at: source, to: destination)
        }
    }

    /// Deletes one of this app's backups (to the Trash). SMAPI's are left alone.
    public func delete(_ backup: SaveBackup) throws {
        guard !backup.isSMAPIBackup else { throw ModManagerError("SMAPI's own backups are managed by its Save Backup mod.") }
        try recycle(backup.url)
    }
}

/// Runs the system archive tools and returns their output.
enum Archive {
    static func run(_ executable: String, _ arguments: [String], in directory: URL? = nil) async throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            // Read on a background thread so a large output can't fill the pipe and stall the tool.
            let handle = output.fileHandleForReading
            let reader = Task.detached { handle.readDataToEndOfFile() }
            process.terminationHandler = { finished in
                Task {
                    let data = await reader.value
                    if finished.terminationStatus == 0 {
                        continuation.resume(returning: String(decoding: data, as: UTF8.self))
                    } else {
                        continuation.resume(throwing: ModManagerError("\((executable as NSString).lastPathComponent) failed (status \(finished.terminationStatus))."))
                    }
                }
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

extension String {
    /// Text of the first <tag>…</tag>, XML-unescaped.
    func xmlTag(_ name: String) -> String? {
        guard let open = range(of: "<\(name)>"),
              let close = range(of: "</\(name)>", range: open.upperBound..<endIndex)
        else { return nil }
        return String(self[open.upperBound..<close.lowerBound]).xmlUnescaped
    }
}
