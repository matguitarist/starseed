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
                    if name == model.activeProfile {
                        Text("In Use")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.2), in: Capsule())
                    }
                    Text("\(model.profiles[name]?.count ?? 0) mods")
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
                Spacer()
                Button("Switch To") { if let selected { switchTo(selected) } }
                    .disabled(selected == nil || selected == model.activeProfile)
                    .help("Turn this profile's mods on and the others off")
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("New profile from the mods on now").font(.headline)
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
        model.createProfile(named: trimmedName)
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

/// The toolbar's profile switcher: shows the profile in use.
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
            Button("Manage Profiles…") { model.showProfiles = true }
        } label: {
            Label(model.activeProfile ?? String(localized: "Profiles"), systemImage: "person.2")
                .labelStyle(.titleAndIcon)
        }
        .help("Profile in use. Choose another to switch which mods are on.")
        .disabled(model.manager == nil)
    }
}
