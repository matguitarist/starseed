// Installing archives (one at a time), Nexus downloads, and the in-app
// browser's download queue.

import AppKit
import ModManagerCore
import SwiftUI
import UniformTypeIdentifiers

extension AppModel {
    // MARK: Installing

    func presentInstallPanel() {
        guard manager != nil else { return }
        let panel = NSOpenPanel()
        panel.message = String(localized: "Select downloaded mod archives (.zip, .7z, .rar)")
        panel.allowedContentTypes = ModManager.archiveExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.directoryURL = .downloadsDirectory
        if panel.runModal() == .OK {
            install(panel.urls)
        }
    }

    /// Queues archives for installation. Installs run one at a time, so
    /// conflict prompts never overlap.
    ///
    /// - Parameters:
    ///   - replaceExisting: skip the "already installed" prompt and replace
    ///     (used for downloads the user explicitly picked, i.e. updates).
    ///   - quiet: don't show a summary alert on success.
    @discardableResult
    func install(_ urls: [URL], replaceExisting: Bool = false, quiet: Bool = false) -> Task<InstallResult, Never> {
        let previous = installQueue
        pendingInstalls += 1
        let task = Task {
            await previous?.value
            defer { pendingInstalls -= 1 }
            return await performInstall(urls, replaceExisting: replaceExisting, quiet: quiet)
        }
        installQueue = Task { _ = await task.value }
        return task
    }

    private func performInstall(_ urls: [URL], replaceExisting: Bool, quiet: Bool) async -> InstallResult {
        var total = InstallResult()
        guard let manager else {
            total.errors.append(String(localized: "Choose your Mods folder first."))
            report(total)
            return total
        }
        let archives = urls.filter { ModManager.archiveExtensions.contains($0.pathExtension.lowercased()) }
        guard !archives.isEmpty else {
            show("Nothing to install", "Drop or choose mod archives (.zip, .7z, .rar) downloaded from Nexus or elsewhere.")
            return total
        }

        let missingBefore = Set(missingDependencies.map(\.id))
        for archive in archives {
            do {
                let prepared = try await manager.prepareInstall(archive: archive)
                var overwrite = replaceExisting
                if !prepared.conflicts.isEmpty && !replaceExisting {
                    guard let choice = await askAboutConflicts(prepared) else {
                        prepared.discard()  // cancelled this archive
                        continue
                    }
                    overwrite = choice
                }
                total.merge(await manager.commit(prepared, overwrite: overwrite))
            } catch let error as ModManagerError where error.revealURL != nil {
                // SMAPI's installer: unpacked to Downloads rather than installed.
                NSWorkspace.shared.activateFileViewerSelecting([error.revealURL!])
                show("SMAPI Installer Ready", detail: error.message)
            } catch {
                total.errors.append(error.localizedDescription)
            }
        }

        refresh()
        if !total.installed.isEmpty {
            Task { await checkForUpdates() }
            let newlyMissing = missingDependencies.filter { !missingBefore.contains($0.id) }
            if !newlyMissing.isEmpty {
                Task {
                    await resolveMissingDependencies()
                    requirementsPrompt = newlyMissing
                }
            }
        }
        if !quiet || !total.errors.isEmpty {
            report(total)
        }
        return total
    }

    func resolveConflict(_ overwrite: Bool?) {
        guard let prompt = conflictPrompt else { return }
        conflictPrompt = nil
        prompt.continuation.resume(returning: overwrite)
    }

    private func askAboutConflicts(_ prepared: PreparedInstall) async -> Bool? {
        await withCheckedContinuation { continuation in
            conflictPrompt = ConflictPrompt(
                archiveName: prepared.archiveName,
                names: prepared.conflicts,
                continuation: continuation
            )
        }
    }

    private func report(_ result: InstallResult) {
        guard !result.isEmpty else { return }
        var lines: [String] = []
        if !result.installed.isEmpty { lines.append(String(localized: "Installed/updated: \(result.installed.joined(separator: ", "))")) }
        if !result.skipped.isEmpty { lines.append(String(localized: "Skipped: \(result.skipped.joined(separator: ", "))")) }
        if !result.errors.isEmpty { lines.append(String(localized: "Errors:\n\(result.errors.joined(separator: "\n"))")) }
        let title = result.errors.isEmpty ? String(localized: "Install Complete") : String(localized: "Install Finished with Problems")
        show(localizedTitle: title, detail: lines.joined(separator: "\n\n"))
    }

    // MARK: Downloads

    /// Handles nxm:// links from the website's "Mod Manager Download" button,
    /// and archive files opened with the app.
    func handleOpenURL(_ url: URL) {
        if url.isFileURL {
            install([url])
            return
        }
        if let collection = NXMCollectionLink(url: url), collection.gameDomain == NexusClient.gameDomain {
            collectionSheet = CollectionSheetRequest(slug: collection.slug, revision: collection.revision)
            NSApp.activate()
            return
        }
        guard let link = NXMLink(url: url) else {
            show("Unsupported Link", detail: url.absoluteString)
            return
        }
        guard link.gameDomain == NexusClient.gameDomain else {
            show("Not a Stardew Valley Mod", "This link is for “\(link.gameDomain)”. Only Stardew Valley mods can be installed here.")
            return
        }
        downloadAndInstall(modID: link.modID, fileID: link.fileID, title: "Nexus mod \(link.modID)", key: link.key, expires: link.expires)
    }

