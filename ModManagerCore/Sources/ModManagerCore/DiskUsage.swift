// How much space mods, kept versions and save backups take on disk.

import Foundation

public enum DiskUsage {
    /// Bytes a file or folder takes on disk (allocated size, so it matches Finder).
    public static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in items {
            guard let values = try? item.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}

extension ModArchive {
    /// Every kept version of every mod, newest first.
    public func allVersions() -> [ArchivedVersion] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return folders.flatMap { versions(of: $0.lastPathComponent) }.sorted { $0.date > $1.date }
    }

    /// Moves one kept version to the Trash.
    public func remove(_ version: ArchivedVersion) throws {
        let slot = version.folder.deletingLastPathComponent()
        try recycle(slot)
        // Drop the mod's folder once its last version is gone.
        let modFolder = slot.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: modFolder.path(percentEncoded: false)))?.isEmpty == true {
            try? FileManager.default.removeItem(at: modFolder)
        }
    }
}
