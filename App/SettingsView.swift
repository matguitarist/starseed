import AppKit
import ModManagerCore
import SwiftUI

struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = "general"  // reopens on the last tab

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            GameSettings()
                .tabItem { Label("Game", systemImage: "gamecontroller") }
                .tag("game")
            UpdatesSettings()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
                .tag("updates")
            NexusSettings()
                .tabItem { Label("Nexus Mods", systemImage: "globe") }
                .tag("nexus")
            StorageSettings()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
                .tag("storage")
        }
        .frame(width: 560, height: 620)
    }
}

/// Light, dark, or whatever macOS uses.
enum AppTheme: String, CaseIterable {
    case system, light, dark

    static var current: AppTheme {
        UserDefaults.standard.string(forKey: Preferences.theme).flatMap(AppTheme.init) ?? .system
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Applies to every window, including Settings and Help.
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

private struct GeneralSettings: View {
    @AppModelEnvironment private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preferences.theme) private var theme = AppTheme.system
    @AppStorage(Preferences.showModPictures) private var showModPictures = true
    @AppStorage(Preferences.showPageTips) private var showPageTips = true
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
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: theme) { _, new in new.apply() }
                Toggle("Show mod pictures from Nexus", isOn: $showModPictures)
                Toggle("Show a tip at the top of each page", isOn: $showPageTips)
            }
            Section {
                Toggle("Show icon in the menu bar", isOn: $showMenuBarIcon)
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("With the menu bar icon, closing the window keeps the app running so it can keep checking. Quit from the icon's menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Setup assistant") {
                    Button("Open…") {
                        openWindow(id: "main")
                        model.showSetupAssistant = true
                    }
                }
                LabeledContent("Page tips") {
                    Button("Show Again") { PageTip.showAgain() }
                }
            } header: {
                Text("Help")
            }
        }
        .formStyle(.grouped)
    }
}

/// The game, SMAPI, the Mods folder, and what happens around playing.
private struct GameSettings: View {
    @AppModelEnvironment private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preferences.backupBeforePlay) private var backupBeforePlay = true
    @AppStorage(Preferences.reportAfterPlaying) private var reportAfterPlaying = true

    var body: some View {
        Form {
            Section("Stardew Valley") {
                LabeledContent("Game") {
                    HStack {
                        if let game = model.gameVersion {
                            Text(model.gameStore?.displayName.map { "\(game.description) · \($0)" } ?? game.description)
                        } else {
                            Text("Not found next to the Mods folder").foregroundStyle(.secondary)
                        }
                        Button("Change…") {
                            openWindow(id: "main")
                            model.showSetupAssistant = true
                        }
                        .help("Opens the setup assistant, which finds Steam, GOG and App Store copies of the game")
                    }
                }
                LabeledContent("SMAPI") {
                    if let smapi = model.smapi {
                        HStack(spacing: 4) {
                            Text(smapi.version?.description ?? String(localized: "Installed (unknown version)"))
                            if model.isSMAPIOutdated, let latest = model.latestSMAPIVersion {
                                Text("· \(latest.description) available").foregroundStyle(.orange)
                            }
                        }
                    } else {
                        Text("Not installed").foregroundStyle(.secondary)
                    }
                }
                if model.smapiNeedsInstall {
                    HStack {
                        Spacer()
                        SMAPIInstallButton()
                    }
                }
                LabeledContent("Mods folder") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(model.manager?.modsURL.path(percentEncoded: false) ?? String(localized: "Not set"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                        HStack {
                            Button("Show in Finder") { model.openModsFolder() }
                                .disabled(model.manager == nil)
                            Button("Change…") { model.chooseModsFolder() }
                        }
                    }
                }
            }
            Section {
                Toggle("Back up saves before playing when mods changed", isOn: $backupBeforePlay)
                Toggle("Tell me about mod problems after playing", isOn: $reportAfterPlaying)
            } header: {
                Text("Playing")
            } footer: {
                Text("Play zips all your saves first if mods were added, removed, updated, or switched on or off since you last played; the last 5 are kept, under Saves. When the game closes, SMAPI's log is checked for mods that didn't load, errors, conflicts and crashes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Mod updates and updates of Starseed itself.
private struct UpdatesSettings: View {
    @AppModelEnvironment private var model
    @AppStorage(Preferences.autoCheckUpdates) private var autoCheckUpdates = true
    @AppStorage(Preferences.notifyUpdates) private var notifyUpdates = true

    var body: some View {
        Form {
            Section("Mods") {
                Toggle("Check for mod updates every few hours", isOn: $autoCheckUpdates)
                Toggle("Notify me about new updates", isOn: $notifyUpdates)
                HStack {
                    Spacer()
                    Button("Check Now") { Task { await model.checkForUpdates() } }
                        .disabled(model.isCheckingUpdates || model.manager == nil)
                }
            }
            Section {
                if AppUpdater.shared.isConfigured {
                    Toggle("Check for new versions of Starseed", isOn: Binding(
                        get: { AppUpdater.shared.automaticallyChecks },
                        set: { AppUpdater.shared.automaticallyChecks = $0 }
                    ))
                }
                LabeledContent("Version") {
                    HStack {
                        Text(verbatim: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                        if AppUpdater.shared.isConfigured {
                            Button("Check Now") { AppUpdater.shared.checkForUpdates() }
                        }
                    }
                }
            } header: {
                Text("Starseed")
            }
        }
        .formStyle(.grouped)
    }
}

private struct NexusSettings: View {
    @AppModelEnvironment private var model
    @State private var keyDraft = ""
    @State private var revealKey = false
    @State private var changingKey = false
    @State private var isDefaultHandler = false

    private static let nxmProbe = URL(string: "nxm://stardewvalley/mods/1/files/1")!

    var body: some View {
        Form {
            Section {
                if model.nexusAccount.user != nil, !changingKey {
                    HStack {
                        accountStatus
                        Spacer()
                        Button("Change Key…") { changingKey = true }
                        Button("Remove", role: .destructive) { model.removeNexusAPIKey() }
                    }
                } else {
                    keyEntry
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

    private var accountStatus: some View {
        NexusAccountStatus()
    }

    /// The key field, shown until a key works (or while changing it).
    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                if changingKey {
                    Button("Cancel") { changingKey = false; keyDraft = "" }
                } else if model.nexusAccount != .none {
                    Button("Remove", role: .destructive) { model.removeNexusAPIKey() }
                }
                Button("Save & Verify", action: save)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }


    private func save() {
        let key = keyDraft
        keyDraft = ""
        changingKey = false
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

/// The Nexus account the API key belongs to (Settings, setup assistant).
struct NexusAccountStatus: View {
    @AppModelEnvironment private var model

    var body: some View {
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
}
