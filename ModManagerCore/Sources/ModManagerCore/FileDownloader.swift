// Downloads a file with progress through DownloadKit: a dropped connection is
// tried again from the byte it stopped at, and the file only appears whole.

import DownloadKit
import Foundation

public enum FileDownloader {
    /// Downloads `url` into a fresh temp folder, keeping the server's file name
    /// (so the archive extension is preserved). Returns the local file URL.
    public static func download(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let folder = try Download.temporaryFolder(prefix: "sdv_download")
        do {
            return try await Download.file(url, into: folder) { update in
                if let fraction = update.fraction { progress(fraction) }
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            switch error {
            case DownloadError.http(let status, _):
                throw NexusError("Download failed (HTTP \(status)).")
            case DownloadError.rateLimited:
                throw NexusError("Download failed (HTTP \(429)).")
            case DownloadError.badResponse:
                throw NexusError("Download finished without a response.")
            default:
                throw error
            }
        }
    }
}
