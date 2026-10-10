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
        // The usual case: nothing running, so skip the per-mod lookups.
        guard !preparingNexusIDs.isEmpty || !browserQueue.isEmpty || downloads.contains(where: { !$0.isFinished }) else { return nil }
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
        if let phase = smapiInstallPhase {
            switch phase {
            case .downloading(let fraction): return ActivityStatus(text: String(localized: "Downloading SMAPI…"), progress: fraction)
            case .installing: return ActivityStatus(text: String(localized: "Installing SMAPI…"))
            }
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

/// The bar under every page: the game's and SMAPI's state on the left
/// (green: up to date, yellow: update waiting, red: missing), and what's
/// running, then briefly how it went, on the right.
struct ActivityStatusBar: View {
    @AppModelEnvironment private var model

    var body: some View {
        HStack(spacing: 12) {
            if model.manager != nil {
                GameIndicator()
                SMAPIIndicator()
            }
            if let status = model.activityStatus {
                if model.manager != nil {
                    Divider().frame(height: 14)
                }
                activity(status)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            if model.activityStatus?.isResult == true {
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
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private func activity(_ status: ActivityStatus) -> some View {
        HStack(spacing: 8) {
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
                .frame(width: 110)
                .controlSize(.small)
            }
            Text(status.text).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            if !status.isResult, let progress = status.progress {
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

/// A colored dot, a name and version, and an optional action button.
private struct VersionIndicator<Action: View>: View {
    let color: Color
    let text: String
    let help: String
    @ViewBuilder let action: Action

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.6), radius: 2)
            Text(text)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            action
        }
        .help(help)
    }
}

private struct GameIndicator: View {
    @AppModelEnvironment private var model

    var body: some View {
        if model.gameFolder == nil {
            VersionIndicator(
                color: .red,
                text: String(localized: "Stardew Valley not found"),
                help: String(localized: "The Mods folder isn't inside the game, so its version and SMAPI can't be checked.")
            ) { EmptyView() }
        } else if model.steamGame?.updatePending == true {
            VersionIndicator(
                color: .yellow,
                text: Self.name(model.gameVersion),
                help: String(localized: "Steam has an update for the game. After it, SMAPI may need reinstalling; Starseed will tell you.")
            ) {
                Button("Update in Steam") { model.openGameInSteam() }
                    .controlSize(.small)
                    .tint(.yellow)
                    .buttonStyle(.borderedProminent)
            }
        } else {
            VersionIndicator(
                color: .green,
                text: Self.name(model.gameVersion),
                help: model.steamGame == nil
                    ? String(localized: "Installed. Updates come from the store you bought it from.")
                    : String(localized: "Up to date in Steam.")
            ) { EmptyView() }
        }
    }

    static func name(_ version: SemanticVersion?) -> String {
        version.map { String(localized: "Stardew Valley \($0.description)") } ?? String(localized: "Stardew Valley")
    }
}

private struct SMAPIIndicator: View {
    @AppModelEnvironment private var model

    var body: some View {
        if model.gameFolder == nil {
            EmptyView()
        } else if let smapi = model.smapi {
            let name = smapi.version.map { "SMAPI \($0.description)" } ?? "SMAPI"
            if !smapi.isLauncherHooked {
                VersionIndicator(
                    color: .yellow,
                    text: String(localized: "\(name), disconnected"),
                    help: String(localized: "A game update replaced SMAPI's launcher: the game starts without mods until SMAPI is reinstalled.")
                ) { button(String(localized: "Reinstall")) }
            } else if model.isSMAPIOutdated, let latest = model.latestSMAPIVersion {
                VersionIndicator(
                    color: .yellow,
                    text: name,
                    help: String(localized: "SMAPI \(latest.description) is available.")
                ) { button(String(localized: "Update to \(latest.description)")) }
            } else if !model.modsNeedingNewerSMAPI.isEmpty {
                VersionIndicator(
                    color: .yellow,
                    text: name,
                    help: String(localized: "Some mods need a newer SMAPI.")
                ) { button(String(localized: "Update")) }
            } else {
                VersionIndicator(
                    color: .green,
                    text: name,
                    help: model.latestSMAPIVersion == nil ? String(localized: "Installed.") : String(localized: "Up to date.")
                ) { EmptyView() }
            }
        } else {
            VersionIndicator(
                color: .red,
                text: String(localized: "SMAPI not installed"),
                help: String(localized: "Mods only load through SMAPI.")
            ) { button(String(localized: "Install")) }
        }
    }

    @ViewBuilder
    private func button(_ title: String) -> some View {
        if model.smapiInstallPhase != nil {
            ProgressView().controlSize(.mini)
        } else {
            Button(title) { model.installSMAPI() }
                .controlSize(.small)
                .tint(.yellow)
                .buttonStyle(.borderedProminent)
                .help("Downloads SMAPI's official installer from GitHub and runs it for your game. Quit the game first.")
        }
    }
}
