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
                List(model.modsWithUpdates) { mod in
                    if let update = model.update(for: mod) {
                        UpdateRow(mod: mod, update: update)
                    }
                }
            }
        }
        .navigationTitle("Updates")
        .navigationSubtitle(model.modsWithUpdates.isEmpty ? "" : "\(model.modsWithUpdates.count) available")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.updateAll()
                } label: {
                    Label("Update All", systemImage: "square.and.arrow.down.on.square")
                }
                .help(model.nexusAccount.user?.isPremium == true
                      ? "Download and install every Nexus update"
                      : "Walk through each update's Nexus download page")
                .disabled(model.nexusUpdates.isEmpty)
            }
            ToolbarItem {
                if model.isCheckingUpdates {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await model.checkForUpdates() }
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.clockwise")
                    }
                    .help("Check for updates")
                }
            }
        }
    }
}

private struct UpdateRow: View {
    @AppModelEnvironment private var model
    let mod: ModInfo
    let update: ModUpdate

    var body: some View {
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
            if let nexusID = model.nexusID(for: mod) {
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
        .padding(.vertical, 4)
    }
}
