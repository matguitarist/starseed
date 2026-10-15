import ModManagerCore
import SwiftUI

/// A collection's pinned files compared against the Mods folder, with
/// install and save-as-profile actions.
struct CollectionSheet: View {
    @AppModelEnvironment private var model
    @Environment(\.dismiss) private var dismiss

    let request: CollectionSheetRequest
    @State private var revision: CollectionRevision?
    @State private var error: String?
    @State private var selectedOptional: Set<Int> = []   // file IDs of optional mods to include
    @State private var includeNewerDowngrades = false
    /// Install into a new profile named after the collection (only its mods
    /// on), or into the profile in use.
    @State private var intoNewProfile = true

    var body: some View {
        VStack(spacing: 0) {
            header.padding()
            Divider()
            content
            Divider()
            VStack(spacing: 8) {
                profileChoice
                footer
            }
            .padding()
        }
        .frame(width: 720, height: 680)
        .task { await load() }
        .onChange(of: collection?.name, initial: true) { _, name in
            if let name, model.activeProfile == name { intoNewProfile = false }
        }
    }

    private var collection: NexusCollection? { revision?.collection ?? request.preview }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            FittedPicture(url: collection?.tileImageURL, cornerRadius: 10)
                .frame(width: 110, height: 138)

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
        // Counts cover the mods that would be used: required ones and the
        // optional ones you ticked. A newer version you have counts as installed.
        let used = revision.mods.filter { !$0.isOptional || selectedOptional.contains($0.fileID) }
        let states = used.map { model.state(of: $0) }
        let newerStates = used.filter { $0.modID != NexusClient.smapiModID }.map { model.state(of: $0) }
        let installed = states.filter { if case .installed = $0 { true } else if case .newerInstalled = $0 { true } else { false } }.count
        let older = states.filter { if case .olderInstalled = $0 { true } else { false } }.count
        let newer = newerStates.filter { if case .newerInstalled = $0 { true } else { false } }.count
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
            if state != .missing, mod.modID != NexusClient.smapiModID, model.isInstalledButOff(nexusID: mod.modID) {
                Text("Off in this profile").foregroundStyle(.secondary).font(.caption)
                Button("Turn On") { model.turnOn(nexusID: mod.modID) }
                    .controlSize(.small)
                    .help("Turn this mod on and add it to the profile in use")
            } else {
                stateText(state)
                    .font(.caption)
            }
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
            if mod.modID == NexusClient.smapiModID { return false }  // installed with its own installer
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
                if model.nexusAccount.user?.isPremium == true {
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
                    Text(modsToInstall.count == 1 ? String(localized: "1 mod · \((Int64(totalKB) * 1024).formatted(.byteCount(style: .file)))") : String(localized: "\(modsToInstall.count) mods · \((Int64(totalKB) * 1024).formatted(.byteCount(style: .file)))"))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(installTitle) {
                if intoNewProfile, let revision {
                    model.useCollectionProfile(revision, mods: includedMods)
                }
                model.installCollection(modsToInstall + (smapiRowNeedingInstall.map { [$0] } ?? []))
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(revision == nil
                      || (modsToInstall.isEmpty && smapiRowNeedingInstall == nil && !intoNewProfile)
                      || (!modsToInstall.isEmpty && model.nexusAccount.user == nil))
        }
    }

    /// "Install into: New profile “X” | Profile in use “Default”".
    @ViewBuilder
    private var profileChoice: some View {
        let name = collection?.name ?? ""
        HStack(spacing: 8) {
            if model.activeProfile == name {
                // Its own profile is in use: just install into it.
                Label("Installs into the profile in use “\(name)”", systemImage: "person.2")
                    .foregroundStyle(.secondary)
            } else {
                Text("Install into").foregroundStyle(.secondary)
                Picker("Install into", selection: $intoNewProfile) {
                    Text(model.profiles[name] == nil ? String(localized: "New profile “\(name)”") : String(localized: "Profile “\(name)”")).tag(true)
                    Text("Profile in use “\(model.activeProfile ?? "")”").tag(false)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            Spacer()
        }
        .font(.callout)
        .help("A new profile has only this collection's mods on, so it doesn't mix with your other mods. Mods you already have aren't downloaded again.")
    }

    /// The collection's mods, with the optional ones you ticked.
    private var includedMods: [CollectionMod] {
        (revision?.mods ?? []).filter { !$0.isOptional || selectedOptional.contains($0.fileID) }
    }

    /// The collection's SMAPI entry when SMAPI is missing or older than it
    /// wants (installed with SMAPI's own installer, not as a mod).
    private var smapiRowNeedingInstall: CollectionMod? {
        guard let row = revision?.mods.first(where: { $0.modID == NexusClient.smapiModID }) else { return nil }
        switch model.state(of: row) {
        case .missing, .olderInstalled: return row
        case .installed, .newerInstalled: return nil
        }
    }

    private var installTitle: String {
        if modsToInstall.isEmpty {
            if smapiRowNeedingInstall != nil { return model.smapi == nil ? String(localized: "Install SMAPI") : String(localized: "Update SMAPI") }
            return intoNewProfile ? String(localized: "Use as Profile") : String(localized: "Up to Date")
        }
        return modsToInstall.count == 1 ? String(localized: "Install 1 Mod") : String(localized: "Install \(modsToInstall.count) Mods")
    }

    private func load() async {
        do {
            revision = try await model.nexusClient.collectionRevision(slug: request.slug, revision: request.revision)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
