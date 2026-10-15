// A short tip at the top of each page, the first times it's opened, for
// people new to the app. "Got It" hides that page's tip; "Hide All Tips"
// turns them off (Help ▸ Show Page Tips Again brings them back).

import SwiftUI

extension SidebarItem {
    /// Stable name, for remembering dismissed tips.
    var tipKey: String {
        switch self {
        case .installed: "installed"
        case .updates: "updates"
        case .requirements: "requirements"
        case .browse: "browse"
        case .collections: "collections"
        case .saves: "saves"
        case .log: "log"
        }
    }

    var tip: (title: LocalizedStringKey, text: LocalizedStringKey) {
        switch self {
        case .installed:
            ("Your Mods", "Tick a mod's box to turn it on or off; nothing is deleted. Changes are saved to the profile in use (menu at the right of the filter bar). Drop downloaded .zip files on the window to install them.")
        case .updates:
            ("Updates", "Mods with a newer version on Nexus or elsewhere. Update one at a time, or all at once. The version you had is kept, so you can go back from the mod's details.")
        case .requirements:
            ("Requirements", "Mods that your mods need but that are missing or turned off. Install All turns on or downloads every one of them.")
        case .browse:
            ("Browse Nexus", "Search Nexus Mods, or paste a Nexus link or mod number. Click a mod to read about it and install it, with what it requires.")
        case .collections:
            ("Collections", "Ready-made modpacks from Nexus. Installing one makes a profile with just its mods, so your other setups stay as they are.")
        case .saves:
            ("Saves", "Your farms, grouped by the profile they're played with. See which mods a save needs, back saves up and restore them. Play switches to the save's profile first.")
        case .log:
            ("SMAPI Log", "What SMAPI wrote while the game ran, with problems explained in plain words. After you play, Starseed tells you if a mod failed.")
        }
    }
}

struct PageTip: View {
    let page: SidebarItem
    @AppStorage(Preferences.showPageTips) private var showPageTips = true
    @AppStorage(Preferences.seenPageTips) private var seenPageTips = ""

    var body: some View {
        if showPageTips, !seen.contains(page.tipKey) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.tip.title).font(.headline)
                    Text(page.tip.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Got It") {
                        withAnimation { seenPageTips = (seen + [page.tipKey]).joined(separator: ",") }
                    }
                    Button("Hide All Tips") {
                        withAnimation { showPageTips = false }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.yellow.opacity(0.08))
            .overlay(alignment: .bottom) { Divider() }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var seen: [String] {
        seenPageTips.split(separator: ",").map(String.init)
    }

    /// Help ▸ Show Page Tips Again.
    static func showAgain() {
        UserDefaults.standard.set(true, forKey: Preferences.showPageTips)
        UserDefaults.standard.set("", forKey: Preferences.seenPageTips)
    }
}
