import AppKit
import ModManagerCore
import SwiftUI

/// Form editor for a mod's config.json: switches for true/false, fields for
/// numbers and text, nested sections for groups of settings. "Raw JSON"
/// edits the file as text for anything the form can't express.
struct ConfigEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let mod: ModInfo

    @State private var original: JSONValue?
    @State private var value: JSONValue = .object([])
    @State private var hadComments = false
    @State private var loadError: String?
    @State private var rawMode = false
    @State private var rawText = ""
    @State private var saveError: String?

    private var configURL: URL { mod.folderURL.appending(path: "config.json") }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(mod.displayName) Settings").font(.title2.bold())
                    Text("Changes apply the next time you start the game.").foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Mode", selection: $rawMode) {
                    Text("Form").tag(false)
                    Text("Raw JSON").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: rawMode) { _, raw in switchMode(toRaw: raw) }
            }
            .padding()
            Divider()

            if let loadError {
                ContentUnavailableView("Couldn't Read config.json", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if rawMode {
                TextEditor(text: $rawText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
            } else {
                Form {
                    JSONFields(value: $value)
                }
                .formStyle(.grouped)
            }

            Divider()
            HStack(spacing: 10) {
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).lineLimit(2)
                } else if hadComments {
                    Label("This file has comments; saving from the form removes them.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open in Text Editor") { NSWorkspace.shared.open(configURL) }
                Button("Revert") {
                    if let original { value = original; rawText = ConfigJSON.serialize(original) }
                    saveError = nil
                }
                .disabled(!hasChanges)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(loadError != nil || !hasChanges)
            }
            .font(.callout)
            .padding()
        }
        .frame(width: 640, height: 600)
        .onAppear(perform: load)
    }

    private var hasChanges: Bool {
        if rawMode { return rawText != original.map(ConfigJSON.serialize) }
        return value != original
    }

    private func load() {
        do {
            let parsed = try ConfigJSON.parse(Data(contentsOf: configURL))
            original = parsed.value
            value = parsed.value
            hadComments = parsed.hadComments
            rawText = ConfigJSON.serialize(parsed.value)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func switchMode(toRaw raw: Bool) {
        if raw {
            rawText = ConfigJSON.serialize(value)
        } else {
            do {
                value = try ConfigJSON.parse(Data(rawText.utf8)).value
                saveError = nil
            } catch {
                saveError = "Fix the JSON first: \(error.localizedDescription)"
                rawMode = true
            }
        }
    }

    private func save() {
        do {
            let final = rawMode ? try ConfigJSON.parse(Data(rawText.utf8)).value : value
            // Keep the previous file once, in case a setting breaks the mod.
            let backup = mod.folderURL.appending(path: "config.json.bak")
            if let previous = try? Data(contentsOf: configURL) {
                try? previous.write(to: backup)
            }
            try Data(ConfigJSON.serialize(final).utf8).write(to: configURL, options: .atomic)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// Fields for every member of an object (or item of an array), recursively.
private struct JSONFields: View {
    @Binding var value: JSONValue

    var body: some View {
        switch value {
        case .object(let members):
            ForEach(members.indices, id: \.self) { index in
                field(label: Self.humanized(members[index].key), value: Binding(
                    get: { members.indices.contains(index) ? members[index].value : .null },
                    set: { newValue in
                        guard case .object(var current) = value, current.indices.contains(index) else { return }
                        current[index].value = newValue
                        value = .object(current)
                    }
                ))
            }
        case .array(let items):
            ForEach(items.indices, id: \.self) { index in
                field(label: "Item \(index + 1)", value: Binding(
                    get: { items.indices.contains(index) ? items[index] : .null },
                    set: { newValue in
                        guard case .array(var current) = value, current.indices.contains(index) else { return }
                        current[index] = newValue
                        value = .array(current)
                    }
                ))
            }
        default:
            field(label: "Value", value: $value)
        }
    }

    @ViewBuilder
    private func field(label: String, value: Binding<JSONValue>) -> some View {
        switch value.wrappedValue {
        case .bool(let flag):
            Toggle(label, isOn: Binding(get: { flag }, set: { value.wrappedValue = .bool($0) }))
        case .number(let text):
            NumberField(label: label, text: text) { value.wrappedValue = .number($0) }
        case .string(let text):
            TextField(label, text: Binding(get: { text }, set: { value.wrappedValue = .string($0) }))
        case .null:
            LabeledContent(label) { Text("not set").foregroundStyle(.secondary) }
        case .object(let members) where members.isEmpty:
            LabeledContent(label) { Text("empty").foregroundStyle(.secondary) }
        case .array(let items) where items.isEmpty:
            LabeledContent(label) { Text("empty list").foregroundStyle(.secondary) }
        case .object, .array:
            Section(label) {
                JSONFields(value: value)
            }
        }
    }

    /// "EnableAutoSave" -> "Enable Auto Save", "ToggleKey" -> "Toggle Key".
    static func humanized(_ key: String) -> String {
        var out = ""
        let chars = Array(key)
        for (index, char) in chars.enumerated() {
            if index > 0, char.isUppercase, chars[index - 1].isLowercase || chars[index - 1].isNumber {
                out.append(" ")
            }
            out.append(char == "_" ? " " : char)
        }
        return out
    }
}

/// A number field that only commits valid JSON numbers.
private struct NumberField: View {
    let label: String
    let text: String
    let commit: (String) -> Void
    @State private var draft = ""

    var body: some View {
        TextField(label, text: $draft)
            .foregroundStyle(ConfigJSON.isNumber(draft) ? Color.primary : Color.red)
            .monospacedDigit()
            .onAppear { draft = text }
            .onChange(of: draft) { _, new in
                if ConfigJSON.isNumber(new) { commit(new) }
            }
            .onChange(of: text) { _, new in
                if new != draft { draft = new }
            }
    }
}