    /// Downloads one Nexus file and installs it, replacing an older copy.
    func downloadAndInstall(modID: Int, fileID: Int, title: String, key: String? = nil, expires: String? = nil) {
        guard manager != nil else {
            show("Choose Your Mods Folder", "Pick your Mods folder before installing mods.")
            return
        }
        guard nexusAPIKey != nil else {
            show("Nexus API Key Needed", "Add your personal Nexus Mods API key in Settings → Nexus Mods to download mods.")
            return
        }

        let item = DownloadItem(title: title, modID: modID)
        downloads.insert(item, at: 0)
        let client = nexusClient

        Task {
            if title.hasPrefix("Nexus mod "), let mod = try? await client.mod(id: modID) {
                item.title = mod.name
            }
        }

        Task {
            var folder: URL?
            do {
                let url = try await client.downloadURL(modID: modID, fileID: fileID, key: key, expires: expires)
                item.state = .downloading
                let file = try await FileDownloader.download(url) { fraction in
                    Task { @MainActor in item.progress = fraction }
                }
                folder = file.deletingLastPathComponent()
                item.state = .installing
                let result = await install([file], replaceExisting: true, quiet: true).value
                item.state = result.errors.isEmpty ? .installed : .failed(result.errors.joined(separator: "\n"))
            } catch {
                item.state = .failed(error.localizedDescription)
            }
            if let folder { try? FileManager.default.removeItem(at: folder) }
        }
    }

    func clearFinishedDownloads() {
        downloads.removeAll { $0.isFinished }
    }

    /// Installs the best file for each Nexus mod: directly for Premium
    /// accounts, otherwise by walking the in-app browser through each mod's
    /// "Mod Manager Download" page.
    func queueNexusInstalls(_ requests: [NexusInstallRequest]) {
        guard !requests.isEmpty else { return }
        guard nexusAPIKey != nil else {
            show("Nexus API Key Needed", "Add your personal Nexus Mods API key in Settings → Nexus Mods to download mods.")
            return
        }
        let client = nexusClient
        let isPremium = nexusAccount.user?.isPremium == true

        let ids = Set(requests.map(\.modID))
        preparingNexusIDs.formUnion(ids)
        Task {
            defer { preparingNexusIDs.subtract(ids) }
            var pages: [BrowserQueueItem] = []
            var failures: [String] = []
            for request in requests {
                defer { preparingNexusIDs.remove(request.modID) }
                do {
                    let fileID: Int
                    if let pinned = request.fileID {
                        fileID = pinned  // e.g. a collection's exact file
                    } else if let file = NexusFile.bestMatch(in: try await client.files(forMod: request.modID), version: request.version) {
                        fileID = file.fileId
                    } else {
                        failures.append(String(localized: "\(request.title): no downloadable file"))
                        continue
                    }
                    if isPremium {
                        downloadAndInstall(modID: request.modID, fileID: fileID, title: request.title)
                    } else {
                        pages.append(BrowserQueueItem(
                            title: request.title,
                            url: NexusClient.modManagerDownloadPageURL(modID: request.modID, fileID: fileID),
                            modID: request.modID
                        ))
                    }
                } catch {
                    failures.append("\(request.title): \(error.localizedDescription)")
                }
            }
            if !pages.isEmpty {
                browserQueue += pages
                openInBrowser(browserQueue[0].url)
            }
            if !failures.isEmpty {
                show("Some Mods Couldn't Be Queued", detail: failures.joined(separator: "\n"))
            }
        }
    }

    // MARK: In-app browser

    func openInBrowser(_ url: URL) {
        browserRequest = BrowserRequest(url: url)
    }

    /// Called by the browser when Nexus hands over an nxm:// link.
    func browserDidReceiveNXM(_ url: URL) {
        handleOpenURL(url)
        advanceBrowserQueue()
    }

    func advanceBrowserQueue() {
        guard !browserQueue.isEmpty else { return }
        browserQueue.removeFirst()
        if let next = browserQueue.first {
            openInBrowser(next.url)
        }
    }

    func cancelBrowserQueue() {
        browserQueue = []
    }

    /// A mod archive downloaded directly in the browser (e.g. "Manual download").
    func installBrowserDownload(_ file: URL) {
        let item = DownloadItem(title: file.lastPathComponent)
        item.state = .installing
        downloads.insert(item, at: 0)
        Task {
            let result = await install([file], replaceExisting: true, quiet: true).value
            item.state = result.errors.isEmpty ? .installed : .failed(result.errors.joined(separator: "\n"))
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
    }
}
