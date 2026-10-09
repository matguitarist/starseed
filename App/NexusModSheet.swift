import ModManagerCore
import SwiftUI

/// A Nexus mod's details and files, with install/download actions.
struct NexusModSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let request: NexusSheetRequest
    @State private var mod: NexusMod?
    @State private var files: [NexusFile] = []
    @State private var requirements: [NexusRequirement] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showOldFiles = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding()
            Divider()
            fileList
            Divider()
            footer
                .padding()
        }
        .frame(width: 680, height: 620)
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: mod?.pictureURL ?? mod?.thumbnailURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 176, height: 99)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(mod?.name ?? "Nexus mod \(request.modID)")
                        .font(.title2.bold())
                        .lineLimit(2)
                    InstalledBadge(nexusID: request.modID)
                }
                if let author = mod?.author {
                    Text("by \(author)").foregroundStyle(.secondary)
                }
                if let summary = mod?.summary {
                    Text(summary.strippingNexusMarkup)
                        .font(.callout)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    NexusIDLink(modID: request.modID)
                    Link("View on Nexus Mods", destination: NexusClient.modPageURL(request.modID))
                        .font(.callout)
                    EndorseTrackButtons(modID: request.modID, version: model.installedMod(nexusID: request.modID)?.version)
                }
                if !requirements.isEmpty {
                    requirementsList
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Requirements

    private var missingRequirements: [NexusRequirement] {
        requirements.filter { requirement in
            requirement.modID.map { !model.isInstalled(nexusID: $0) } ?? false
        }
    }

    private var requirementsList: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Requires").font(.subheadline.bold())
                if !missingRequirements.isEmpty {
                    Button("Install \(missingRequirements.count) Missing") {
                        model.queueNexusInstalls(missingRequirements.compactMap { requirement in
                            requirement.modID.map { NexusInstallRequest(modID: $0, title: requirement.name, version: nil) }
                        })
                    }
                    .controlSize(.small)
                }
            }
            ForEach(requirements) { requirement in
                HStack(spacing: 5) {
                    if let modID = requirement.modID {
                        let installed = model.isInstalled(nexusID: modID)
                        Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(installed ? .green : .red)
                        Button(requirement.name) { model.nexusSheet = NexusSheetRequest(modID: modID) }
                            .buttonStyle(.link)
                        NexusIDLink(modID: modID)
                    } else {
                        Image(systemName: "link.circle").foregroundStyle(.secondary)
                        if let url = requirement.externalURL {
                            Link(requirement.name, destination: url)
                        } else {
                            Text(requirement.name)
                        }
                    }
                    if let notes = requirement.notes {
                        Text("· \(notes)").foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .font(.callout)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Files

    private var visibleFiles: [NexusFile] {
        showOldFiles ? files : files.filter(\.isCurrent)
    }

    private var fileSections: [(title: String, files: [NexusFile])] {
        Dictionary(grouping: visibleFiles, by: \.category)
            .map { ($0.value[0].categoryTitle, $0.value, $0.value[0].categoryOrder) }
            .sorted { $0.2 < $1.2 }
            .map { ($0.0, $0.1) }
    }

    @ViewBuilder
    private var fileList: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            ContentUnavailableView("Couldn't Load Files", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if visibleFiles.isEmpty {
            ContentUnavailableView("No Files", systemImage: "doc", description: Text("This mod has no downloadable files."))
        } else {
            List {
                ForEach(fileSections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.files) { file in
                            fileRow(file)
                        }
                    }
                }
                if files.contains(where: { !$0.isCurrent }) {
                    Toggle("Show old versions", isOn: $showOldFiles)
                        .toggleStyle(.checkbox)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func fileRow(_ file: NexusFile) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.headline)
                Text(fileDetails(file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let description = file.description?.strippingNexusMarkup, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer()
            fileAction(file)
        }
        .padding(.vertical, 3)
    }

    private func fileDetails(_ file: NexusFile) -> String {
        var parts: [String] = []
        if let version = file.version, !version.isEmpty { parts.append("v\(version)") }
        if let bytes = file.byteCount { parts.append(bytes.formatted(.byteCount(style: .file))) }
        parts.append(file.uploadedAt.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func fileAction(_ file: NexusFile) -> some View {
        if model.nexusAccount.user?.isPremium == true {
            Button("Install") {
                model.downloadAndInstall(
                    modID: request.modID,
                    fileID: file.fileId,
                    title: mod.map { "\($0.name) – \(file.name)" } ?? file.name
                )
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button("Download…") {
                openURL(NexusClient.modManagerDownloadPageURL(modID: request.modID, fileID: file.fileId))
                dismiss()
            }
            .help("Opens the Nexus download page. Click “Slow download” and the file installs automatically.")
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .center) {
            accountNote
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var accountNote: some View {
        switch model.nexusAccount {
        case .signedIn(let user) where user.isPremium:
            Label("Premium: files install directly.", systemImage: "bolt.fill")
        case .signedIn:
            Text("Free account: **Download…** opens Nexus in the app's browser (sign in there the first time). Click **Slow download** and the mod installs automatically.")
        case .checking:
            Text("Checking your Nexus account… (macOS may ask to allow Keychain access)")
        case .none, .invalid:
            HStack(spacing: 6) {
                Text("Add your Nexus API key to install mods.")
                SettingsLink { Text("Open Settings…") }
            }
        }
    }

    private func load() async {
        mod = request.preview
        isLoading = true
        defer { isLoading = false }
        let client = model.nexusClient
        Task { requirements = (try? await client.requirements(forMod: request.modID)) ?? [] }
        do {
            async let loadedFiles = client.files(forMod: request.modID)
            if mod == nil {
                mod = try? await client.mod(id: request.modID)
            }
            files = try await loadedFiles
        } catch {
            self.error = error.localizedDescription
        }
    }
}
