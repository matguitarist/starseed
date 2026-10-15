import ModManagerCore
import SwiftUI

/// Save games: which mods each one needs (e.g. a save copied from another
/// computer), and backups to restore all saves or just one.
struct SavesView: View {
    @AppModelEnvironment private var model
    @State private var saves: [SaveGame] = []
    @State private var tab = Tab.mods
    @AppStorage("showProfileSavesOnly") private var showProfileSavesOnly = false

    static let allSavesID = "__all__"

    enum Tab: String, CaseIterable {
        case mods, backups

        var title: String {
            switch self {
            case .mods: String(localized: "Mods", comment: "Saves tab")
            case .backups: String(localized: "Backups", comment: "Saves tab")
            }
        }
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Picker("Show", selection: $showProfileSavesOnly) {
                    Text("All Saves").tag(false)
                    Text("This Profile").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)
                .help("This Profile shows only the saves played with the profile in use")
                Divider()
                List(selection: $model.selectedSaveID) {
                    Label("All Saves & Backups", systemImage: "archivebox")
                        .tag(Self.allSavesID)
                    ForEach(groups, id: \.profile) { group in
                        Section {
                            ForEach(group.saves) { save in
                                saveRow(save).tag(save.id)
                            }
                        } header: {
                            sectionHeader(group.profile)
                        }
                    }
                }
                .overlay {
                    if showProfileSavesOnly, groups.isEmpty, !saves.isEmpty {
                        ContentUnavailableView("No Saves in This Profile", systemImage: "person.2",
                                               description: Text("Saves join a profile when you play them with it, or when you pick it for a save."))
                    }
                }
            }
            .frame(width: 240)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Saves")
        .navigationSubtitle(saves.isEmpty ? "" : (saves.count == 1 ? String(localized: "1 save") : String(localized: "\(saves.count) saves")))
        .onAppear {
            reloadSaves()
            if model.selectedSaveID == nil { model.selectedSaveID = saves.first?.id }
        }
        .onChange(of: model.savesRevision) { reloadSaves() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task {
                        if await model.backUpSaves(saves.map(\.id), label: String(localized: "All saves")) != nil {
                            model.selectedSaveID = Self.allSavesID
                        }
                    }
                } label: {
                    Label("Back Up All Saves", systemImage: "archivebox")
                }
                .help("Back up every save into one backup")
                .disabled(saves.isEmpty)

                Button {
                    NSWorkspace.shared.open(SaveGame.defaultFolder)
                } label: {
                    Label("Open Saves Folder", systemImage: "folder")
                }
                .help("Open the saves folder in Finder")

                RefreshToolbarButton(title: "Refresh", help: "Read the saves folder again", action: reloadSaves)

                PlayToolbarButton(save: saves.first { $0.id == model.selectedSaveID })
            }
        }
    }

    /// Saves by profile: the one in use first, then the others, then saves
    /// without one.
    private var groups: [(profile: String?, saves: [SaveGame])] {
        let links = model.saveLinks.compactMapValues { $0.kind == .profile ? $0.name : nil }
        let byID = Dictionary(saves.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let grouped = ProfileRules.groupedSaves(saves.map(\.id), links: links, order: model.profileNames, active: model.activeProfile)
            .map { (profile: $0.profile, saves: $0.saves.compactMap { byID[$0] }) }
        return showProfileSavesOnly ? grouped.filter { $0.profile != nil && $0.profile == model.activeProfile } : grouped
    }

    @ViewBuilder
    private func sectionHeader(_ profile: String?) -> some View {
        if let profile {
            HStack(spacing: 4) {
                Label(profile, systemImage: "person.2")
                if profile == model.activeProfile {
                    Text("In Use")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .background(.green.opacity(0.2), in: Capsule())
                }
            }
        } else {
            Text("No Profile")
        }
    }

    private func saveRow(_ save: SaveGame) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(save.farmName.isEmpty ? save.id : "\(save.farmName) Farm").font(.headline)
            Text(save.farmerName).foregroundStyle(.secondary)
            Text([save.dateText, save.gameVersion.map { "v\($0)" }].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var detail: some View {
        if model.selectedSaveID == Self.allSavesID {
            BackupsView(save: nil, saves: saves, onRestore: reloadSaves)
        } else if let save = saves.first(where: { $0.id == model.selectedSaveID }) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Picker("View", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.title) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer()
                    SaveModSetPicker(save: save)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()
                switch tab {
                case .mods:
                    SaveAnalysisView(save: save).id(save.id)
                case .backups:
                    BackupsView(save: save, saves: saves, onRestore: reloadSaves).id(save.id)
                }
            }
        } else {
            ContentUnavailableView(
                saves.isEmpty ? "No Saves Found" : "Select a Save",
                systemImage: "externaldrive",
                description: Text(saves.isEmpty
                    ? "Saves live in ~/.config/StardewValley/Saves."
                    : "See which mods a save needs, or back it up and restore it.")
            )
        }
    }

    private func reloadSaves() {
        saves = SaveGame.list()
    }
}

