import SwiftUI

/// Save/apply/delete named sets of "which mods are enabled".
struct ProfilesView: View {
    @AppModelEnvironment private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Profiles").font(.title2.bold())
                Text("A profile remembers which mods are enabled.")
                    .foregroundStyle(.secondary)
            }

            List(model.profileNames, id: \.self, selection: $selected) { name in
                HStack {
                    Text(name)
                    Spacer()
                    Text("\(model.profiles[name]?.count ?? 0) mods")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 180)
            .overlay {
                if model.profiles.isEmpty {
                    Text("No profiles yet").foregroundStyle(.secondary)
                }
            }
            .onChange(of: selected) { _, name in
                if let name { newName = name }
            }

            HStack {
                TextField("Profile name", text: $newName)
                    .onSubmit(save)
                Button(model.profiles[trimmedName] == nil ? "Save Current" : "Update", action: save)
                    .disabled(trimmedName.isEmpty)
            }

            HStack {
                Button("Delete", role: .destructive) {
                    if let selected { model.deleteProfile(named: selected) }
                    selected = nil
                }
                .disabled(selected == nil)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    if let selected { model.applyProfile(named: selected) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected == nil)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        model.saveProfile(named: trimmedName)
        selected = trimmedName
    }
}
