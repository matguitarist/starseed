// What the app is doing right now, per mod (the Installed table's Activity
// column) and overall (the status bar under the table).

import ModManagerCore
import SwiftUI

struct ProgressStep: Equatable {
    var text: String
    var fraction: Double?
}

struct StatusResult: Equatable {
    let id = UUID()  // the same text twice is two results
    var text: String
    var isError = false
}

struct ActivityStatus: Equatable {
    var text: String
    var progress: Double?
    /// A finished task's result: a checkmark instead of a bar.
    var isResult = false
    var isError = false
}

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
    var activityStatus: ActivityStatus? {
        let active = downloads.filter { !$0.isFinished }
        if !active.isEmpty {
            let downloading = active.filter { $0.state == .downloading }
            if !downloading.isEmpty {
                let fraction = downloading.map(\.progress).reduce(0, +) / Double(downloading.count)
                return ActivityStatus(text: String(localized: "Downloading \(downloading.count) mod(s)…"), progress: fraction)
            }
            if active.contains(where: { $0.state == .installing }) {
                return ActivityStatus(text: String(localized: "Installing…"))
            }
            return ActivityStatus(text: String(localized: "Starting \(active.count) download(s)…"))
        }
        if isInstalling { return ActivityStatus(text: String(localized: "Installing…")) }
        if isBackingUpBeforePlay { return ActivityStatus(text: String(localized: "Backing up your saves before playing…")) }
        if !preparingNexusIDs.isEmpty { return ActivityStatus(text: String(localized: "Finding files on Nexus…")) }
        if let step = updateCheckStep { return ActivityStatus(text: step.text, progress: step.fraction) }
        if isCheckingUpdates { return ActivityStatus(text: String(localized: "Checking for updates…")) }
        if isResolvingRequirements { return ActivityStatus(text: String(localized: "Looking up requirements…")) }
        if !browserQueue.isEmpty {
            return ActivityStatus(text: String(localized: "\(browserQueue.count) download(s) waiting on Nexus: click “Slow download” in the browser"))
        }
        if let statusResult {
            return ActivityStatus(text: statusResult.text, isResult: true, isError: statusResult.isError)
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

/// A thin bar under every page showing what's running, then briefly how
/// it went ("Checked 30 mods: all up to date").
struct ActivityStatusBar: View {
    @AppModelEnvironment private var model

    var body: some View {
        if let status = model.activityStatus {
            HStack(spacing: 10) {
                if status.isResult {
                    Image(systemName: status.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(status.isError ? .orange : .green)
                } else {
                    Group {
                        if let progress = status.progress {
                            ProgressView(value: progress).progressViewStyle(.linear)
                        } else {
                            ProgressView().progressViewStyle(.linear)
                        }
                    }
                    .frame(width: 140)
                    .controlSize(.small)
                }
                Text(status.text).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if !status.isResult, let progress = status.progress {
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer()
                if status.isResult {
                    Button {
                        model.statusResult = nil
                    } label: {
                        Image(systemName: "xmark").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
