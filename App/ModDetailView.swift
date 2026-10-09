import ModManagerCore
import SwiftUI

struct ModDetailView: View {
    @AppModelEnvironment private var model
    @State private var editingConfig: ModInfo?

    var body: some View {
        Group {
            if let mod = model.singleSelectedMod {
                details(for: mod)
            } else if let group = model.selectedGroup {
                GroupDetailView(group: group)
            } else {
                ContentUnavailableView(
                    model.selection.isEmpty ? "No Mod Selected" : "\(model.selection.count) Mods Selected",
                    systemImage: "puzzlepiece.extension"
                )
            }
        }
        .sheet(item: $editingConfig) { mod in
            ConfigEditorView(mod: mod)
        }
    }

    private func details(for mod: ModInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mod.displayName)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                    Label(mod.status.title, systemImage: "circle.fill")
                        .font(.callout)
                        .foregroundStyle(mod.status.color)
                    if let update = model.update(for: mod) {
                        HStack {
                            Label("Version \(update.version) available", systemImage: "arrow.down.circle.fill")
                                .foregroundStyle(.orange)
                            Spacer()
                            if let nexusID = model.nexusID(for: mod) {
                                Button("Update…") { model.nexusSheet = NexusSheetRequest(modID: nexusID) }
                            } else if let url = update.url {
                                Link("Download Page", destination: url)
                            }
                        }
                        .font(.callout)
                        .padding(8)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                    if let error = mod.parseError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    row("Version", mod.version)
                    row("Author", mod.author)
                    if !mod.uniqueID.isEmpty { row("Unique ID", mod.uniqueID) }
                    if let minimum = mod.minimumApiVersion { row("Needs SMAPI", String(localized: "\(minimum) or later")) }
                    if let nexusID = model.nexusID(for: mod) {
                        GridRow {
                            Text("Nexus").foregroundStyle(.secondary)
                            NexusIDLink(modID: nexusID)
                        }
                    }
                }

                if let nexusID = model.nexusID(for: mod) {
                    EndorseTrackButtons(modID: nexusID, version: mod.version)
                }

                if !mod.description.isEmpty {
                    Text(mod.description)
                        .textSelection(.enabled)
                }

                if mod.contentPackFor != nil || !mod.dependencies.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Requires").font(.headline)
                        if let framework = mod.contentPackFor {
                            dependencyRow(framework, of: mod, required: true, note: String(localized: "content pack for"))
                        }
                        ForEach(mod.dependencies, id: \.uniqueID) { dep in
                            dependencyRow(dep.uniqueID, of: mod, required: dep.isRequired, note: dep.isRequired ? nil : String(localized: "optional"))
                        }
                    }
                }

                if let nexusID = model.nexusID(for: mod) {
                    optionalFilesSection(for: mod, nexusID: nexusID)
                }

                previousVersions(for: mod)

                Text(mod.folderURL.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                // Two rows: three buttons don't fit the inspector's width.
                VStack(alignment: .leading, spacing: 8) {
                    if FileManager.default.fileExists(atPath: mod.folderURL.appending(path: "config.json").path(percentEncoded: false)) {
                        Button {
                            editingConfig = mod
                        } label: {
                            Label("Mod Settings…", systemImage: "slider.horizontal.3")
                        }
                        .help("Edit this mod's config.json")
                    }
                    HStack {
                        Button("Show in Finder") { model.revealInFinder([mod]) }
                        Spacer()
                        Button("Move to Trash…", role: .destructive) { model.pendingTrash = [mod] }
                    }
                    if let nexusID = model.nexusID(for: mod) {
                        Button("All Nexus Files…") { model.nexusSheet = NexusSheetRequest(modID: nexusID) }
                            .help("Every file on this mod's Nexus page: main, optional, updates and old versions")
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Versions replaced by updates, kept so a bad update can be undone.
    @ViewBuilder
    private func previousVersions(for mod: ModInfo) -> some View {
        let versions = model.archivedVersions(of: mod)
        if !versions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Previous Versions").font(.headline)
                ForEach(versions) { version in
                    HStack {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("v\(version.version)")
                            Text("replaced \(version.date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Revert") { model.revert(mod, to: version) }
                            .controlSize(.small)
                            .help("Put v\(version.version) back. The current version is kept here, and your settings carry over.")
                    }
                }
            }
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func dependencyRow(_ uniqueID: String, of mod: ModInfo, required: Bool, note: String?) -> some View {
        let present = model.enabledIDs.contains(uniqueID.lowercased())
        let installedButOff = model.mods.contains { !$0.isEnabled && $0.uniqueID.caseInsensitiveCompare(uniqueID) == .orderedSame }
        let record = model.record(forDependency: uniqueID)
        let icon = present ? "checkmark.circle.fill" : (required ? "xmark.circle.fill" : "circle.dashed")
        let color: Color = present ? .green : (required ? .red : .secondary)
        return HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(record?.name ?? uniqueID).textSelection(.enabled)
                    if let nexusID = record?.nexusID { NexusIDLink(modID: nexusID) }
                }
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if !present {
                Button(installedButOff ? "Enable" : "Install") { model.installDependency(uniqueID, of: mod) }
                    .controlSize(.small)
                    .help(installedButOff ? "It's installed but disabled" : "Download it from Nexus")
            }
        }
        .help(present ? "Installed and enabled" : (required ? "Missing or disabled" : "Not installed (optional)"))
    }

    /// Optional files from the mod's Nexus page (add-ons, compatibility
    /// patches, alternate versions), installable from here.
    @ViewBuilder
    private func optionalFilesSection(for mod: ModInfo, nexusID: Int) -> some View {
        let files = model.optionalFiles(for: mod)
        VStack(alignment: .leading, spacing: 6) {
            if model.nexusFiles[nexusID] == nil {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking Nexus for optional files…").font(.caption).foregroundStyle(.secondary)
                }
            } else if !files.isEmpty {
                Text("Optional Files on Nexus").font(.headline)
                ForEach(files) { file in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "plus.square.on.square").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.name)
                            Text([file.version.map { "v\($0)" }, file.byteCount.map { $0.formatted(.byteCount(style: .file)) }]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let description = file.description?.strippingNexusMarkup, !description.isEmpty {
                                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 4)
                        optionalFileButton(file, mod: mod, nexusID: nexusID)
                    }
                }
            }
        }
        .task(id: nexusID) { await model.loadNexusFiles(for: nexusID) }
    }

    @ViewBuilder
    private func optionalFileButton(_ file: NexusFile, mod: ModInfo, nexusID: Int) -> some View {
        if model.nexusAccount.user?.isPremium == true {
            Button("Install") {
                model.downloadAndInstall(modID: nexusID, fileID: file.fileId, title: "\(mod.displayName) – \(file.name)")
            }
            .controlSize(.small)
        } else {
            Button("Download…") {
                model.openInBrowser(NexusClient.modManagerDownloadPageURL(modID: nexusID, fileID: file.fileId))
            }
            .controlSize(.small)
            .help("Opens the Nexus download page. Click “Slow download” and it installs automatically.")
        }
    }
}