/// Backups containing one save (restore just that save) or all backups
/// (restore everything in a backup, or pick one save from it).
private struct BackupsView: View {
    @AppModelEnvironment private var model
    let save: SaveGame?
    let saves: [SaveGame]
    let onRestore: () -> Void

    @State private var backups: [SaveBackup] = []
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var pendingRestore: (backup: SaveBackup, ids: [String]?)?
    @State private var pendingDelete: SaveBackup?
    @State private var restoredMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if backups.isEmpty {
                ContentUnavailableView(
                    "No Backups Yet",
                    systemImage: "archivebox",
                    description: Text(save == nil ? "Back up all saves to create a restore point." : "Back up this save to create a restore point.")
                )
            } else {
                List(backups) { backup in
                    row(backup)
                }
            }
        }
        .task { await reload() }
        .confirmationDialog(
            restoreTitle,
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Restore") {
                guard let pending = pendingRestore else { return }
                Task { await restore(pending.backup, ids: pending.ids) }
            }
        } message: {
            Text("The current version is backed up first (“Before restore”) and moved to the Trash, so you can undo this. If Steam Cloud reports a conflict the next time you play, keep the local files.")
        }
        .confirmationDialog(
            "Delete this backup?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                guard let backup = pendingDelete else { return }
                do { try model.backupStore.delete(backup) } catch { model.show("Couldn’t Delete Backup", detail: error.localizedDescription) }
                Task { await reload() }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(save.map { "Backups of \($0.farmName) Farm" } ?? "All Saves & Backups").font(.title2.bold())
                if let restoredMessage {
                    Label(restoredMessage, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if model.isGameRunning {
                    Label("Stardew Valley is running. Quit it before restoring.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text("Includes SMAPI's automatic daily backups.").foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isWorking { ProgressView().controlSize(.small) }
            Button(save == nil ? "Back Up All Saves" : "Back Up Now") {
                Task {
                    isWorking = true
                    defer { isWorking = false }
                    let ids = save.map { [$0.id] } ?? saves.map(\.id)
                    let label = save.map { "\($0.farmName) Farm" } ?? "All saves"
                    if await model.backUpSaves(ids, label: label) != nil { await reload() }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || (save == nil && saves.isEmpty))
        }
        .padding()
    }

    private func row(_ backup: SaveBackup) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: backup.isSMAPIBackup ? "clock.arrow.circlepath" : "archivebox.fill")
                .foregroundStyle(backup.isSMAPIBackup ? Color.secondary : Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(backup.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                    Text(backup.isSMAPIBackup ? "SMAPI daily backup" : backup.label)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Text(backup.saveIDs.map { backup.saveNames[$0] ?? $0 }.joined(separator: ", "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(backup.byteCount.formatted(.byteCount(style: .file)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let save {
                Button("Restore") { pendingRestore = (backup, [save.id]) }
            } else {
                if backup.saveIDs.count > 1 {
                    Menu("Restore One") {
                        ForEach(backup.saveIDs, id: \.self) { id in
                            Button(backup.saveNames[id] ?? id) { pendingRestore = (backup, [id]) }
                        }
                    }
                    .fixedSize()
                }
                Button(backup.saveIDs.count > 1 ? "Restore All" : "Restore") { pendingRestore = (backup, nil) }
            }
            Menu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([backup.url]) }
                if !backup.isSMAPIBackup {
                    Button("Move to Trash…", role: .destructive) { pendingDelete = backup }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 3)
    }

    private var restoreTitle: String {
        guard let pending = pendingRestore else { return "" }
        let ids = pending.ids ?? pending.backup.saveIDs
        let names = ids.map { pending.backup.saveNames[$0] ?? $0 }
        let when = pending.backup.date.formatted(date: .abbreviated, time: .shortened)
        return names.count == 1 ? String(localized: "Restore \(names[0]) from \(when)?") : String(localized: "Restore \(names.count) saves from \(when)?")
    }

    private func restore(_ backup: SaveBackup, ids: [String]?) async {
        isWorking = true
        defer { isWorking = false }
        if await model.restoreSaves(from: backup, ids: ids) {
            let count = (ids ?? backup.saveIDs).count
            restoredMessage = count == 1 ? String(localized: "Restored. The previous version is in “Before restore”.") : String(localized: "Restored \(count) saves. The previous versions are in “Before restore”.")
            onRestore()
            await reload()
        }
    }

    private func reload() async {
        let all = await model.backupStore.list()
        backups = save.map { save in all.filter { $0.saveIDs.contains(save.id) } } ?? all
        isLoading = false
    }
}

private struct SaveAnalysisView: View {
    @AppModelEnvironment private var model
    let save: SaveGame

    @State private var analysis: AppModel.SaveAnalysis?
    @State private var error: String?
    @State private var selected: Set<Int> = []   // Nexus mod IDs ticked for install
    @State private var status = String(localized: "Scanning the save…")
    @State private var editingRow: String?        // row whose match is being changed
    @State private var linkDraft = ""
    @State private var linkError: String?

    var body: some View {
        Group {
            if let analysis {
                content(analysis)
            } else if let error {
                ContentUnavailableView("Couldn't Read Save", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(status)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await run() }
    }

    private func run() async {
        do {
            let result = try await model.analyze(save) { status = $0 }
            analysis = result
            // Pre-tick the confident matches that aren't installed yet.
            selected = Set(missingMatches(result).filter { $0.confidence >= .byAuthor || isGroupNameMatch($0, in: result) }.map(\.modID))
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Content

    private func content(_ analysis: AppModel.SaveAnalysis) -> some View {
        let missing = missingMatches(analysis)
        return VStack(spacing: 0) {
            header(analysis, missingCount: missing.count)
            Divider()
            List {
                if !analysis.mods.isEmpty {
                    Section {
                        ForEach(analysis.mods) { use in
                            modRow(use)
                        }
                    } header: {
                        Text("Mods this save uses")
                    } footer: {
                        Text("Found from IDs stored in the save file.")
                    }
                }

                if analysis.logCoversSave {
                    if !analysis.gaps.isEmpty {
                        Section {
                            ForEach(analysis.gaps) { gap in
                                gapRow(gap)
                            }
                        } header: {
                            Text("Missing content (from your last game session)")
                        } footer: {
                            Text("Locations and NPCs the game dropped when loading this save, grouped by their probable mod. Matches come from a Nexus search, so check them before installing.")
                        }
                    }
                } else {
                    Section {
                        Label("Load this save once with SMAPI, then come back: SMAPI's log lists every location and NPC from mods you don't have, which finds even more missing mods.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                if !analysis.unmatchedIDs.isEmpty {
                    Section {
                        DisclosureGroup("\(analysis.unmatchedIDs.count) other IDs in the save didn't match a mod") {
                            Text(analysis.unmatchedIDs.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func header(_ analysis: AppModel.SaveAnalysis, missingCount: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(save.farmName) Farm").font(.title2.bold())
                Text([save.farmerName, save.dateText, save.lastSaved.map { "saved \($0.formatted(date: .abbreviated, time: .shortened))" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if missingCount == 0 {
                Label("Everything this save needs is installed", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Text("\(missingCount) missing").foregroundStyle(.orange)
                Button("Install \(selected.count) Selected") {
                    model.installMatches(missingMatches(analysis).filter { selected.contains($0.modID) })
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || model.nexusAccount.user == nil)
                .help(model.nexusAccount.user == nil ? "Add your Nexus API key in Settings first" : "Download and install the ticked mods")
            }
        }
        .padding()
    }

    // MARK: Rows

    private func modRow(_ use: AppModel.SaveModUse) -> some View {
        HStack(spacing: 10) {
            if let match = use.match, use.installed == nil {
                checkbox(match.modID)
            }
            statusIcon(installed: use.installed)
            VStack(alignment: .leading, spacing: 1) {
                Text(use.installed?.displayName ?? use.match?.name ?? use.uniqueID).font(.headline)
                HStack(spacing: 6) {
                    Text(use.uniqueID)
                    if let match = use.match, use.installed == nil {
                        NexusIDLink(modID: match.modID)
                        ConfidenceBadge(confidence: match.confidence)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if use.installed == nil {
                changeButton(rowID: "id:" + use.id, hasMatch: use.match != nil)
            }
            trailing(installed: use.installed, match: use.match)
        }
    }

    private func gapRow(_ gap: AppModel.SaveContentGap) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let match = gap.match, gap.installed == nil {
                checkbox(match.modID)
            }
            statusIcon(installed: gap.installed)
            VStack(alignment: .leading, spacing: 2) {
                Text(gap.group.key).font(.headline)
                Text(locationSummary(gap.group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(gap.group.locations.joined(separator: "\n"))
                if let match = gap.match {
                    HStack(spacing: 6) {
                        Text("\(match.confidence == .chosen ? "Using" : "Likely"): \(match.name)").font(.callout)
                        NexusIDLink(modID: match.modID)
                        if match.matchedTerm != gap.group.key {
                            Text("(found via “\(match.matchedTerm)”)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No match found on Nexus").font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if gap.installed == nil {
                changeButton(rowID: "gap:" + gap.id, hasMatch: gap.match != nil)
            }
            if gap.match == nil {
                Button("Search Nexus") {
                    let query = gap.group.searchTerms.first?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    model.openInBrowser(URL(string: "https://www.nexusmods.com/games/stardewvalley/mods?keyword=\(query)")!)
                }
            } else {
                trailing(installed: gap.installed, match: gap.match)
            }
        }
    }

    /// Lets the user replace a match by pasting the right Nexus link or mod number.
    private func changeButton(rowID: String, hasMatch: Bool) -> some View {
        Button(hasMatch ? "Change…" : "Set Mod…") {
            linkDraft = ""
            linkError = nil
            editingRow = rowID
        }
        .help("Paste the right Nexus link (e.g. nexusmods.com/stardewvalley/mods/7286) or mod number")
        .popover(isPresented: Binding(get: { editingRow == rowID }, set: { if !$0 { editingRow = nil } })) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Which Nexus mod is it?").font(.headline)
                TextField("https://www.nexusmods.com/stardewvalley/mods/7286", text: $linkDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 360)
                    .onSubmit { Task { await applyLink(to: rowID) } }
                if let linkError {
                    Text(linkError).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button("Paste") { linkDraft = NSPasteboard.general.string(forType: .string) ?? "" }
                    Spacer()
                    Button("Cancel") { editingRow = nil }
                    Button("Use This Mod") { Task { await applyLink(to: rowID) } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(NexusClient.modID(fromLinkOrNumber: linkDraft) == nil)
                }
            }
            .padding()
        }
    }

    private func applyLink(to rowID: String) async {
        guard let modID = NexusClient.modID(fromLinkOrNumber: linkDraft) else {
            linkError = String(localized: "That isn't a Stardew Valley mod link or number.")
            return
        }
        let name: String
        do {
            name = try await model.nexusClient.mod(id: modID).name
        } catch {
            linkError = String(localized: "Couldn't find mod #\(String(modID)) on Nexus.")
            return
        }
        let match = ModMatch(modID: modID, name: name, author: nil, confidence: .chosen, matchedTerm: linkDraft)
        let installed = model.installedMod(nexusID: modID)
        guard var analysis else { return }
        if rowID.hasPrefix("id:"), let index = analysis.mods.firstIndex(where: { "id:" + $0.id == rowID }) {
            if let old = analysis.mods[index].match { selected.remove(old.modID) }
            analysis.mods[index].match = match
            analysis.mods[index].installed = installed
        } else if rowID.hasPrefix("gap:"), let index = analysis.gaps.firstIndex(where: { "gap:" + $0.id == rowID }) {
            if let old = analysis.gaps[index].match { selected.remove(old.modID) }
            analysis.gaps[index].match = match
            analysis.gaps[index].installed = installed
        }
        if installed == nil { selected.insert(modID) }
        self.analysis = analysis
        editingRow = nil
    }

    private func locationSummary(_ group: MissingContentGroup) -> String {
        let locations = group.locations.count == 1 ? String(localized: "1 location") : String(localized: "\(group.locations.count) locations")
        guard !group.npcs.isEmpty else { return locations }
        let npcs = group.npcs.prefix(6).joined(separator: ", ") + (group.npcs.count > 6 ? "…" : "")
        return locations + " · " + String(localized: "NPCs: \(npcs)")
    }

    private func checkbox(_ modID: Int) -> some View {
        Toggle("Install", isOn: Binding(
            get: { selected.contains(modID) },
            set: { if $0 { selected.insert(modID) } else { selected.remove(modID) } }
        ))
        .labelsHidden()
        .toggleStyle(.checkbox)
    }

    @ViewBuilder
    private func statusIcon(installed: ModInfo?) -> some View {
        if let installed {
            Image(systemName: installed.isEnabled ? "checkmark.circle.fill" : "power.circle.fill")
                .foregroundStyle(installed.isEnabled ? .green : .orange)
                .help(installed.isEnabled ? "Installed" : "Installed but disabled")
        } else {
            Image(systemName: "arrow.down.circle").foregroundStyle(.blue).help("Not installed")
        }
    }

    @ViewBuilder
    private func trailing(installed: ModInfo?, match: ModMatch?) -> some View {
        if let installed {
            if installed.isEnabled {
                Text("Installed").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Enable") { model.setEnabled([installed.id], true) }
            }
        } else if let match {
            Button("Details…") { model.nexusSheet = NexusSheetRequest(modID: match.modID) }
        }
    }

    // MARK: Helpers

    /// Matched, not-installed mods across both sections (deduplicated).
    private func missingMatches(_ analysis: AppModel.SaveAnalysis) -> [ModMatch] {
        var seen = Set<Int>()
        let fromIDs = analysis.mods.filter { $0.installed == nil }.compactMap(\.match)
        let fromGaps = analysis.gaps.filter { $0.installed == nil }.compactMap(\.match)
        return (fromIDs + fromGaps).filter { seen.insert($0.modID).inserted && !model.isInstalled(nexusID: $0.modID) }
    }

    /// A gap matched by its own name ("Ridgeside"), not just an NPC name.
    private func isGroupNameMatch(_ match: ModMatch, in analysis: AppModel.SaveAnalysis) -> Bool {
        analysis.gaps.contains { $0.match?.modID == match.modID && $0.match?.matchedTerm == $0.group.key }
    }
}

private struct ConfidenceBadge: View {
    let confidence: ModMatch.Confidence

    var body: some View {
        let (text, color): (String, Color) = switch confidence {
        case .confirmed: (String(localized: "SMAPI database"), .green)
        case .byAuthor: (String(localized: "matched by author"), .teal)
        case .byName: (String(localized: "possible match"), .orange)
        case .chosen: (String(localized: "your choice"), .blue)
        }
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Picks the profile a save is played with.
private struct SaveModSetPicker: View {
    @AppModelEnvironment private var model
    let save: SaveGame

    var body: some View {
        let current = model.saveLinks[save.id]
        Menu {
            Section("Profiles") {
                ForEach(model.profileNames, id: \.self) { name in
                    Button {
                        model.link(saveID: save.id, to: SaveModSet(kind: .profile, name: name))
                    } label: {
                        if current?.name == name { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
            }
            Divider()
            Button("No Profile (keep the mods that are on)") { model.link(saveID: save.id, to: nil) }
        } label: {
            if let current {
                Label(current.name, systemImage: "person.2")
                    .foregroundStyle(model.exists(current) ? Color.primary : Color.red)
            } else {
                Label("No Profile", systemImage: "person.2.slash")
            }
        }
        .fixedSize()
        .help("The profile this save is played with. Play switches to it before launching. Saves you play join the profile in use.")
    }
}
