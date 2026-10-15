import ModManagerCore
import SwiftUI

/// Installed mods that have a newer version, according to SMAPI's update API.
struct UpdatesView: View {
    @AppModelEnvironment private var model

    var body: some View {
        Group {
            if model.modsWithUpdates.isEmpty {
                ContentUnavailableView {
                    Label(
                        model.isCheckingUpdates ? "Checking for Updates…" : "All Mods Up to Date",
                        systemImage: model.isCheckingUpdates ? "arrow.triangle.2.circlepath" : "checkmark.circle"
                    )
                } description: {
                    if let error = model.updateCheckError {
                        Text(error)
                    } else if let date = model.lastUpdateCheck {
                        Text("Last checked \(date.formatted(.relative(presentation: .named))).")
                    }
                } actions: {
                    Button("Check Now") { Task { await model.checkForUpdates() } }
                        .disabled(model.isCheckingUpdates)
                }
            } else {
                VStack(spacing: 0) {
                    updateAllBar
                    List(model.modsWithUpdates) { mod in
                        if let update = model.update(for: mod) {
                            UpdateRow(mod: mod, update: update)
                        }
                    }
                }
            }
        }
        .navigationTitle("Updates")
        .navigationSubtitle(model.modsWithUpdates.isEmpty ? "" : "\(model.modsWithUpdates.count) available")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                RefreshToolbarButton(title: "Check for Updates", help: "Check for updates", isBusy: model.isCheckingUpdates) {
                    Task { await model.checkForUpdates() }
                }
                PlayToolbarButton()
            }
        }
    }
}

extension UpdatesView {
    /// "3 updates available · [Update All]" above the list.
    private var updateAllBar: some View {
        let count = model.nexusUpdates.count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.modsWithUpdates.count == 1 ? String(localized: "1 mod update available") : String(localized: "\(model.modsWithUpdates.count) mod updates available"))
                    .font(.headline)
                if model.nexusAccount.user?.isPremium != true, count > 0 {
                    Text("Free account: Nexus's page for each update opens in turn; click **Slow download** on each. The browser closes after the last one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                model.updateAll()
            } label: {
                Label(count > 0 ? String(localized: "Update All (\(count))") : String(localized: "Update All"), systemImage: "square.and.arrow.down.on.square")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(count == 0 || model.nexusAccount.user == nil)
            .help(model.nexusAccount.user == nil ? "Add your Nexus API key in Settings first"
                  : model.nexusAccount.user?.isPremium == true ? "Download and install every Nexus update"
                  : "Walk through each update's Nexus download page")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct UpdateRow: View {
    @AppModelEnvironment private var model
    let mod: ModInfo
    let update: ModUpdate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row
            if let nexusID = model.nexusID(for: mod) {
                ChangelogDisclosure(nexusID: nexusID, installed: mod.version, latest: update.version)
            }
        }
        .padding(.vertical, 4)
    }

    private var row: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mod.displayName).font(.headline)
                    if let nexusID = model.nexusID(for: mod) { NexusIDLink(modID: nexusID) }
                }
                HStack(spacing: 4) {
                    Text(mod.version)
                    Image(systemName: "arrow.right")
                    Text(update.version).foregroundStyle(.orange)
                }
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            Spacer()
            if model.activity(for: [mod]) != nil {
                ActivityCell(mods: [mod]).frame(width: 180)
            } else if let nexusID = model.nexusID(for: mod) {
                Button("Files…") { model.nexusSheet = NexusSheetRequest(modID: nexusID) }
                    .help("Choose a specific file on Nexus")
                Button("Update") {
                    model.queueNexusInstalls([NexusInstallRequest(modID: nexusID, title: mod.displayName, version: update.version)])
                }
                .buttonStyle(.borderedProminent)
            } else if let url = update.url {
                Link("Open Download Page", destination: url)
            }
        }
    }
}
