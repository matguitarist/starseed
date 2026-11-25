// Downloads a file with progress through DownloadKit: a dropped connection is
// tried again from the byte it stopped at, and the file only appears whole.

import DownloadKit
import Foundation

public enum FileDownloader {
    /// What Starseed's downloads send: the system's own User-Agent, as before
    /// DownloadKit, and the server's suggested file name.
    static let options = DownloadOptions(usesSystemUserAgent: true, prefersSuggestedFilename: true)

    /// Downloads `url` into a fresh temp folder, keeping the server's file name
    /// (so the archive extension is preserved). Returns the local file URL.
    public static func download(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let folder = try Download.temporaryFolder(prefix: "sdv_download")
        do {
            return try await Download.file(url, into: folder, options: options) { update in
                if let fraction = update.fraction { progress(fraction) }
            }
        } catch let error as DownloadError {
            try? FileManager.default.removeItem(at: folder)
            if let status = error.status {
                throw NexusError("Download failed (HTTP \(status)).")
            }
            if case .badResponse = error {
                throw NexusError("Download finished without a response.")
            }
            throw error
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}
