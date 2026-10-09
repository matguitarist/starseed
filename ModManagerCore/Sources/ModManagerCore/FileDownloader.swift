// Downloads a file with progress reporting. URLSession's async download API
// doesn't report progress, so this wraps a delegate-based download task.

import Foundation

public enum FileDownloader {
    /// Downloads `url` into a fresh temp folder, keeping the server's file name
    /// (so the archive extension is preserved). Returns the local file URL.
    public static func download(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let delegate = Delegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (tempFile, response) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NexusError("Download failed (HTTP \(http.statusCode)).")
        }

        let name = response.suggestedFilename.flatMap { $0.isEmpty ? nil : $0 }
            ?? url.lastPathComponent.removingPercentEncoding
            ?? "download.zip"
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "sdv_download_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: name)
        try FileManager.default.moveItem(at: tempFile, to: destination)
        return destination
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        // Only touched from the session's serial delegate queue.
        var continuation: CheckedContinuation<(URL, URLResponse), Error>?
        let progress: @Sendable (Double) -> Void

        init(progress: @escaping @Sendable (Double) -> Void) {
            self.progress = progress
        }

        func urlSession(
            _ session: URLSession, downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
        ) {
            guard totalBytesExpectedToWrite > 0 else { return }
            progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            // `location` is deleted when this method returns, so move it first.
            let keep = FileManager.default.temporaryDirectory.appending(path: "sdv_dl_\(UUID().uuidString)")
            do {
                try FileManager.default.moveItem(at: location, to: keep)
                if let response = downloadTask.response {
                    continuation?.resume(returning: (keep, response))
                } else {
                    continuation?.resume(throwing: NexusError("Download finished without a response."))
                }
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                continuation?.resume(throwing: error)
                continuation = nil
            }
        }
    }
}
