import ModManagerCore
import SwiftUI

/// Required dependencies that are missing or disabled, with one-click fixes.
struct RequirementsView: View {
    @AppModelEnvironment private var model

    var body: some View {
        let missing = model.missingDependencies
        Group {
            if missing.isEmpty {
                ContentUnavailableView(
                    "All Requirements Installed",
                    systemImage: "checkmark.seal",
                    description: Text("Every enabled mod has the framework mods it needs.")
                )
            } else {
                List(missing) { dependency in
                    RequirementRow(dependency: dependency)
                }
            }
        }
        .navigationTitle("Requirements")
        .navigationSubtitle(missing.isEmpty ? "" : "\(missing.count) missing")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.installMissingDependencies(missing)
                } label: {
                    Label("Install All", systemImage: "square.and.arrow.down.on.square")
                }
                .help("Enable or download every missing requirement")
                .disabled(missing.isEmpty)
            }
        }
        .task { await model.resolveMissingDependencies() }
    }
}

private struct RequirementRow: View {
    @AppModelEnvironment private var model
    let dependency: MissingDependency

    var body: some View {
        let record = model.record(forDependency: dependency.uniqueID)
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: dependency.disabledCopy == nil ? "puzzlepiece.extension" : "power")
                .font(.title2)
                .foregroundStyle(dependency.disabledCopy == nil ? .red : .orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record?.name ?? dependency.uniqueID).font(.headline)
                    if let nexusID = record?.nexusID { NexusIDLink(modID: nexusID) }
                    if record?.name != nil {
                        Text(dependency.uniqueID).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Text("Needed by \(model.describeNeeding(dependency.requiredBy))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if dependency.disabledCopy != nil {
                    Text("Installed but disabled").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            action(record: record)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func action(record: SMAPIModRecord?) -> some View {
        if let disabled = dependency.disabledCopy {
            Button("Enable") { model.setEnabled([disabled.id], true) }
        } else if let nexusID = record?.nexusID {
            HStack {
                Button("Details…") { model.nexusSheet = NexusSheetRequest(modID: nexusID) }
                Button("Install") { model.installMissingDependencies([dependency]) }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            Button("Search Nexus") {
                let query = (record?.name ?? dependency.uniqueID).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                model.openInBrowser(URL(string: "https://www.nexusmods.com/games/stardewvalley/mods?keyword=\(query)")!)
            }
        }
    }
}
