import ModManagerCore
import SwiftUI

/// Profiles: named sets of enabled mods. One is always in use, and turning
/// mods on or off updates it; switching turns another set on.
struct ProfilesView: View {
    @AppModelEnvironment private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    @State private var newName = ""
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var confirmDelete = false
    @State private var startEmpty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Profiles").font(.title2.bold())
                Text("Each profile remembers which mods are on. Changes you make are saved to the profile in use; switching turns another set of mods on. Nothing is deleted.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            List(model.profileNames, id: \.self, selection: $selected) { name in
                HStack(spacing: 8) {
                    Image(systemName: name == model.activeProfile ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(name == model.activeProfile ? Color.green : Color.secondary)
                    if renaming == name {
                        TextField("Profile name", text: $renameText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(commitRename)
                            .onExitCommand { renaming = nil }
                    } else {
                        Text(name).fontWeight(name == model.activeProfile ? .semibold : .regular)
                    }
                    Spacer()
                    if model.profileCollections[name] != nil {
                        Button {
                            // One sheet at a time: close Profiles, then open the collection.
                            dismiss()
                            Task {
                                try? await Task.sleep(for: .milliseconds(350))
                                model.showCollection(forProfile: name)
                            }
                        } label: {
                            Label("Collection", systemImage: "square.grid.2x2")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help("Open the Nexus collection this profile was made from, to add its optional mods")
                    }
                    if name == model.activeProfile {
                        Text("In Use")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.2), in: Capsule())
                    }
                    let count = model.profiles[name]?.count ?? 0
                    Text(count == 1 ? String(localized: "1 mod") : String(localized: "\(count) mods"))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { switchTo(name) }
            }
            .frame(minHeight: 200)

            HStack {
                Button("Rename") {
                    renaming = selected
                    renameText = selected ?? ""
                }
                .disabled(selected == nil)
                Button("Delete…", role: .destructive) { confirmDelete = true }
                    .disabled(selected == nil)
                Button("Export…") { if let selected { model.exportProfile(named: selected) } }
                    .disabled(selected == nil)
                    .help("Save this profile to a file (mods, versions, settings) to share it or use it on another Mac")
                Button("Import…") {
                    model.importProfile()
                    selected = model.activeProfile
                }
                .help("Add a profile from a file exported from Starseed; missing mods download into it")
                Spacer()
                Button("Switch To") { if let selected { switchTo(selected) } }
                    .disabled(selected == nil || selected == model.activeProfile)
                    .help("Turn this profile's mods on and the others off")
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("New profile").font(.headline)
                Picker("Start with", selection: $startEmpty) {
                    Text("The mods on now").tag(false)
                    Text("No mods").tag(true)
                }
                .pickerStyle(.segmented)
                if startEmpty {
                    Text("Only SMAPI's own mods (Console Commands, Save Backup) stay on. Every other mod is turned off, not deleted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    TextField("Profile name", text: $newName)
                        .onSubmit(create)
                    Button("Create", action: create)
                        .disabled(trimmedName.isEmpty || model.profiles[trimmedName] != nil)
                }
                if model.profiles[trimmedName] != nil {
                    Text("A profile with this name already exists.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 440)
        .onAppear { selected = model.activeProfile }
        .confirmationDialog("Delete “\(selected ?? "")”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let selected { model.deleteProfile(named: selected) }
                selected = model.activeProfile
            }
        } message: {
            Text("Only the profile is deleted, not the mods.")
        }
    }

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func switchTo(_ name: String) {
        model.switchProfile(to: name)
        selected = name
    }

    private func create() {
        guard !trimmedName.isEmpty, model.profiles[trimmedName] == nil else { return }
        model.createProfile(named: trimmedName, empty: startEmpty)
        selected = trimmedName
        newName = ""
    }

    private func commitRename() {
        if let old = renaming { model.renameProfile(old, to: renameText) }
        let renamed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.profiles[renamed] != nil { selected = renamed }
        renaming = nil
    }
}

/// The profile switcher in the Installed filter bar: shows the profile in use.
struct ProfileMenu: View {
    @AppModelEnvironment private var model

    var body: some View {
        Menu {
            ForEach(model.profileNames, id: \.self) { name in
                Button {
                    model.switchProfile(to: name)
                } label: {
                    if name == model.activeProfile {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
            Divider()
            Button("Show Profile Details") {
                model.selection = []
                model.showInspector = true
            }
            if let active = model.activeProfile, let collection = model.profileCollections[active] {
                Button("Show Collection “\(collection.name)”…") { model.showCollection(forProfile: active) }
            }
            Button("Manage Profiles…") { model.showProfiles = true }
        } label: {
            Label(model.activeProfile ?? String(localized: "Profiles"), systemImage: "person.2")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Profile in use. Choose another to switch which mods are on.")
        .disabled(model.manager == nil)
    }
}

/// The details panel when no mod is selected: the profile in use, and the
/// Nexus collection it came from (with a way back to its optional mods).
struct ProfileOverview: View {
    @AppModelEnvironment private var model
    /// Read once, and again after a session links saves (not on every redraw).
    @State private var saves: [SaveGame] = []

    var body: some View {
        let name = model.activeProfile ?? ""
        let count = model.profiles[name]?.count ?? 0
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile in use").font(.caption).foregroundStyle(.secondary)
                    Label(name, systemImage: "person.2.fill").font(.title2.bold())
                    Text("\(model.mods.filter(\.isEnabled).count) of \(model.mods.count) installed mods are on")
                        .foregroundStyle(.secondary)
                    if count > model.mods.filter(\.isEnabled).count {
                        Text("Some mods in this profile aren't installed.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if let link = model.profileCollections[name] {
                    collectionCard(link)
                }

                savesCard(profile: name)

                HStack {
                    Button("Manage Profiles…") { model.showProfiles = true }
                }
                Text("Select a mod to see its details.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .task(id: model.savesRevision) {
            saves = await Task.detached { SaveGame.list() }.value
        }
        .task(id: model.profileCollections[name]?.slug) {
            guard let slug = model.profileCollections[name]?.slug, model.collectionRevisions[slug] == nil,
                  let revision = try? await model.nexusClient.collectionRevision(slug: slug)
            else { return }
            model.collectionRevisions[slug] = revision
        }
    }

    /// The farms played with this profile; clicking one opens it in Saves.
    @ViewBuilder
    private func savesCard(profile: String) -> some View {
        let saves = saves.filter { model.profile(forSave: $0.id) == profile }
        if !saves.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Saves").font(.caption).foregroundStyle(.secondary)
                ForEach(saves) { save in
                    Button {
                        model.showSave(id: save.id)
                    } label: {
                        Label(save.displayName, systemImage: "house")
                    }
                    .buttonStyle(.link)
                    .help(save.localizedDate.map { String(localized: "\(save.farmerName) · \($0)") } ?? save.farmerName)
                }
            }
        }
    }

    @ViewBuilder
    private func collectionCard(_ link: ProfileCollection) -> some View {
        let revision = model.collectionRevisions[link.slug]
        VStack(alignment: .leading, spacing: 8) {
            Text("Made from the collection").font(.caption).foregroundStyle(.secondary)
            if let url = revision?.collection.tileImageURL {
                ShapedPicture(url: url)
            }
            Text(link.name).font(.headline)
            if let author = revision?.collection.author {
                Text("by \(author)").font(.callout).foregroundStyle(.secondary)
            }
            if let summary = revision?.collection.summary, !summary.isEmpty {
                Text(summary.strippingNexusMarkup)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let revision {
                let required = revision.mods.filter { !$0.isOptional }
                let optional = revision.mods.filter(\.isOptional)
                let have = required.filter { model.state(of: $0) != .missing }.count
                let haveOptional = optional.filter { model.state(of: $0) != .missing }.count
                VStack(alignment: .leading, spacing: 2) {
                    Label("\(have) of \(required.count) mods installed", systemImage: have == required.count ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(have == required.count ? .green : .blue)
                    if !optional.isEmpty {
                        Label("\(haveOptional) of \(optional.count) optional mods installed", systemImage: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            } else {
                ProgressView().controlSize(.small)
            }
            HStack {
                Button("Show Collection…") { model.showCollection(forProfile: model.activeProfile ?? "") }
                    .buttonStyle(.borderedProminent)
                    .help("Install missing or optional mods from this collection")
                if let page = revision?.collection.pageURL {
                    Button("View on Nexus") { model.openInBrowser(page) }
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
