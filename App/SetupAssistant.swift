// The setup assistant: shown at first launch (and from the Help menu). It
// finds the game, installs SMAPI, picks the Mods folder, connects Nexus and
// sets a few options. "Skip Setup" uses what it finds, for people who
// already know the app (a reinstall, a new Mac).

import AppKit
import ModManagerCore
import SwiftUI

struct SetupAssistant: View {
    @AppModelEnvironment private var model

    enum Step: Int, CaseIterable {
        case welcome, game, smapi, mods, nexus, options, done
    }

    @State private var step = Step.welcome
    @State private var games: [URL]?
    @State private var game: URL?
    @State private var customModsFolder: URL?
    @State private var pickError: String?
    @State private var latestSMAPI: SemanticVersion?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .game: gameStep
                case .smapi: smapiStep
                case .mods: modsStep
                case .nexus: nexusStep
                case .options: optionsStep
                case .done: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)
            Divider()
            footer
        }
        .frame(width: 640, height: 540)
        .interactiveDismissDisabled()
        .task {
            let found = await Task.detached { GameLocator().installs() }.value
            games = found
            if game == nil {
                // The game of the current Mods folder, else the first found.
                game = found.first { $0 == model.gameFolder } ?? model.gameFolder ?? found.first
            }
        }
        .task { latestSMAPI = try? await SMAPIInstaller.latestRelease().version }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Welcome to Starseed").font(.largeTitle.bold())
            Text("Starseed installs, updates and organizes your Stardew Valley mods. Let's get your game ready for mods: it takes about a minute.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            VStack(alignment: .leading, spacing: 8) {
                bullet("magnifyingglass", "Find your game and its Mods folder")
                bullet("puzzlepiece.extension", "Install SMAPI, the mod loader every mod needs")
                bullet("globe", "Connect your Nexus Mods account to download mods")
            }
            .padding(.top, 4)
            Spacer()
            Button("Already know Starseed? Skip setup") { skip() }
                .buttonStyle(.link)
                .help("Use the game found on this Mac and skip the page tips")
        }
        .frame(maxWidth: .infinity)
    }

    private var gameStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Your Game", "Starseed puts mods next to the game. Pick the copy you play.")
            if let games {
                if games.isEmpty, game == nil {
                    Label("Stardew Valley wasn't found in Steam, GOG Games or Applications.", systemImage: "questionmark.folder")
                        .font(.headline)
                    Text("Install it from Steam, GOG or the App Store, then choose Look Again. If it's somewhere else, choose it.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(gameChoices, id: \.self) { folder in
                            gameRow(folder)
                        }
                    }
                }
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Looking for Stardew Valley…")
                }
            }
            HStack {
                Button("Choose Game…", action: chooseGame)
                Button("Look Again") {
                    games = nil
                    Task {
                        let found = await Task.detached { GameLocator().installs() }.value
                        games = found
                        if game == nil { game = found.first }
                    }
                }
                Spacer()
                Button("My Mods folder is somewhere else…", action: chooseModsFolder)
                    .buttonStyle(.link)
            }
            if let pickError {
                Label(pickError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var smapiStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("SMAPI", "SMAPI is the mod loader: the game only loads mods when it starts through SMAPI. Starseed installs it with SMAPI's official installer.")
            if let game {
                let _ = model.smapiInstallCount  // re-read after an install
                let installed = SMAPIInstallation.detect(modsURL: game.appending(path: "Mods"))
                if let phase = model.smapiInstallPhase {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        switch phase {
                        case .downloading: Text("Downloading SMAPI…")
                        case .installing: Text("Installing SMAPI…")
                        }
                    }
                } else if let installed, installed.version == nil || latestSMAPI == nil || installed.version! >= latestSMAPI! {
                    statusLine(ok: true, installed.version.map { String(localized: "SMAPI \($0.description) is installed.") } ?? String(localized: "SMAPI is installed."))
                    Text("You're ready for mods. Launch the game as usual; Starseed's Play button does it for you.")
                        .foregroundStyle(.secondary)
                } else if let version = installed?.version, let latestSMAPI {
                    statusLine(ok: false, String(localized: "SMAPI \(version.description) is installed; \(latestSMAPI.description) is available."))
                    Button("Update SMAPI") { model.installSMAPI(into: game) }
                        .buttonStyle(.borderedProminent)
                } else {
                    statusLine(ok: false, String(localized: "SMAPI isn't installed yet."))
                    HStack {
                        Button("Install SMAPI") { model.installSMAPI(into: game) }
                            .buttonStyle(.borderedProminent)
                        Button("Download Page") { model.getSMAPI() }
                    }
                    Text("Quit the game first. The installer is downloaded from SMAPI's GitHub page.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if SMAPIInstaller.needsRosetta {
                        Label("SMAPI's installer needs Rosetta. If macOS offers to install it, accept.", systemImage: "info.circle")
                            .font(.callout)
                    }
                }
            } else {
                statusLine(ok: false, String(localized: "Your Mods folder isn't inside a game Starseed found, so it can't install SMAPI for you."))
                Button("Open SMAPI's Download Page") { model.getSMAPI() }
            }
            Text("You can skip this and install SMAPI later from the status bar at the bottom of the window.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var modsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Mods Folder", "Mods live in a folder named Mods next to the game. Starseed manages what's in it; nothing is uploaded anywhere.")
            if let folder = modsFolder {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(folder.path(percentEncoded: false))
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        let count = modCount(in: folder)
                        if let count {
                            statusLine(ok: true, count == 0 ? String(localized: "No mods yet.") : (count == 1 ? String(localized: "1 mod found.") : String(localized: "\(count) mods found.")))
                        } else {
                            statusLine(ok: true, String(localized: "The folder will be created."))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
            } else {
                statusLine(ok: false, String(localized: "Choose your game or your Mods folder."))
            }
            Button("Use a Different Folder…", action: chooseModsFolder)
            Text("Mods you already have stay as they are. Starseed keeps them in profiles: the first one, “Default”, starts with the mods that are on.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var nexusStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Nexus Mods (Optional)", "Most mods come from Nexus Mods. With your account, Starseed can browse and download mods, install collections, and check for updates.")
            SetupNexusKey()
            if model.nexusAccount.user == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Sign in at nexusmods.com (a free account works).")
                    Text("2. Open the API Keys page and copy your **Personal API Key** at the bottom.")
                    Text("3. Paste it above. It's kept in your Keychain.")
                }
                .foregroundStyle(.secondary)
                Link("Open the Nexus API Keys page…", destination: NexusClient.apiKeyPageURL)
            }
            Text("Free accounts download with one click on **Slow download** in Starseed's Nexus browser; Premium accounts download directly. You can do this later in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var optionsStep: some View {
        SetupOptions()
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("You're All Set", "Here's your setup. You can change any of it in Settings, or run this assistant again from the Help menu.")
            VStack(alignment: .leading, spacing: 8) {
                let installed = game.flatMap { SMAPIInstallation.detect(modsURL: $0.appending(path: "Mods")) }
                if let game {
                    statusLine(ok: true, gameDescription(game))
                } else {
                    statusLine(ok: false, String(localized: "Game not found"))
                }
                if let installed {
                    statusLine(ok: true, installed.version.map { String(localized: "SMAPI \($0.description)") } ?? "SMAPI")
                } else {
                    statusLine(ok: false, String(localized: "SMAPI not installed: install it from the status bar before playing with mods"))
                }
                if let folder = model.manager?.modsURL {
                    statusLine(ok: true, String(localized: "Mods folder: \(folder.path(percentEncoded: false))"))
                }
                if let user = model.nexusAccount.user {
                    statusLine(ok: true, String(localized: "Nexus Mods: \(user.name)"))
                } else {
                    statusLine(ok: false, String(localized: "Nexus Mods not connected (optional)"))
                }
            }
            Divider().padding(.vertical, 4)
            Text("Next steps").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                bullet("globe", "Find mods in **Browse Nexus**, or a whole modpack in **Collections**.")
                bullet("square.and.arrow.down", "Or drop downloaded mod archives (.zip) on the window.")
                bullet("play.fill", "Press **Play** to launch the game with your mods.")
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if step != .welcome && step != .done {
                Button("Skip Setup") { skip() }
                    .help("Close the assistant and keep what's set up so far")
            }
            Spacer()
            stepDots
            Spacer()
            if step != .welcome && step != .done {
                Button("Back") { move(-1) }
            }
            Button(continueTitle) { advance() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { item in
                Circle()
                    .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    private var continueTitle: LocalizedStringKey {
        switch step {
        case .welcome: "Get Started"
        case .done: "Start Using Starseed"
        case .nexus where model.nexusAccount.user == nil: "Skip for Now"
        default: "Continue"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .game: game != nil || customModsFolder != nil
        case .smapi: model.smapiInstallPhase == nil
        case .mods: modsFolder != nil
        default: true
        }
    }

    private func advance() {
        switch step {
        case .mods:
            guard let folder = modsFolder else { return }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                return model.show("Couldn't Create the Mods Folder", detail: error.localizedDescription)
            }
            if model.manager?.modsURL.standardizedFileURL != folder.standardizedFileURL {
                model.use(modsFolder: folder)
            }
        case .done:
            finish()
            return
        default: break
        }
        move(1)
    }

    private func move(_ offset: Int) {
        var next = Step(rawValue: step.rawValue + offset) ?? step
        // Without a game there's nothing to install SMAPI into.
        if next == .smapi, game == nil, customModsFolder != nil { next = Step(rawValue: next.rawValue + offset) ?? next }
        step = next
    }

    /// Uses what was found (or picked) and closes. From the welcome page it
    /// also turns the page tips off: that's someone who knows the app.
    private func skip() {
        if step == .welcome {
            UserDefaults.standard.set(false, forKey: Preferences.showPageTips)
        }
        if model.manager == nil, let folder = customModsFolder ?? (game ?? GameLocator().installs().first)?.appending(path: "Mods", directoryHint: .isDirectory) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            model.use(modsFolder: folder)
        }
        finish()
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Preferences.setupCompleted)
        model.showSetupAssistant = false
        model.sidebarSelection = .installed
    }

    // MARK: Helpers

    private var gameChoices: [URL] {
        var list = games ?? []
        if let game, !list.contains(game) { list.append(game) }
        return list
    }

    private var modsFolder: URL? {
        customModsFolder ?? game?.appending(path: "Mods", directoryHint: .isDirectory)
    }

    private func gameRow(_ folder: URL) -> some View {
        Button {
            game = folder
            customModsFolder = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: game == folder ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(game == folder ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gameDescription(folder)).font(.headline)
                    Text(folder.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(game == folder ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    /// "Stardew Valley 1.6.15 · Steam"
    private func gameDescription(_ folder: URL) -> String {
        let version = SMAPIInstallation.gameVersion(in: folder)?.description
        let store = GameStore.detect(gameFolder: folder).displayName
        return (["Stardew Valley", version].compactMap { $0 }.joined(separator: " ")) + (store.map { " · \($0)" } ?? "")
    }

    /// Mods in a folder, or nil when the folder doesn't exist yet.
    private func modCount(in folder: URL) -> Int? {
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return nil }
        if model.manager?.modsURL.standardizedFileURL == folder.standardizedFileURL { return model.mods.count }
        return (try? ModManager(modsURL: folder, archive: model.modArchive).scan().count) ?? 0
    }

    private func chooseGame() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose Stardew Valley (the app, or the folder it's in)")
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(filePath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let folder = GameLocator.gameFolder(fromPicked: url) {
            game = folder
            customModsFolder = nil
            pickError = nil
        } else {
            pickError = String(localized: "That isn't Stardew Valley. Choose “Stardew Valley.app”, or the folder that holds it.")
        }
    }

    private func chooseModsFolder() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Select your Stardew Valley “Mods” folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = modsFolder ?? .homeDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        customModsFolder = url
        // A Mods folder inside a game also gives the game.
        if let folder = GameLocator.gameFolder(fromPicked: url) {
            game = folder
        } else {
            game = nil
        }
        if step == .game { move(1) }
    }

    private func header(_ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold())
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private func bullet(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 20)
        }
    }

    private func statusLine(ok: Bool, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
        }
    }
}

