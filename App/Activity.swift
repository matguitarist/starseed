// What the app is doing right now, per mod (the Installed table's Activity
// column) and overall (the status bar under the table).

import ModManagerCore
import SwiftUI

enum ModActivity: Equatable {
    case preparing
    case waitingOnNexus
    case downloading(Double)
    case installing
}

extension AppModel {
    /// The newest unfinished work for a Nexus mod.
    func activity(forNexusID id: Int) -> ModActivity? {
        if let item = downloads.first(where: { $0.modID == id && !$0.isFinished }) {
            switch item.state {
            case .downloading: return .downloading(item.progress)
            case .installing: return .installing
            default: return .preparing
            }
        }
        if browserQueue.contains(where: { $0.modID == id }) { return .waitingOnNexus }
        if preparingNexusIDs.contains(id) { return .preparing }
        return nil
    }

    func activity(for mods: [ModInfo]) -> ModActivity? {
        for mod in mods {
            if let id = nexusID(for: mod), let activity = activity(forNexusID: id) { return activity }
        }
        return nil
    }

    /// One line for the status bar, with overall progress when known.
    var activityStatus: (text: String, progress: Double?)? {
        let active = downloads.filter { !$0.isFinished }
        if !active.isEmpty {
            let downloading = active.filter { $0.state == .downloading }
            if !downloading.isEmpty {
                let fraction = downloading.map(\.progress).reduce(0, +) / Double(downloading.count)
                return (String(localized: "Downloading \(downloading.count) mod(s)…"), fraction)
            }
            if active.contains(where: { $0.state == .installing }) {
                return (String(localized: "Installing…"), nil)
            }
            return (String(localized: "Starting \(active.count) download(s)…"), nil)
        }
        if isInstalling { return (String(localized: "Installing…"), nil) }
        if !preparingNexusIDs.isEmpty { return (String(localized: "Finding files on Nexus…"), nil) }
        if isCheckingUpdates { return (String(localized: "Checking for updates…"), nil) }
        if isResolvingRequirements { return (String(localized: "Looking up requirements…"), nil) }
        if !browserQueue.isEmpty {
            return (String(localized: "\(browserQueue.count) download(s) waiting on Nexus: click “Slow download” in the browser"), nil)
        }
        return nil
    }
}

/// The Installed table's Activity cell: progress while a mod is being
/// fetched or installed, otherwise an Update button when there is one.
struct ActivityCell: View {
    @AppModelEnvironment private var model
    let mods: [ModInfo]

    var body: some View {
        if let activity = model.activity(for: mods) {
            switch activity {
            case .preparing:
                bar(nil, String(localized: "Finding file…"))
            case .waitingOnNexus:
                Button("Waiting on Nexus") { model.openInBrowser(model.browserQueue[0].url) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .help("Click “Slow download” on the Nexus page in the browser")
            case .downloading(let fraction):
                bar(fraction, fraction.formatted(.percent.precision(.fractionLength(0))))
            case .installing:
                bar(nil, String(localized: "Installing…"))
            }
        } else if let (mod, update) = mods.lazy.compactMap({ mod in model.update(for: mod).map { (mod, $0) } }).first {
            if let nexusID = model.nexusID(for: mod) {
                Button {
                    model.queueNexusInstalls([NexusInstallRequest(modID: nexusID, title: mod.displayName, version: update.version)])
                } label: {
                    Label("Update to \(update.version)", systemImage: "arrow.down.circle")
                        .monospacedDigit()
                }
                .controlSize(.small)
                .tint(.orange)
                .help("Download and install version \(update.version) from Nexus")
            } else if let url = update.url {
                Link(destination: url) {
                    Text("\(update.version) available").monospacedDigit()
                }
                .font(.caption)
                .help("This update isn't on Nexus: open its page")
            }
        }
    }

    private func bar(_ fraction: Double?, _ label: String) -> some View {
        HStack(spacing: 6) {
            if let fraction {
                ProgressView(value: fraction).progressViewStyle(.linear)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text(label).font(.caption).foregroundStyle(.secondary).monospacedDigit().fixedSize()
        }
        .controlSize(.small)
    }
}

/// A thin bar under a list showing what's running.
struct ActivityStatusBar: View {
    @AppModelEnvironment private var model

    var body: some View {
        if let status = model.activityStatus {
            HStack(spacing: 10) {
                Group {
                    if let progress = status.progress {
                        ProgressView(value: progress).progressViewStyle(.linear)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
                .frame(width: 140)
                .controlSize(.small)
                Text(status.text).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if let progress = status.progress {
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
