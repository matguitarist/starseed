// Save backups: zip files with one or more save folders at their root, the
// same layout SMAPI's Save Backup mod uses, so its daily backups (in the
// game folder's save-backups/) can be listed and restored too.

import Foundation
import ArchiveKit

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

    /// Where pruned backups and the saves a restore replaces go.
    var folder: BackupFolder { BackupFolder(root: directory, disposal: .custom(recycle)) }

    // MARK: Listing

    /// All backups (this app's and SMAPI's), newest first.
    public func list() async -> [SaveBackup] {
        var backups: [SaveBackup] = []
        for (root, isSMAPI) in [(directory, false), (smapiDirectory, true)] {
            guard let root else { continue }
            for zip in BackupFolder(root: root).list() {
                if let backup = await Self.inspect(zip.url, isSMAPIBackup: isSMAPI) {
                    backups.append(backup)
                }
            }
        }
        return backups.sorted { $0.date > $1.date }
    }

    static func inspect(_ zip: URL, isSMAPIBackup: Bool) async -> SaveBackup? {
        guard let entries = try? Zip.entries(zip) else { return nil }
        // Top-level folders that contain a SaveGameInfo are saves.
        var ids: [String] = []
        for entry in entries {
            let parts = entry.name.split(separator: "/")
            if parts.count == 2, parts[1] == "SaveGameInfo", !ids.contains(String(parts[0])) {
                ids.append(String(parts[0]))
            }
        }
        guard !ids.isEmpty else { return nil }

        var names: [String: String] = [:]
        for id in ids {
            if let data = try? await Zip.read("\(id)/SaveGameInfo", from: zip, limit: 16 << 20) {
                let info = String(decoding: data, as: UTF8.self)
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

    /// Zips the given save folders into one backup: "2026-10-08 20.22.05 - label.zip",
    /// with " 2" when one was made in the same second. Each save is a top-level folder.
    @discardableResult
    public func backUp(saveIDs: [String], label: String) async throws -> SaveBackup {
        let existing = saveIDs.filter { FileManager.default.fileExists(atPath: savesFolder.appending(path: $0).path(percentEncoded: false)) }
        guard !existing.isEmpty else { throw ModManagerError("There are no saves to back up.") }
        // A plain zip (no macOS metadata), like SMAPI's Save Backup mod writes.
        let zip: BackupFolder.Backup
        do {
            zip = try await folder.backUp(from: savesFolder, items: existing, label: label, macMetadata: false)
        } catch {
            throw ModManagerError(archive: error)
        }
        guard let backup = await Self.inspect(zip.url, isSMAPIBackup: false) else {
            throw ModManagerError("The backup was created but couldn't be read back.")
        }
        return backup
    }

    /// Keeps the newest `keep` of this app's backups whose label is one of
    /// `labels` (e.g. automatic ones), recycling the rest. "Auto 2" is a
    /// second "Auto" made in the same second.
    public func prune(labels: Set<String>, keep: Int) async throws {
        try folder.prune(keep: keep) { $0.label.map(labels.contains) ?? false }
    }

    // MARK: Restoring

    /// Restores saves from a backup (all of them when `saveIDs` is nil). The
    /// current versions are first backed up ("Before restore") and moved to
    /// the Trash, so a restore can always be undone.
    public func restore(_ backup: SaveBackup, saveIDs: [String]? = nil) async throws {
        let ids = saveIDs ?? backup.saveIDs
        guard !ids.isEmpty, Set(ids).isSubset(of: backup.saveIDs) else {
            throw ModManagerError("That backup doesn't contain the selected save.")
        }

        let current = ids.filter { FileManager.default.fileExists(atPath: savesFolder.appending(path: $0).path(percentEncoded: false)) }
        if !current.isEmpty {
            try await backUp(saveIDs: current, label: "Before restore")
        }

        // Unpacked beside the Saves folder first; each save then replaces its
        // current folder, and the others stay as they are.
        let source = BackupFolder(root: backup.url.deletingLastPathComponent(), disposal: .custom(recycle))
        let wanted = ids
        do {
            try await source.restore(try source.backup(at: backup.url), into: savesFolder, items: ids) { content in
                // A zip of one save holds one folder: its top is still the Saves folder.
                wanted.contains { FileManager.default.fileExists(atPath: content.appending(path: "\($0)/SaveGameInfo").path(percentEncoded: false)) }
            }
        } catch {
            throw ModManagerError(archive: error)
        }
    }

    /// Deletes one of this app's backups (to the Trash). SMAPI's are left alone.
    public func delete(_ backup: SaveBackup) throws {
        guard !backup.isSMAPIBackup else { throw ModManagerError("SMAPI's own backups are managed by its Save Backup mod.") }
        try recycle(backup.url)
    }
}

extension ModManagerError {
    /// ArchiveKit's errors in this app's words.
    init(archive error: any Error) {
        switch error {
        case let error as ModManagerError:
            self = error
        case ArchiveError.nothingToBackUp:
            self.init("There are no saves to back up.")
        case ArchiveError.notABackup:
            self.init("That backup doesn't contain the selected save.")
        case ArchiveError.unsafeEntry(let name):
            self.init("This archive tries to write outside its folder (“\(name)”), so nothing was unpacked.")
        default:
            self.init(verbatim: error.localizedDescription)
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