/// The Nexus API key field in the assistant.
private struct SetupNexusKey: View {
    @AppModelEnvironment private var model
    @State private var keyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.nexusAccount.user == nil {
                HStack(spacing: 6) {
                    SecureField("API key", text: $keyDraft, prompt: Text("Paste your personal API key"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Paste") {
                        keyDraft = NSPasteboard.general.string(forType: .string)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        save()
                    }
                    Button("Connect", action: save)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            NexusAccountStatus()
        }
    }

    private func save() {
        let key = keyDraft
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        keyDraft = ""
        Task { await model.setNexusAPIKey(key) }
    }
}

/// A few choices worth making up front; all are in Settings too.
private struct SetupOptions: View {
    @AppStorage(Preferences.backupBeforePlay) private var backupBeforePlay = true
    @AppStorage(Preferences.reportAfterPlaying) private var reportAfterPlaying = true
    @AppStorage(Preferences.autoCheckUpdates) private var autoCheckUpdates = true
    @AppStorage(Preferences.notifyUpdates) private var notifyUpdates = true
    @AppStorage(Preferences.showPageTips) private var showPageTips = true
    @AppStorage(Preferences.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A Few Choices").font(.title.bold())
                Text("These keep your farms safe and your mods current. The defaults suit most players.")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)
            option($backupBeforePlay, "Back up saves before playing when mods changed",
                   "Zips your saves first, so a mod update can't ruin a farm. The last 5 are kept.")
            option($reportAfterPlaying, "Tell me about mod problems after playing",
                   "Reads SMAPI's log when the game closes and points out mods that failed or crashed.")
            option($autoCheckUpdates, "Check for mod updates every few hours", nil)
            option($notifyUpdates, "Notify me about new updates", nil)
            option($showMenuBarIcon, "Show icon in the menu bar",
                   "Play, switch profiles and see updates from the menu bar. Closing the window keeps Starseed there, checking for updates.")
            option($showPageTips, "Show a tip at the top of each page",
                   "A short explanation the first time you open each page. Dismiss each one, or turn them all off.")
        }
    }

    private func option(_ value: Binding<Bool>, _ title: LocalizedStringKey, _ detail: LocalizedStringKey?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: value)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
