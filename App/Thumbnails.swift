// Pictures of installed mods from their Nexus pages: a small thumbnail in
// the Installed list and a larger picture in the details panel.

import AppKit
import ModManagerCore
import SwiftUI

extension AppModel {
    /// Fetches Nexus info (pictures) for installed mods not looked up yet.
    func loadNexusModInfo() async {
        let ids = Array(Set(mods.compactMap { nexusID(for: $0) })).filter { nexusModInfo[$0] == nil }.sorted()
        guard !ids.isEmpty, let found = try? await nexusClient.mods(ids: ids) else { return }
        for mod in found { nexusModInfo[mod.modId] = mod }
    }

    /// The Nexus page info for a row: the first part with a known page.
    func nexusInfo(for mods: [ModInfo]) -> NexusMod? {
        mods.lazy.compactMap { self.nexusID(for: $0) }.compactMap { self.nexusModInfo[$0] }.first
    }
}

/// Decoded images by URL, so scrolling the list doesn't reload them.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private var images: [URL: NSImage] = [:]
    private var loading: [URL: Task<NSImage?, Never>] = [:]

    func cached(_ url: URL) -> NSImage? { images[url] }

    func image(for url: URL) async -> NSImage? {
        if let image = images[url] { return image }
        if let task = loading[url] { return await task.value }
        let task = Task<NSImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return NSImage(data: data)
        }
        loading[url] = task
        let image = await task.value
        loading[url] = nil
        if let image { images[url] = image }
        return image
    }
}

/// A mod picture from Nexus, filling its frame; a puzzle piece meanwhile
/// and for mods without one.
struct ModPicture: View {
    let url: URL?
    var cornerRadius: CGFloat = 4
    @State private var image: NSImage?

    var body: some View {
        // An overlay takes the frame's size, so a wide picture is cropped
        // instead of widening the row.
        Rectangle()
            .fill(.quaternary.opacity(0.5))
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundStyle(.tertiary)
                        .imageScale(.small)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: url) {
            guard let url else { image = nil; return }
            image = ImageCache.shared.cached(url)
            if image == nil { image = await ImageCache.shared.image(for: url) }
        }
    }
}

/// The large picture at the top of the details panel.
struct ModHeaderPicture: View {
    @AppModelEnvironment private var model
    @AppStorage(Preferences.showModPictures) private var showModPictures = true
    let mods: [ModInfo]

    var body: some View {
        if showModPictures, let info = model.nexusInfo(for: mods), let url = info.pictureURL ?? info.thumbnailURL {
            ModPicture(url: url, cornerRadius: 8)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
        }
    }
}
