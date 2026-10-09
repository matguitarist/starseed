import ModManagerCore
import SwiftUI

/// Required dependencies that are missing or disabled, with one-click fixes.
/// Requirements are listed under their Nexus names. IDs that only appear in
/// a mod's files (and match nothing on Nexus) are tucked into their own
/// section, so they don't read like mods that need installing.
struct RequirementsView: View {
    @AppModelEnvironment private var model

    var body: some View {
        let missing = model.missingDependencies
        let confirmed = missing.filter(model.isConfirmed)
        let unlisted = missing.filter { !model.isConfirmed($0) }
        Group {
            if missing.isEmpty {
                ContentUnavailableView(
                    "All Requirements Installed",
                    systemImage: "checkmark.seal",
                    description: Text("Every enabled mod has the framework mods it needs.")
                )
            } else {
                List {
                    if !confirmed.isEmpty {
                        Section {
                            ForEach(confirmed) { RequirementRow(dependency: $0) }
                        }
                    }
                    if model.isResolvingRequirements && !unlisted.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Looking up names on Nexus…").foregroundStyle(.secondary)
                        }
                    } else if !unlisted.isEmpty {
                        Section {
                            DisclosureGroup {
                                ForEach(unlisted) { UnlistedRequirementRow(dependency: $0) }
                            } label: {
                                Text("Not listed on Nexus (\(unlisted.count))")
                            }
                        } footer: {
                            Text("These IDs come from the mods' own files but don't match anything on their Nexus pages. Often they're covered by the requirements above under another name; if SMAPI's log still reports them missing, search for them.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Requirements")
        .navigationSubtitle(confirmed.isEmpty ? "" : "\(confirmed.count) missing")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.installMissingDependencies(confirmed)
                } label: {
                    Label("Install All", systemImage: "square.and.arrow.down.on.square")
                }
                .help("Enable or download every missing requirement")
                .disabled(confirmed.isEmpty)
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
                    Text(record?.name ?? dependency.disabledCopy?.displayName ?? dependency.uniqueID).font(.headline)
                    if let nexusID = record?.nexusID { NexusIDLink(modID: nexusID) }
                }
                Text("Needed by \(model.describeNeeding(dependency.requiredBy))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(model.describeNeedingParts(dependency.requiredBy))
                if dependency.disabledCopy != nil {
                    Text("Installed but disabled").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if let disabled = dependency.disabledCopy {
                Button("Enable") { model.setEnabled([disabled.id], true) }
            } else if let nexusID = record?.nexusID {
                HStack {
                    Button("Details…") { model.nexusSheet = NexusSheetRequest(modID: nexusID) }
                    Button("Install") { model.installMissingDependencies([dependency]) }
                        .buttonStyle(.borderedProminent)
                }
            } else if let page = record?.downloadPage {
                DownloadPageButton(page: page, site: record?.downloadSite, controlSize: .regular)
            }
        }
        .padding(.vertical, 4)
        .help(dependency.uniqueID)
    }
}

/// An ID from a mod's files that matched nothing on Nexus.
private struct UnlistedRequirementRow: View {
    @AppModelEnvironment private var model
    let dependency: MissingDependency

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(dependency.uniqueID).font(.callout.monospaced())
                Text("Needed by \(model.describeNeeding(dependency.requiredBy))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(model.describeNeedingParts(dependency.requiredBy))
            }
            Spacer()
            Button("Search Nexus") {
                let query = dependency.uniqueID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                model.openInBrowser(URL(string: "https://www.nexusmods.com/games/stardewvalley/mods?keyword=\(query)")!)
            }
            .controlSize(.small)
        }
    }
}
