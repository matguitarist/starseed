// The Help window (Help → Starseed Help): short, task-based topics. Every
// paragraph is a String Catalog key, so it's translated like the rest of
// the app; **bold** marks the names of buttons and sections.

import ModManagerCore
import SwiftUI

enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, installing, managing, updates, requirements, profiles, saves, problems, log, settings, troubleshooting, shortcuts

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .gettingStarted: "Getting Started"
        case .installing: "Installing Mods"
        case .managing: "Managing Your Mods"
        case .updates: "Updates"
        case .requirements: "Requirements"
        case .profiles: "Profiles & Collections"
        case .saves: "Saves & Backups"
        case .problems: "When Something Breaks"
        case .log: "SMAPI Log"
        case .settings: "Settings & Storage"
        case .troubleshooting: "Troubleshooting"
        case .shortcuts: "Keyboard Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .gettingStarted: "flag"
        case .installing: "square.and.arrow.down"
        case .managing: "square.stack.3d.up"
        case .updates: "arrow.down.circle"
        case .requirements: "puzzlepiece.extension"
        case .profiles: "person.2"
        case .saves: "archivebox"
        case .problems: "bandage"
        case .log: "doc.text.magnifyingglass"
        case .settings: "gearshape"
        case .troubleshooting: "wrench.and.screwdriver"
        case .shortcuts: "keyboard"
        }
    }
}

