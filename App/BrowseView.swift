import ModManagerCore
import SwiftUI

/// Search and browse Stardew Valley mods on Nexus (public API, no key needed).
struct BrowseView: View {
    @AppModelEnvironment private var model
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var sort = NexusSort.endorsements
    @State private var results: [NexusMod] = []
    @State private var totalCount = 0
    @State private var isLoading = false
    @State private var error: String?

    private struct SearchKey: Equatable {
        let query: String
        let sort: NexusSort
    }

    var body: some View {
        content
            .navigationTitle("Browse Nexus")
            .navigationSubtitle(totalCount > 0 ? "\(totalCount.formatted()) mods" : "")
            .searchable(text: $query, placement: .toolbar, prompt: "Search, or paste a Nexus link or mod #")
            .onSubmit(of: .search) {
                // A pasted link, "#7286" or "7286" opens that mod directly.
                if let modID = NexusClient.modID(fromLinkOrNumber: query) {
                    model.nexusSheet = NexusSheetRequest(modID: modID)
                } else {
                    submittedQuery = query
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Sort", selection: $sort) {
                    ForEach(NexusSort.allCases, id: \.self) { Text($0.localizedTitle) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
            }
            // Debounce typing; submitting with Return searches immediately.
            .task(id: query) {
                // Pasted links open right away; bare numbers wait for Return,
                // since "72" may just be the start of "7286".
                if query.localizedCaseInsensitiveContains("nexusmods.com"),
                   let modID = NexusClient.modID(fromLinkOrNumber: query) {
                    model.nexusSheet = NexusSheetRequest(modID: modID)
                    return
                }
                try? await Task.sleep(for: .milliseconds(450))
                if !Task.isCancelled, NexusClient.modID(fromLinkOrNumber: query) == nil { submittedQuery = query }
            }
            .task(id: SearchKey(query: submittedQuery, sort: sort)) {
                await load(reset: true)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let error, results.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Reach Nexus", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await load(reset: true) } }
            }
        } else if results.isEmpty && !isLoading {
            ContentUnavailableView.search(text: submittedQuery)
        } else {
            List {
                ForEach(results) { mod in
                    Button {
                        model.nexusSheet = NexusSheetRequest(modID: mod.modId, preview: mod)
                    } label: {
                        NexusModRow(mod: mod)
                    }
                    .buttonStyle(.plain)
                }
                if isLoading || results.count < totalCount {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Load More") { Task { await load(reset: false) } }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func load(reset: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await model.nexusClient.searchMods(
                query: submittedQuery,
                sort: sort,
                offset: reset ? 0 : results.count
            )
            guard !Task.isCancelled else { return }
            if reset {
                results = page.mods
            } else {
                let known = Set(results.map(\.id))
                results += page.mods.filter { !known.contains($0.id) }
            }
            totalCount = page.totalCount
            error = nil
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct NexusModRow: View {
    @AppModelEnvironment private var model
    let mod: NexusMod

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: mod.thumbnailURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 112, height: 63)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(mod.name).font(.headline).lineLimit(1)
                    NexusIDLink(modID: mod.modId)
                    InstalledBadge(nexusID: mod.modId)
                }
                if let author = mod.author {
                    Text("by \(author)").font(.caption).foregroundStyle(.secondary)
                }
                if let summary = mod.summary {
                    Text(summary.strippingNexusMarkup)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 12) {
                    if let downloads = mod.downloads {
                        Label(downloads.formatted(.number.notation(.compactName)), systemImage: "arrow.down.circle")
                    }
                    if let endorsements = mod.endorsements {
                        Label(endorsements.formatted(.number.notation(.compactName)), systemImage: "hand.thumbsup")
                    }
                    if let version = mod.version, !version.isEmpty {
                        Text("v\(version)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// "Installed" / "Update" capsule for a Nexus mod that's already in the Mods folder.
struct InstalledBadge: View {
    @AppModelEnvironment private var model
    let nexusID: Int

    var body: some View {
        if let installed = model.installedMod(nexusID: nexusID) {
            if model.isInstalledButOff(nexusID: nexusID) {
                HStack(spacing: 4) {
                    Text("Off in this profile")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                        .foregroundStyle(.secondary)
                        .help("Installed \(installed.version), but turned off in the profile in use")
                    Button("Turn On") { model.turnOn(nexusID: nexusID) }
                        .controlSize(.mini)
                        .help("Turn this mod on and add it to the profile in use")
                }
            } else {
                badge(installed)
            }
        }
    }

    private func badge(_ installed: ModInfo) -> some View {
        Group {
            let hasUpdate = model.update(for: installed) != nil
            Text(hasUpdate ? "Update" : "Installed")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((hasUpdate ? Color.orange : Color.green).opacity(0.2), in: Capsule())
                .foregroundStyle(hasUpdate ? .orange : .green)
                .help(hasUpdate ? "Installed \(installed.version) — a newer version is available" : "Installed \(installed.version)")
        }
    }
}
