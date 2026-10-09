import AppKit
import ModManagerCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            NexusSettings()
                .tabItem { Label("Nexus Mods", systemImage: "globe") }
        }
        .frame(width: 540)
    }
}

private struct GeneralSettings: View {
    @AppModelEnvironment private var model
    @AppStorage(Preferences.autoCheckUpdates) private var autoCheckUpdates = true
    @AppStorage(Preferences.notifyUpdates) private var notifyUpdates = true
    @AppStorage(Preferences.showMenuBarIcon) private var showMenuBarIcon = false
    @State private var language = AppLanguage.current

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $language) {
                    Text("System (\(AppLanguage.systemName))").tag(AppLanguage.system)
                    // Every language the app is translated into, each named in itself.
                    ForEach(AppLanguage.available, id: \.self) { language in
                        Text(verbatim: language.name).tag(language)
                    }
                }
                .onChange(of: language) { _, new in new.apply() }
                if language != AppLanguage.atLaunch {
                    HStack {
                        Text("The new language applies after a restart.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now") { AppLanguage.relaunch() }
                            .disabled(model.activityStatus != nil)
                            .help(model.activityStatus != nil ? "Wait for downloads and checks to finish" : "")
                    }
                }
            }
            Section("Updates") {
                Toggle("Check for mod updates every few hours", isOn: $autoCheckUpdates)
                Toggle("Notify me about new updates", isOn: $notifyUpdates)
                Toggle("Show icon in the menu bar", isOn: $showMenuBarIcon)
                Text("With the menu bar icon, closing the window keeps the app running so it can keep checking. Quit from the icon's menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Mods folder") {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(model.manager?.modsURL.path(percentEncoded: false) ?? "Not set")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                    Button("Change…") { model.chooseModsFolder() }
                }
            }
            LabeledContent("SMAPI") {
                if let smapi = model.smapi {
                    HStack(spacing: 4) {
                        Text(smapi.version?.description ?? "Installed (unknown version)")
                        if model.isSMAPIOutdated, let latest = model.latestSMAPIVersion {
                            Text("· \(latest.description) available").foregroundStyle(.orange)
                        }
                    }
                } else {
                    Text("Not found next to the Mods folder").foregroundStyle(.secondary)
                }
            }
            if let game = model.smapi?.gameVersion {
                LabeledContent("Stardew Valley", value: game.description)
            }
        }
        .formStyle(.grouped)
    }
}

private struct NexusSettings: View {
    @AppModelEnvironment private var model
    @State private var keyDraft = ""
    @State private var revealKey = false
    @State private var isDefaultHandler = false

    private static let nxmProbe = URL(string: "nxm://stardewvalley/mods/1/files/1")!

    var body: some View {
        Form {
            Section {
                // An explicit bordered field: in a grouped Form, a plain
                // SecureField shows only its label and no visible box.
                HStack(spacing: 6) {
                    Group {
                        if revealKey {
                            TextField("API key", text: $keyDraft, prompt: Text("Paste your personal API key"))
                        } else {
                            SecureField("API key", text: $keyDraft, prompt: Text("Paste your personal API key"))
                        }
                    }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                    Button {
                        revealKey.toggle()
                    } label: {
                        Image(systemName: revealKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(revealKey ? "Hide key" : "Show key")
                    Button("Paste") {
                        keyDraft = NSPasteboard.general.string(forType: .string)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    }
                }
                HStack {
                    accountStatus
                    Spacer()
                    if model.nexusAccount != .none {
                        Button("Remove", role: .destructive) { model.removeNexusAPIKey() }
                    }
                    Button("Save & Verify", action: save)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("API Key")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Needed to download mods. Sign in to Nexus, open your account's API Keys page, and copy the “Personal API Key” at the bottom. It's stored in your Keychain.")
                    Link("Open the Nexus API Keys page…", destination: NexusClient.apiKeyPageURL)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let user = model.nexusAccount.user {
                Section("Downloads") {
                    if user.isPremium {
                        Label("Premium: mods download and install directly from the app.", systemImage: "bolt.fill")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Free accounts can't download with the API key alone. Nexus only hands out download links on its website, to a signed-in user.")
                            Text("Sign in once in the app's Nexus browser (the login is remembered). After that, each mod is one click on **Slow download** and installs automatically.")
                                .foregroundStyle(.secondary)
                            Button("Sign In to Nexus…") {
                                model.openInBrowser(NexusClient.signInURL)
                            }
                        }
                    }
                }
            }

            Section {
                if isDefaultHandler {
                    Label("This app opens Nexus “Mod Manager Download” links.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Text("Another app (or none) opens Nexus “Mod Manager Download” links.")
                        Spacer()
                        Button("Use This App") { Task { await makeDefaultHandler() } }
                    }
                }
            } header: {
                Text("Mod Manager Downloads")
            } footer: {
                Text("Links in this app open in its own Nexus browser, which catches these downloads itself. Making this app the default also catches “Mod Manager Download” clicks in Safari or Chrome.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshHandlerStatus)
    }

    @ViewBuilder
    private var accountStatus: some View {
        switch model.nexusAccount {
        case .none:
            Text("Not connected").foregroundStyle(.secondary)
        case .checking:
            ProgressView().controlSize(.small)
        case .signedIn(let user):
            Label(
                user.isPremium ? String(localized: "\(user.name) · Premium") : String(localized: "\(user.name) · Free account"),
                systemImage: "person.crop.circle.badge.checkmark"
            )
            .foregroundStyle(.green)
        case .invalid(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private func save() {
        let key = keyDraft
        keyDraft = ""
        Task { await model.setNexusAPIKey(key) }
    }

    private func refreshHandlerStatus() {
        let handler = NSWorkspace.shared.urlForApplication(toOpen: Self.nxmProbe)
        isDefaultHandler = handler?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    private func makeDefaultHandler() async {
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "nxm")
        } catch {
            model.show("Couldn’t Change Default App", detail: error.localizedDescription)
        }
        refreshHandlerStatus()
    }
}

/// The app's own language, independent of macOS's. Stored as the app's
/// AppleLanguages default, which macOS reads at launch. The choices come
/// from the bundle, so adding a translation adds it here.
struct AppLanguage: Hashable {
    /// A localization code ("fr", "pt-BR"), or nil to follow macOS.
    let code: String?

    static let system = AppLanguage(code: nil)
    private static let key = "AppleLanguages"

    /// The app's translations, sorted by their own names.
    static let available: [AppLanguage] = Set(Bundle.main.localizations)  // can list one twice
        .subtracting(["Base"])
        .map { AppLanguage(code: $0) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    /// "Français", "English", "Deutsch".
    var name: String {
        guard let code else { return "" }
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static var current: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard let stored = (domain?[key] as? [String])?.first else { return .system }
        // "fr-CA" set elsewhere still selects "fr".
        let codes = available.compactMap(\.code)
        guard let match = Bundle.preferredLocalizations(from: codes, forPreferences: [stored]).first,
              codes.contains(match) else { return .system }
        return AppLanguage(code: match)
    }

    /// What this run of the app uses (the setting can change after launch).
    static let atLaunch = current

    /// The language macOS would pick for the app, by name ("Français").
    static var systemName: String {
        let global = UserDefaults(suiteName: UserDefaults.globalDomain)?.stringArray(forKey: key) ?? Locale.preferredLanguages
        let code = Bundle.preferredLocalizations(from: available.compactMap(\.code), forPreferences: global).first ?? "en"
        return AppLanguage(code: code).name
    }

    func apply() {
        if let code {
            UserDefaults.standard.set([code], forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
