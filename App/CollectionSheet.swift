import ModManagerCore
import SwiftUI

/// A collection's pinned files compared against the Mods folder, with
/// install and save-as-profile actions.
struct CollectionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let request: CollectionSheetRequest
    @State private var revision: CollectionRevision?
    @State private var error: String?
    @State private var selectedOptional: Set<Int> = []   // file IDs of optional mods to include
    @State private var includeNewerDowngrades = false
    @State private var profileSaved: String?

    var body: some View {
        VStack(spacing: 0) {
            header.padding()
            Divider()
            content
            Divider()
            footer.padding()
        }
        .frame(width: 720, height: 680)
        .task { await load() }
    }

    private var collection: NexusCollection? { revision?.collection ?? request.preview }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: collection?.tileImageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(collection?.name ?? "Collection").font(.title2.bold()).lineLimit(2)
                HStack(spacing: 6) {
                    if let author = collection?.author { Text("by \(author)") }
                    if let number = revision?.revisionNumber ?? collection?.latestRevision { Text("· Revision \(number)") }
                }
                .foregroundStyle(.secondary)
                if let summary = collection?.summary {
                    Text(summary.strippingNexusMarkup).font(.callout).lineLimit(3)
                }
                if let collection {
                    CollectionStats(collection: collection)
                    Link("View on Nexus Mods", destination: collection.pageURL).font(.callout)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Mod list

    @ViewBuilder
    private var content: some View {
        if let error {
            ContentUnavailableView("Couldn't Load Collection", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if let revision {
            VStack(spacing: 0) {
                summaryBar(revision)
                List {
                    let required = revision.mods.filter { !$0.isOptional }
                    let optional = revision.mods.filter(\.isOptional)
                    Section("Mods (\(required.count))") {
                        ForEach(required) { modRow($0) }
                    }
                    if !optional.isEmpty {
                        Section("Optional (\(optional.count))") {
                            ForEach(optional) { modRow($0) }
                        }
                    }
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func summaryBar(_ revision: CollectionRevision) -> some View {
        let states = revision.mods.map { model.state(of: $0) }
        let installed = states.filter { $0 == .installed }.count
        let older = states.filter { if case .olderInstalled = $0 { true } else { false } }.count
        let newer = states.filter { if case .newerInstalled = $0 { true } else { false } }.count
        let missing = states.filter { $0 == .missing }.count
        return HStack(spacing: 14) {
            Label("\(installed) installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            if older > 0 { Label("\(older) to update", systemImage: "arrow.up.circle.fill").foregroundStyle(.orange) }
            if missing > 0 { Label("\(missing) missing", systemImage: "arrow.down.circle.fill").foregroundStyle(.blue) }
            if newer > 0 {
                Toggle("Match \(newer) newer installed mods to the collection's versions", isOn: $includeNewerDowngrades)
                    .toggleStyle(.checkbox)
                    .help("By default, mods you already have in a newer version are kept.")
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func modRow(_ mod: CollectionMod) -> some View {
        let state = model.state(of: mod)
        return HStack(spacing: 10) {
            if mod.isOptional {
                Toggle("Include", isOn: Binding(
                    get: { selectedOptional.contains(mod.fileID) },
                    set: { if $0 { selectedOptional.insert(mod.fileID) } else { selectedOptional.remove(mod.fileID) } }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            }
            stateIcon(state)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Button(mod.modName) { model.openInBrowser(NexusClient.modPageURL(mod.modID)) }
                        .buttonStyle(.plain)
                        .font(.headline)
                        .help("Open this mod's Nexus page")
                    NexusIDLink(modID: mod.modID)
                }
                Text([mod.fileName, mod.version.map { "v\($0)" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            stateText(state)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func stateIcon(_ state: AppModel.CollectionModState) -> some View {
        switch state {
        case .installed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .olderInstalled: Image(systemName: "arrow.up.circle.fill").foregroundStyle(.orange)
        case .newerInstalled: Image(systemName: "checkmark.circle").foregroundStyle(.teal)
        case .missing: Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private func stateText(_ state: AppModel.CollectionModState) -> some View {
        switch state {
        case .installed: Text("Installed").foregroundStyle(.secondary)
        case .olderInstalled(let version): Text("You have \(version)").foregroundStyle(.orange)
        case .newerInstalled(let version): Text("You have \(version) (newer)").foregroundStyle(.teal)
        case .missing: Text("Not installed").foregroundStyle(.secondary)
        }
    }

    // MARK: Footer

    /// Files the Install button would download.
    private var modsToInstall: [CollectionMod] {
        guard let revision else { return [] }
        return revision.mods.filter { mod in
            guard !mod.isOptional || selectedOptional.contains(mod.fileID) else { return false }
            switch model.state(of: mod) {
            case .installed: return false
            case .olderInstalled, .missing: return true
            case .newerInstalled: return includeNewerDowngrades
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let profileSaved {
                    Label(profileSaved, systemImage: "checkmark").foregroundStyle(.green)
                } else if model.nexusAccount.user?.isPremium == true {
                    Text("Premium: everything downloads and installs automatically.")
                } else if model.nexusAccount.user != nil {
                    Text("Free account: the Nexus browser opens each mod in turn. Click **Slow download** on each page.")
                } else if model.nexusAccount == .checking {
                    Text("Checking your Nexus account… (macOS may ask to allow Keychain access)")
                } else {
                    Text("Add your Nexus API key in Settings to install collections.")
                }
                let totalKB = modsToInstall.compactMap(\.sizeKB).reduce(0, +)
                if totalKB > 0 {
                    Text("\(modsToInstall.count) mods · \((Int64(totalKB) * 1024).formatted(.byteCount(style: .file)))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            Spacer()
            Button("Save as Profile") {
                guard let revision else { return }
                let count = model.saveProfile(fromCollection: revision)
                profileSaved = "Saved profile “\(revision.collection.name)” (\(count) mods)"
            }
            .disabled(revision == nil)
            .help("Save a profile that enables the collection's installed mods")
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(modsToInstall.isEmpty ? "Up to Date" : "Install \(modsToInstall.count) Mods") {
                model.installCollection(modsToInstall)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(modsToInstall.isEmpty || model.nexusAccount.user == nil)
        }
    }

    private func load() async {
        do {
            revision = try await model.nexusClient.collectionRevision(slug: request.slug, revision: request.revision)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
