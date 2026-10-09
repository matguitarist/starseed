// Previous versions of mods, kept when an update replaces them, so a bad
// update can be reverted in one click.
//
// Layout: <directory>/<UniqueID>/<yyyy-MM-dd HH.mm.ss> - <version>/<mod folder>

import Foundation

public struct ArchivedVersion: Identifiable, Hashable, Sendable {
    public let folder: URL        // the archived mod folder itself
    public let uniqueID: String
    public let version: String
    public let date: Date

    public var id: URL { folder }
}

public struct ModArchive: Sendable {
    public let directory: URL
    /// Versions kept per mod; older ones go to `recycle`.
    public let keep: Int
    let recycle: @Sendable (URL) throws -> Void

    public static let defaultDirectory = ConfigStore.defaultDirectory.appending(path: "ModArchive", directoryHint: .isDirectory)

    public init(
        directory: URL = ModArchive.defaultDirectory,
        keep: Int = 3,
        recycle: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.directory = directory
        self.keep = keep
        self.recycle = recycle
    }

    private static let stampFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Moves a mod folder into the archive (out of Mods), then prunes old versions.
    public func store(_ modFolder: URL) throws {
        let mod = ManifestParser.parse(modFolder: modFolder)
        let key = Self.key(for: mod.uniqueID.isEmpty ? mod.bareFolderName : mod.uniqueID)
        let safeVersion = mod.version.replacingOccurrences(of: "/", with: "-")
        let fm = FileManager.default
        var slot = directory.appending(path: "\(key)/\(Self.stampFormat.string(from: .now)) - \(safeVersion)", directoryHint: .isDirectory)
        var counter = 2
        while fm.fileExists(atPath: slot.path(percentEncoded: false)) {
            slot = directory.appending(path: "\(key)/\(Self.stampFormat.string(from: .now)) - \(safeVersion) \(counter)", directoryHint: .isDirectory)
            counter += 1
        }
        try fm.createDirectory(at: slot, withIntermediateDirectories: true)
        // Store under the enabled name so a restore doesn't carry a stale dot.
        try fm.moveItem(at: modFolder, to: slot.appending(path: mod.bareFolderName, directoryHint: .isDirectory))
        try prune(key: key)
    }

    /// Archived versions of a mod, newest first.
    public func versions(of uniqueID: String) -> [ArchivedVersion] {
        let fm = FileManager.default
        let folder = directory.appending(path: Self.key(for: uniqueID), directoryHint: .isDirectory)
        let slots = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return slots.compactMap { slot -> ArchivedVersion? in
            guard let modFolder = (try? fm.contentsOfDirectory(at: slot, includingPropertiesForKeys: nil))?.first(where: Self.isDirectory) else { return nil }
            let name = slot.lastPathComponent
            let stamp = name.components(separatedBy: " - ").first ?? ""
            let mod = ManifestParser.parse(modFolder: modFolder)
            return ArchivedVersion(folder: modFolder, uniqueID: uniqueID, version: mod.version, date: Self.stampFormat.date(from: stamp) ?? .distantPast)
        }
        .sorted { $0.date > $1.date }
    }

    /// Puts an archived version back in place of the installed mod. The
    /// installed version is archived in turn (so you can switch back), and
    /// its config.json settings carry over.
    public func restore(_ version: ArchivedVersion, replacing installed: ModInfo) throws {
        let fm = FileManager.default
        let destination = installed.folderURL  // keeps location and enabled state
        let config = try? Data(contentsOf: destination.appending(path: "config.json"))
        // Move the archived copy out first: archiving the installed version can prune it.
        let staging = fm.temporaryDirectory.appending(path: "sdv_revert_\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.moveItem(at: version.folder, to: staging)
        do {
            try store(destination)
        } catch {
            try? fm.moveItem(at: staging, to: version.folder)
            throw error
        }
        try fm.moveItem(at: staging, to: destination)
        try? fm.removeItem(at: version.folder.deletingLastPathComponent())  // empty slot
        if let config {
            try config.write(to: destination.appending(path: "config.json"))
        }
    }

    private func prune(key: String) throws {
        let fm = FileManager.default
        let folder = directory.appending(path: key, directoryHint: .isDirectory)
        let slots = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }  // timestamps sort newest first
        for slot in slots.dropFirst(keep) {
            try recycle(slot)
        }
    }

    private static func key(for id: String) -> String {
        id.lowercased().replacingOccurrences(of: "/", with: "-")
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) && isDir.boolValue
    }
}
