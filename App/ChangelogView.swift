import ModManagerCore
import SwiftUI

extension AppModel {
    func loadChangelog(nexusID: Int) async {
        guard changelogs[nexusID] == nil else { return }
        changelogs[nexusID] = (try? await nexusClient.changelog(forMod: nexusID)) ?? []
    }
}

/// "What's new" between the installed version and an update, from Nexus.
/// Collapsed by default; loads when opened.
struct ChangelogDisclosure: View {
    @AppModelEnvironment private var model
    let nexusID: Int
    let installed: String
    let latest: String
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, 4)
                .task { await model.loadChangelog(nexusID: nexusID) }
        } label: {
            Text("What's New").font(.callout)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let all = model.changelogs[nexusID] {
            let entries = Changelog.entries(all, after: installed, upTo: latest)
            if entries.isEmpty {
                HStack(spacing: 6) {
                    Text("No changelog for this version on Nexus.").foregroundStyle(.secondary)
                    Button("Open Mod Page") {
                        model.openInBrowser(NexusClient.modPageURL(nexusID))
                    }
                    .buttonStyle(.link)
                }
                .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entries, id: \.version) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: entry.version).font(.callout.bold()).monospacedDigit()
                            ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(verbatim: "•").foregroundStyle(.secondary)
                                    Text(verbatim: line).fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.callout)
                            }
                        }
                    }
                }
                .textSelection(.enabled)
            }
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading changelog…").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }
}
