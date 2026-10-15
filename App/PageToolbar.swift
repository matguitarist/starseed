// Toolbar buttons shared by the pages, so each page's toolbar reads the
// same way: page actions, then Refresh, then Play, then the side panel
// toggle (always last).

import ModManagerCore
import SwiftUI

/// Play, on every page. With a save, switches to its profile first.
struct PlayToolbarButton: View {
    @AppModelEnvironment private var model
    var save: SaveGame?

    var body: some View {
        Button {
            if let save { model.play(save) } else { model.launchGame() }
        } label: {
            Label("Play", systemImage: "play.fill")
        }
        .help(helpText)
    }

    private var helpText: String {
        guard let save else { return String(localized: "Launch Stardew Valley with the mods that are on") }
        let farm = save.displayName
        if let profile = model.profile(forSave: save.id) {
            return String(localized: "Switch to the profile “\(profile)”, then launch the game. Then pick \(farm) in Load Game.")
        }
        return String(localized: "Launch the game. Then pick \(farm) in Load Game.")
    }
}

/// Refresh: a spinner while busy, so you can see it's working.
struct RefreshToolbarButton: View {
    let title: LocalizedStringKey
    let help: LocalizedStringKey
    var isBusy = false
    let action: () -> Void

    var body: some View {
        if isBusy {
            ProgressView()
                .controlSize(.small)
                .help(help)
        } else {
            Button(action: action) {
                Label(title, systemImage: "arrow.clockwise")
            }
            .help(help)
        }
    }
}

/// Shows or hides the panel at the right of a page.
struct PanelToolbarButton: View {
    let title: LocalizedStringKey
    let help: LocalizedStringKey
    @Binding var isShown: Bool

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Label(title, systemImage: "sidebar.trailing")
        }
        .help(help)
    }
}
