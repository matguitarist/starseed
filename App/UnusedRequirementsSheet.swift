import ModManagerCore
import SwiftUI

/// After a deletion: requirements nothing else uses anymore, with checkboxes.
/// An item stays (and is greyed out) while something kept still needs it.
struct UnusedRequirementsSheet: View {
    @AppModelEnvironment private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: AppModel.UnusedRequirementsPrompt
    @State private var unticked: Set<String> = []

    /// Items that can really go: ticked, and only needed by removed mods or
    /// by other items that also go.
    private var removable: [UnusedRequirement] {
        var goingNames = Set(prompt.removedNames)
        var result: [UnusedRequirement] = []
        var changed = true
        while changed {
            changed = false
            for item in prompt.items where !unticked.contains(item.id) && !result.contains(where: { $0.id == item.id }) {
                if item.neededBy.allSatisfy(goingNames.contains) {
                    result.append(item)
                    goingNames.insert(item.mod.displayName)
                    changed = true
                }
            }
        }
        return result
    }

    var body: some View {
        let removableIDs = Set(removable.map(\.id))
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Remove Requirements No Longer Needed?").font(.title2.bold())
                Text("Nothing else you have installed uses these anymore. They were only needed by what you just removed.")
                    .foregroundStyle(.secondary)
            }

            List(prompt.items) { item in
                let isKept = !unticked.contains(item.id) && !removableIDs.contains(item.id)
                HStack(spacing: 10) {
                    Toggle("Remove", isOn: Binding(
                        get: { !unticked.contains(item.id) },
                        set: { if $0 { unticked.remove(item.id) } else { unticked.insert(item.id) } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(item.mod.displayName).font(.headline)
                            Text("v\(item.mod.version)").font(.caption).foregroundStyle(.secondary)
                            if let nexusID = model.nexusID(for: item.mod) { NexusIDLink(modID: nexusID) }
                        }
                        Text(isKept
                             ? "Kept: still needed by \(item.neededBy.joined(separator: ", "))"
                             : "Was needed by \(item.neededBy.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(isKept ? .orange : .secondary)
                    }
                }
                .opacity(isKept ? 0.6 : 1)
            }
            .frame(minHeight: 160)

            Text("They go to the Trash, so you can put them back from Finder.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Keep All") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(removable.count == 1 ? "Move 1 to Trash" : "Move \(removable.count) to Trash") {
                    model.moveToTrash(removable.map(\.mod), suggestUnused: false)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(removable.isEmpty)
            }
        }
        .padding()
        .frame(width: 520, height: 440)
    }
}
