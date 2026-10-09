import Foundation
import ModManagerCore
import SwiftUI

/// One Nexus download shown in the sidebar.
@MainActor
@Observable
final class DownloadItem: Identifiable {
    enum State: Equatable {
        case waiting
        case downloading
        case installing
        case installed
        case failed(String)
    }

    let id = UUID()
    var title: String
    /// The Nexus mod being downloaded, to show progress on its row.
    let modID: Int?
    var progress = 0.0
    var state = State.waiting

    init(title: String, modID: Int? = nil) {
        self.title = title
        self.modID = modID
    }

    var isFinished: Bool {
        switch state {
        case .installed, .failed: true
        default: false
        }
    }
}

/// Asks the root view to show the Nexus mod sheet. `preview` lets the sheet
/// draw immediately when we already have search-result data.
struct NexusSheetRequest: Identifiable {
    let modID: Int
    var preview: NexusMod?
    var id: Int { modID }
}

/// One Nexus mod to install (update, requirement...). `version` picks the
/// matching file when known; otherwise the newest main file is used.
struct NexusInstallRequest {
    let modID: Int
    let title: String
    let version: String?
    var fileID: Int? = nil  // install this exact file instead of picking one
}

struct CollectionSheetRequest: Identifiable {
    let slug: String
    var revision: Int? = nil
    var preview: NexusCollection? = nil
    var id: String { slug }
}

struct BrowserRequest: Equatable {
    let id = UUID()
    let url: URL
}

struct BrowserQueueItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let url: URL
    var modID: Int? = nil
}

struct DownloadRow: View {
    let item: DownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .lineLimit(1)
                .truncationMode(.middle)
            switch item.state {
            case .waiting:
                ProgressView().progressViewStyle(.linear).controlSize(.small)
            case .downloading:
                ProgressView(value: item.progress).controlSize(.small)
            case .installing:
                Text("Installing…").font(.caption).foregroundStyle(.secondary)
            case .installed:
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed(let message):
                Label("Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .help(message)
            }
        }
        .padding(.vertical, 2)
    }
}

/// "#7286": the Nexus mod number, matching the website's address
/// (nexusmods.com/stardewvalley/mods/7286). Opens that page in the app's browser.
struct NexusIDLink: View {
    @AppModelEnvironment private var model
    let modID: Int

    var body: some View {
        // Verbatim: a localized title would print 5787 as "5,787", which
        // no longer matches the website's address.
        Button {
            model.openInBrowser(NexusClient.modPageURL(modID))
        } label: {
            Text(verbatim: "#\(modID)")
        }
            .buttonStyle(.link)
            .font(.caption.monospacedDigit())
            .help(NexusClient.modPageURL(modID).absoluteString)
    }
}

/// 👍 Endorse and Track buttons for a Nexus mod (needs a verified API key).
struct EndorseTrackButtons: View {
    @AppModelEnvironment private var model
    let modID: Int
    var version: String? = nil

    var body: some View {
        if model.nexusAccount.user != nil {
            let endorsed = model.endorsements[modID] == .endorsed
            let tracked = model.trackedMods.contains(modID)
            HStack(spacing: 6) {
                Button {
                    model.setEndorsed(!endorsed, modID: modID, version: version)
                } label: {
                    Label(endorsed ? "Endorsed" : "Endorse", systemImage: endorsed ? "hand.thumbsup.fill" : "hand.thumbsup")
                }
                .tint(endorsed ? .green : nil)
                .help(endorsed ? "You endorsed this mod. Click to withdraw it." : "Thank the author by endorsing this mod on Nexus")
                Button {
                    model.setTracked(!tracked, modID: modID)
                } label: {
                    Label(tracked ? "Tracking" : "Track", systemImage: tracked ? "bell.fill" : "bell")
                }
                .help(tracked ? "Nexus notifies you about this mod. Click to stop." : "Get Nexus notifications when this mod is updated")
            }
            .controlSize(.small)
        }
    }
}

extension String {
    /// Nexus summaries and file descriptions contain BBCode, HTML tags and
    /// entities; flatten them to plain text for display.
    var strippingNexusMarkup: String {
        var text = replacing(/<br\s*\/?>/.ignoresCase(), with: "\n")
            .replacing(/<[^>]+>/, with: "")
            .replacing(/\[\/?[a-zA-Z*]+(=[^\]]*)?\]/, with: "")
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// "Get on ModDrop ↗": for requirements that aren't on Nexus. Opens the
/// page in the default browser; the file is then dropped on the window.
struct DownloadPageButton: View {
    @AppModelEnvironment private var model
    let page: URL
    let site: String?
    var controlSize: ControlSize = .small

    var body: some View {
        Button {
            model.openDownloadPage(page)
        } label: {
            Label(site.map { String(localized: "Get on \($0)") } ?? String(localized: "Download Page"), systemImage: "arrow.up.right.square")
        }
        .controlSize(controlSize)
        .help(String(localized: "Not on Nexus. Opens \(page.absoluteString); download the file, then drop it on this window."))
    }
}
