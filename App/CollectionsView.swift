import ModManagerCore
import SwiftUI

/// Browse and search Stardew Valley collections on Nexus.
struct CollectionsView: View {
    @AppModelEnvironment private var model
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var sort = CollectionSort.endorsements
    @State private var results: [NexusCollection] = []
    @State private var totalCount = 0
    @State private var isLoading = false
    @State private var error: String?

    private struct SearchKey: Equatable {
        let query: String
        let sort: CollectionSort
    }

    var body: some View {
        content
            .navigationTitle("Collections")
            .navigationSubtitle(totalCount > 0 ? "\(totalCount.formatted()) collections" : "")
            .searchable(text: $query, placement: .toolbar, prompt: "Search collections")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { PlayToolbarButton() }
            }
            .onSubmit(of: .search) { submittedQuery = query }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Sort", selection: $sort) {
                    ForEach(CollectionSort.allCases, id: \.self) { Text($0.localizedTitle) }
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
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(450))
                if !Task.isCancelled { submittedQuery = query }
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
                ForEach(results) { collection in
                    Button {
                        model.collectionSheet = CollectionSheetRequest(slug: collection.slug, preview: collection)
                    } label: {
                        CollectionRow(collection: collection)
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
            let page = try await model.nexusClient.searchCollections(
                query: submittedQuery,
                sort: sort,
                offset: reset ? 0 : results.count
            )
            guard !Task.isCancelled else { return }
            if reset {
                results = page.collections
            } else {
                let known = Set(results.map(\.id))
                results += page.collections.filter { !known.contains($0.id) }
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

private struct CollectionRow: View {
    let collection: NexusCollection

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: collection.tileImageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(collection.name).font(.headline).lineLimit(1)
                if let author = collection.author {
                    Text("by \(author)").font(.caption).foregroundStyle(.secondary)
                }
                if let summary = collection.summary {
                    Text(summary.strippingNexusMarkup)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                CollectionStats(collection: collection)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct CollectionStats: View {
    let collection: NexusCollection

    var body: some View {
        HStack(spacing: 12) {
            if let count = collection.modCount {
                Label("\(count) mods", systemImage: "square.stack.3d.up")
            }
            if let size = collection.totalSize {
                Label(size.formatted(.byteCount(style: .file)), systemImage: "internaldrive")
            }
            if let endorsements = collection.endorsements {
                Label(endorsements.formatted(.number.notation(.compactName)), systemImage: "hand.thumbsup")
            }
            if let downloads = collection.totalDownloads {
                Label(downloads.formatted(.number.notation(.compactName)), systemImage: "arrow.down.circle")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