/// Details for a group of parts (a multi-folder mod, or a folder in Mods).
private struct GroupDetailView: View {
    @AppModelEnvironment private var model
    let group: ModGroup

    /// Required mods any part is missing, under their Nexus names. IDs that
    /// match nothing on Nexus are only counted (see Requirements).
    @ViewBuilder
    private var missingRequirements: some View {
        var seen = Set<String>()
        let missing = group.mods.flatMap { part in part.missingDependencies.map { (id: $0, part: part) } }
            .filter { seen.insert($0.id.lowercased()).inserted }
        let confirmed = missing.filter { model.record(forDependency: $0.id)?.nexusID != nil }
        let unlisted = missing.count - confirmed.count
        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Missing Requirements").font(.headline)
                ForEach(confirmed, id: \.id) { item in
                    let record = model.record(forDependency: item.id)
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text(record?.name ?? item.id)
                        if let nexusID = record?.nexusID { NexusIDLink(modID: nexusID) }
                        Spacer(minLength: 4)
                        Button("Install") { model.installDependency(item.id, of: item.part) }
                            .controlSize(.small)
                    }
                    .help(item.id)
                }
                if model.isResolvingRequirements && unlisted > 0 {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Looking up names on Nexus…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if unlisted > 0 {
                    Button(unlisted == 1 ? "1 more not listed on Nexus…" : "\(unlisted) more not listed on Nexus…") {
                        model.sidebarSelection = .requirements
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .task { await model.resolveMissingDependencies() }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(group.name, systemImage: group.isFolder ? "folder.fill" : "square.stack.3d.up.fill")
                        .font(.title2.bold())
                    Text(group.isFolder
                         ? "A folder inside Mods with \(group.mods.count) mods. SMAPI loads every mod in it."
                         : "\(group.mods.count) parts of one mod. Enable or disable them together.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(group.mods) { mod in
                        HStack(spacing: 8) {
                            Toggle("Enabled", isOn: Binding(get: { mod.isEnabled }, set: { model.setEnabled([mod.id], $0) }))
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 0) {
                                Text(mod.displayName)
                                Text("\(mod.relativePath) · v\(mod.version)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(mod.status.title).font(.caption).foregroundStyle(mod.status.color)
                        }
                    }
                }

                missingRequirements

                if let nexusID = group.mods.lazy.compactMap({ model.nexusID(for: $0) }).first {
                    HStack {
                        Text("Nexus").foregroundStyle(.secondary)
                        NexusIDLink(modID: nexusID)
                    }
                    EndorseTrackButtons(modID: nexusID, version: group.mods.first?.version)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Enable All") { model.setEnabled(Set(group.mods.map(\.id)), true) }
                        Button("Disable All") { model.setEnabled(Set(group.mods.map(\.id)), false) }
                    }
                    HStack {
                        Button("Show in Finder") { model.revealInFinder(group.mods) }
                        Spacer()
                        Button("Move to Trash…", role: .destructive) { model.pendingTrash = group.mods }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
