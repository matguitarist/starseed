import ModManagerCore
import SwiftUI

/// Saved lists of mods: snapshot what's installed, export/import as .json,
/// install what's missing from Nexus, or switch to exactly that set.
struct MyCollectionsView: View {
    @AppModelEnvironment private var model
    @State private var selection: String?
    @State private var isNaming = false
    @State private var newName = ""

    var body: some View {
        HStack(spacing: 0) {
            List(model.modLists, selection: $selection) { list in
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name).font(.headline)
                    Text("\(list.mods.count) mods · \(list.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
                .tag(list.id)
            }
            .frame(width: 230)
            .overlay {
                if model.modLists.isEmpty {
                    Text("No collections yet").foregroundStyle(.secondary)
                }
            }
            Divider()
            if let list = model.modLists.first(where: { $0.id == selection }) {
                ModListDetail(list: list, onDelete: { selection = nil })
                    .id(list.id)
            } else {
                ContentUnavailableView {
                    Label("My Collections", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Save your installed mods as a list, export it, and import it on another Mac (or share it with a friend) to install the same mods.")
                } actions: {
                    Button("Save Current Mods…") { startNaming() }
                        .buttonStyle(.borderedProminent)
                    Button("Import…") { importList() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("My Collections")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    startNaming()
                } label: {
                    Label("Save Current Mods", systemImage: "plus.rectangle.on.rectangle")
                }
                .help("Save the installed mods as a new collection")
                Button {
                    importList()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import a collection file (.json)")
            }
        }
        .alert("Save Current Mods", isPresented: $isNaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                if let list = model.saveCurrentMods(as: newName) { selection = list.id }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the \(model.mods.filter { !$0.uniqueID.lowercased().hasPrefix("smapi.") && !$0.uniqueID.isEmpty }.count) installed mods, their versions, Nexus numbers and settings. A collection with the same name is replaced.")
        }
        .onAppear {
            model.loadModLists()
            if selection == nil { selection = model.modLists.first?.id }
        }
    }

    private func startNaming() {
        newName = String(localized: "My Mods \(Date.now.formatted(date: .abbreviated, time: .omitted))")
        isNaming = true
    }

    private func importList() {
        if let list = model.importModList() { selection = list.id }
    }
}

private struct ModListDetail: View {
    @AppModelEnvironment private var model
    let list: ModList
    let onDelete: () -> Void

    @State private var confirmApply = false
    @State private var confirmDelete = false
    @State private var confirmSettings = false

    var body: some View {
        let states = list.mods.map { ModListEntryState.of($0, in: model.mods) }
        let missing = states.filter { $0 == .missing }.count
        let older = states.filter { if case .olderInstalled = $0 { true } else { false } }.count
        let disabled = states.filter { $0 == .disabled }.count

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name).font(.title2.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Label("\(states.count - missing - older) installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        if older > 0 { Label("\(older) older here", systemImage: "arrow.up.circle.fill").foregroundStyle(.orange) }
                        if missing > 0 { Label("\(missing) missing", systemImage: "arrow.down.circle.fill").foregroundStyle(.blue) }
                        if disabled > 0 { Label("\(disabled) disabled", systemImage: "power.circle").foregroundStyle(.secondary) }
                    }
                    .font(.callout)
                    if list.settingsCount > 0 {
                        let changed = list.settingsChanges(for: model.mods).count
                        HStack(spacing: 8) {
                            Label(changed == 0 ? String(localized: "Settings for \(list.settingsCount) mods, same as yours")
                                  : String(localized: "Settings for \(list.settingsCount) mods, \(changed) different from yours"),
                                  systemImage: "slider.horizontal.3")
                                .foregroundStyle(.secondary)
                            if changed > 0 {
                                Button("Apply Settings…") { confirmSettings = true }
                                    .controlSize(.small)
                            }
                        }
                        .font(.callout)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    HStack {
                        Button("Export…") { model.exportModList(list) }
                        Button("Delete…", role: .destructive) { confirmDelete = true }
                    }
                    HStack {
                        Button("Use This Set…") { confirmApply = true }
                            .help("Enable exactly the mods this collection had enabled, and disable the rest")
                        Button(missing + older > 0 ? "Install \(missing + older) Mods" : "All Installed") {
                            model.installMissing(from: list)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(missing + older == 0 || model.nexusAccount.user == nil)
                        .help(model.nexusAccount.user == nil ? "Add your Nexus API key in Settings first" : "Download missing and older mods from Nexus")
                    }
                }
            }
            .padding()
            Divider()
            List(Array(zip(list.mods, states)), id: \.0.id) { entry, state in
                row(entry, state)
            }
        }
        .confirmationDialog("Use “\(list.name)”?", isPresented: $confirmApply, titleVisibility: .visible) {
            Button("Enable These Mods") { model.apply(list) }
        } message: {
            Text("Mods this collection had enabled are turned on and every other mod is turned off. Nothing is deleted.")
        }
        .confirmationDialog("Use this collection's mod settings?", isPresented: $confirmSettings, titleVisibility: .visible) {
            Button("Apply Settings") { model.applySettings(from: list) }
        } message: {
            Text("The settings of \(list.settingsChanges(for: model.mods).map(\.mod.displayName).formatted(.list(type: .and))) are replaced by the ones saved in “\(list.name)”. Each mod's current settings are kept as config.json.bak.")
        }
        .confirmationDialog("Delete “\(list.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                model.deleteModList(list)
                onDelete()
            }
        } message: {
            Text("Only the collection is deleted, not the mods.")
        }
    }

    private var subtitle: String {
        var parts = [
            String(localized: "\(list.mods.count) mods"),
            String(localized: "saved \(list.createdAt.formatted(date: .abbreviated, time: .shortened))"),
        ]
        if let game = list.gameVersion { parts.append("Stardew \(game)") }
        if let smapi = list.smapiVersion { parts.append("SMAPI \(smapi)") }
        return parts.joined(separator: " · ")
    }

    private func row(_ entry: ModListEntry, _ state: ModListEntryState) -> some View {
        HStack(spacing: 10) {
            switch state {
            case .installed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .disabled: Image(systemName: "power.circle.fill").foregroundStyle(.orange)
            case .olderInstalled: Image(systemName: "arrow.up.circle.fill").foregroundStyle(.orange)
            case .newerInstalled: Image(systemName: "checkmark.circle").foregroundStyle(.teal)
            case .missing: Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.headline)
                    if let nexusID = entry.nexusID { NexusIDLink(modID: nexusID) }
                    if !entry.enabled {
                        Text("disabled in collection").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text([entry.uniqueID, "v\(entry.version)", entry.author.map { "by \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Group {
                switch state {
                case .installed: Text("Installed")
                case .disabled: Text("Installed, disabled")
                case .olderInstalled(let version): Text("You have \(version)").foregroundStyle(.orange)
                case .newerInstalled(let version): Text("You have \(version) (newer)").foregroundStyle(.teal)
                case .missing: Text("Not installed")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