struct HelpView: View {
    static let windowID = "help"
    @State private var selection: HelpTopic? = .gettingStarted

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.icon).tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)  // room for German and Spanish titles
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let topic = selection ?? .gettingStarted
                    Label(topic.title, systemImage: topic.icon)
                        .font(.largeTitle.bold())
                        .padding(.bottom, 4)
                    content(for: topic)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .id(selection)  // start each topic at the top
        }
        .navigationTitle("Starseed Help")
    }

    @ViewBuilder
    private func content(for topic: HelpTopic) -> some View {
        switch topic {
        case .gettingStarted:
            HelpText("Starseed installs, updates and organizes Stardew Valley mods. Mods run through **SMAPI**, the mod loader for Stardew Valley, so SMAPI needs to be installed first.")
            HelpSection("1. Install SMAPI") {
                HelpText("Click **Install SMAPI** in the orange banner: Starseed downloads SMAPI's official installer and runs it for your game. When a new SMAPI comes out, or a game update disconnects it, the same banner offers to update or reinstall it.")
            }
            HelpSection("2. Choose your Mods folder") {
                HelpText("On first launch, pick the game's **Mods** folder. For the Steam version it's inside the game: *Stardew Valley.app/Contents/MacOS/Mods*. You can change it later in **Settings → General**.")
            }
            HelpSection("3. Add your Nexus Mods API key") {
                HelpText("To download from Nexus Mods inside the app, paste your personal API key in **Settings → Nexus Mods** (**Open the Nexus API Keys page…** takes you there). The key is kept in your Keychain.")
                HelpText("Free Nexus accounts download through Nexus's own page: click **Slow download** once per mod, and Starseed installs the file when it arrives. Premium accounts download directly.")
            }
            HelpSection("4. Play") {
                HelpText("**Play** in the toolbar starts the game through Steam, with SMAPI. If your mods changed since you last played, your saves are backed up first.")
            }

        case .installing:
            HelpSection("From files you downloaded") {
                HelpText("Drop .zip, .7z or .rar archives (or mod folders) on the window, or use **Install Mods…** (⌘O). An archive can hold several mods; each one goes into the Mods folder, and an older copy is replaced, keeping its settings.")
            }
            HelpSection("From Nexus Mods") {
                HelpText("**Browse Nexus** searches Stardew Valley mods. Open one to see its files and requirements, then **Install**. Requirements that are missing can be installed in the same step.")
                HelpText("**Collections** lists curated mod packs from Nexus. A collection installs every mod it lists, at the versions it was made with.")
                HelpText("Install a collection into a **new profile** named after it: only the collection's mods are on there, so it doesn't mix with your other mods, and mods you already have aren't downloaded again. Your usual profile is still one click away in the toolbar.")
                HelpText("Links in Starseed open in its own Nexus browser, which catches **Mod Manager Download** buttons. To catch them in Safari or Chrome too, click **Use This App** in **Settings → Nexus Mods**.")
            }
            HelpSection("Optional files") {
                HelpText("Mods with extra files on Nexus (add-ons, compatibility patches) show a small badge in the list. The details panel lists them under **Optional Files on Nexus**, each with its own **Install** button.")
            }

        case .managing:
            HelpSection("The Installed list") {
                HelpText("Every mod in the Mods folder, with its version, author and status. Tick or untick **On** to enable or disable a mod: disabled mods stay installed but SMAPI skips them (their folder name starts with a dot). ⌘Z undoes it.")
                HelpText("Mods made of several parts, like Stardew Valley Expanded, appear as one row you can expand; their parts are enabled and disabled together. Type in the filter bar to find a mod by name, author or ID (⌘F).")
            }
            HelpSection("The details panel") {
                HelpText("Select a mod to see its description and Nexus page, the mods it needs (**Requires**), the mods that use it (**Required By**, **Optional For**) and any **Conflicts** SMAPI reported. From there you can:")
                HelpBullets([
                    "edit its settings with **Mod Settings…**, without opening the config file",
                    "go back to an earlier version under **Previous Versions** (kept automatically when you update)",
                    "endorse or track it on Nexus",
                ])
            }
            HelpSection("Removing mods") {
                HelpText("**Move to Trash…** (or the Delete key) puts mods in the Trash, so they can be restored from Finder. If a mod is used by others, you're warned first; afterwards, Starseed offers to remove requirements nothing uses anymore.")
                HelpText("If the same mod is installed twice, SMAPI loads neither copy: a banner offers **Keep Newest**.")
            }

        case .updates:
            HelpText("Starseed asks SMAPI's update service about every installed mod, at launch and every few hours (**Settings → General**). You get a notification when new updates are found, and the status bar at the bottom of the window shows each check's progress and result.")
            HelpSection("Installing updates") {
                HelpText("Mods with an update show an **Update to…** button in the **Activity** column. The **Updates** section lists them all, with **Update All**. While a mod downloads and installs, its progress shows in the same column.")
                HelpText("Open **What's New** under an update to read the changelog from Nexus before installing it.")
            }
            HelpSection("If an update breaks something") {
                HelpText("The version you replaced is kept. Select the mod and pick it under **Previous Versions** in the details panel; your settings carry over.")
            }
            HelpSection("The game and SMAPI") {
                HelpText("The bar at the bottom of the window shows Stardew Valley's and SMAPI's versions, each with a colored dot: **green** when up to date, **yellow** when an update is waiting, **red** when missing. Point at a dot to see why.")
                HelpBullets([
                    "When Steam has a game update, **Update in Steam** opens the game's page in Steam.",
                    "When SMAPI has a new version, **Update to…** installs it. After a game update, SMAPI may be disconnected; **Reinstall** connects it again.",
                ])
            }
            HelpSection("Updates of Starseed") {
                HelpText("Starseed updates itself: it checks for new versions once a day and asks before installing. **Starseed → Check for App Updates…** checks right away.")
            }

        case .requirements:
            HelpText("Many mods need others to work: frameworks like Content Patcher or SpaceCore, or tilesheet packs. The **Requirements** section lists what your enabled mods need but you don't have, and which mods need it.")
            HelpBullets([
                "**Install** downloads it from Nexus; **Install All** does them all.",
                "If it's installed but disabled, **Enable** turns it back on.",
                "Mods hosted elsewhere (ModDrop, GitHub…) get a **Get on…** button that opens their page: download the file there, then drop it on the window.",
            ])
            HelpText("**Not listed on Nexus** holds IDs from mods' files that match nothing on their Nexus pages. They're usually covered by a requirement above under another name; if SMAPI's log still says something is missing, search for it.")

        case .profiles:
            HelpSection("Profiles") {
                HelpText("A profile remembers which mods are on. One is always in use; its name shows in the toolbar, and turning mods on or off updates it. Starseed starts with a **Default** profile.")
                HelpText("**In “…”** at the right of the filter bar shows only the mods in the profile in use; **All Mods** shows everything installed.")
                HelpText("Make one for each way you play (a big expansion run, a vanilla-plus game…): **Manage Profiles…** in the toolbar's profile menu creates, renames and deletes them. Choosing another profile in that menu switches which mods are on; switching back brings yours back exactly as they were.")
            }
            HelpSection("My Collections") {
                HelpText("A collection is a list of your mods with their versions, Nexus pages and settings. **Export…** it to share your setup, or keep it as a backup; **Import…** reads one back and offers to install whatever's missing. **Apply Settings…** then copies the collection's mod settings over yours.")
            }
            HelpSection("Mods for each save") {
                HelpText("In **Saves**, choose which profile or collection a save is played with. **Use Mods & Play** switches to those mods before launching, so each farm always gets its own set.")
            }

        case .saves:
            HelpSection("Missing mods") {
                HelpText("**Saves** lists your farms. Select one to see the mods it was played with and which are missing or older here, then **Find Missing Mods** to install them from Nexus.")
            }
            HelpSection("Backups") {
                HelpText("**Back Up All Saves**, or **Back Up Now** on a single farm, makes a zip you can restore later, all at once or one save at a time. Restoring first backs up the current saves, so it can be undone. Backups made by SMAPI's own Save Backup mod are listed too.")
                HelpText("When your mods changed since you last played, **Play** backs up every save before starting the game; the last 5 of these are kept. You can turn this off in **Settings → General**.")
            }

        case .problems:
            HelpSection("After you play") {
                HelpText("When the game closes, Starseed reads SMAPI's log. If mods didn't load, had errors, conflicted or crashed the game, a notification tells you; click it to open the **SMAPI Log** with plain advice and a button to fix each problem.")
            }
            HelpSection("Conflicts") {
                HelpText("Two mods conflict when they replace the same game files: SMAPI then uses the game's originals, so neither change shows. The mods' details show the conflict in orange, and **Disable One** in the SMAPI Log turns one off (⌘Z undoes it).")
            }
            HelpSection("Find a Broken Mod") {
                HelpText("When something goes wrong but nothing says which mod is to blame, use **Game → Find a Broken Mod…**:")
                HelpBullets([
                    "Starseed turns off half of your mods. Mods that need each other, and the parts of one mod, stay together.",
                    "Play until you can tell whether the problem happens, quit the game, then answer **Yes** or **No**.",
                    "After a few tests, Starseed names the mod. Keep it off, or put everything back as it was.",
                ])
                HelpText("Don't go to bed in the game during tests: Stardew Valley saves overnight, and saving with mods off can lose their content. You can quit Starseed between tests; the search continues where you left it.")
            }
            HelpSection("If an update caused it") {
                HelpText("Select the mod and pick the version you had under **Previous Versions** in the details panel.")
            }

        case .settings:
            HelpSection("General") {
                HelpBullets([
                    "**Language**: Starseed's language, or the one macOS uses. It changes after a restart.",
                    "**Updates**: checking mods every few hours, notifications, and the menu bar icon.",
                    "**Appearance**: show or hide mod pictures from Nexus.",
                    "**Playing**: the report after each game session.",
                    "**Saves**: back up saves before playing when your mods changed.",
                    "Your **Mods folder**, and the SMAPI and game versions found next to it.",
                ])
            }
            HelpSection("The menu bar icon") {
                HelpText("With the icon on, closing the window keeps Starseed running, so it keeps checking for updates. Its menu shows the game's and SMAPI's state, the number of updates, the last session's problems, and lets you play or switch profiles without opening the window.")
            }
            HelpSection("Nexus Mods") {
                HelpText("Your personal API key, your account (free or Premium), and **Use This App**, which makes Starseed catch **Mod Manager Download** links clicked in Safari or Chrome.")
            }
            HelpSection("Storage") {
                HelpText("How much space your mods take, largest first, plus the previous versions kept for rollback and Starseed's save backups. You can remove old versions and backups older than 30 days; they go to the Trash.")
            }

        case .log:
            HelpText("SMAPI writes a log each time the game runs. The **SMAPI Log** section shows the latest one with colors per level (errors, warnings, info…) and filters by level, mod or text.")
            HelpSection("What SMAPI is telling you") {
                HelpText("The top of the log turns SMAPI's messages into plain advice, each with a button to fix it:")
                HelpBullets([
                    "mods that didn't load, and what they need",
                    "mods that had errors while you played",
                    "mods that conflict because they replace the same game files",
                    "updates for SMAPI and your mods",
                ])
            }
            HelpSection("Asking for help") {
                HelpText("When reporting a problem to a mod author, share your log: **Upload to smapi.io…** gives you a link to paste. **Clear** hides older lines so the next run is easy to read.")
            }

        case .troubleshooting:
            HelpQuestion("macOS asks for Keychain access at launch.") {
                HelpText("The Nexus API key is stored in your Keychain. Choose **Always Allow**; a rebuilt or updated copy of the app may ask once more.")
            }
            HelpQuestion("A download stays on “Waiting on Nexus”.") {
                HelpText("Free accounts have to click **Slow download** on the Nexus page in Starseed's browser window. Click **Waiting on Nexus** to bring that page back.")
            }
            HelpQuestion("A mod doesn't show up in the game.") {
                HelpText("Check its status in **Installed** and the **SMAPI Log** after starting the game: it may be disabled, missing a requirement, need a newer SMAPI, or conflict with another mod.")
            }
            HelpQuestion("The game starts without mods.") {
                HelpText("A game update probably disconnected SMAPI. Click **Reinstall SMAPI** in the orange banner; your mods and settings stay as they are.")
            }
            HelpQuestion("Something breaks, but the log doesn't say which mod.") {
                HelpText("Use **Game → Find a Broken Mod…**. Starseed turns off half of your mods, you play and say whether the problem happened, and after a few tests it names the mod. Your mods are put back at the end.")
            }
            HelpQuestion("How do I know if a mod failed while I played?") {
                HelpText("When the game closes, Starseed reads SMAPI's log and sends a notification if mods didn't load, had errors, conflicted or crashed the game. Click it to see SMAPI's advice.")
            }
            HelpQuestion("macOS says it can't check Starseed when I open it.") {
                HelpText("Starseed isn't signed with a paid Apple Developer ID. Open **System Settings → Privacy & Security** and click **Open Anyway**. It's needed only once; updates don't ask again.")
            }
            HelpQuestion("Something else went wrong.") {
                HelpText("Most problems show up in the **SMAPI Log**. The Stardew Valley modding community can help with it on the official forums and Discord.")
            }
            HelpQuestion("Something is wrong with Starseed itself.") {
                HelpText("Use **Help → Report a Problem or Suggest an Idea…** to tell us on GitHub. Include your Starseed version (**Starseed → About Starseed**) and what you were doing.")
            }

        case .shortcuts:
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                shortcut("⌘O", "Install mods from files")
                shortcut("⌘R", "Rescan the Mods folder")
                shortcut("⇧⌘U", "Check for mod updates")
                shortcut("⌘F", "Filter the Installed list")
                shortcut("⌘Z / ⇧⌘Z", "Undo or redo enabling and disabling")
                shortcut("⌫", "Move the selected mods to the Trash")
                shortcut("⇧⌘O", "Open the Mods folder")
                shortcut("⌘L", "Play Stardew Valley")
                shortcut("⇧⌘L", "Show SMAPI Log")
                shortcut("⌘1 – ⌘8", "Go to a page of the sidebar")
                shortcut("⌥⌘I", "Show or hide the details panel")
                shortcut("⌘,", "Settings")
                shortcut("⌘?", "This help")
            }
        }

        if topic == .gettingStarted || topic == .troubleshooting {
            HelpSection("More help") {
                VStack(alignment: .leading, spacing: 6) {
                    Link("Stardew Valley Wiki: Getting started with mods", destination: URL(string: "https://stardewvalleywiki.com/Modding:Player_Guide/Getting_Started")!)
                    Link("SMAPI website and log parser", destination: URL(string: "https://smapi.io")!)
                    Link("Stardew Valley mods on Nexus Mods", destination: URL(string: "https://www.nexusmods.com/stardewvalley")!)
                }
            }
        }
    }

    private func shortcut(_ keys: String, _ action: LocalizedStringKey) -> some View {
        GridRow {
            Text(verbatim: keys)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(action)
        }
    }
}

private struct HelpText: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HelpBullets: View {
    let items: [LocalizedStringKey]
    init(_ items: [LocalizedStringKey]) { self.items = items }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "•").foregroundStyle(.secondary)
                    HelpText(items[index])
                }
            }
        }
        .padding(.leading, 4)
    }
}

private struct HelpSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold())
            content
        }
    }
}

/// A troubleshooting question with its answer.
private struct HelpQuestion<Content: View>: View {
    let question: LocalizedStringKey
    @ViewBuilder let content: Content
    init(_ question: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.question = question
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question).font(.headline)
            content
        }
    }
}

/// Help menu items. A view, so it can open the Help window.
struct HelpCommands: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Starseed Help") { openWindow(id: HelpView.windowID) }
            .keyboardShortcut("?", modifiers: .command)
        Divider()
        Link("Stardew Valley Wiki: Getting started with mods", destination: URL(string: "https://stardewvalleywiki.com/Modding:Player_Guide/Getting_Started")!)
        Link("SMAPI website and log parser", destination: URL(string: "https://smapi.io")!)
        Divider()
        Link("Starseed on GitHub", destination: AppLinks.repository)
        Link("Report a Problem or Suggest an Idea…", destination: AppLinks.newIssue)
    }
}
