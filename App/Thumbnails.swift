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
            ShapedPicture(url: url)
        }
    }
}

/// A picture as wide as its container, in its own shape: landscape pictures
/// fill the width; portrait ones are shown whole (up to 4:5), over a blurred
/// copy of themselves.
struct ShapedPicture: View {
    let url: URL
    var cornerRadius: CGFloat = 8
    @State private var image: NSImage?

    /// Tallest box for portrait pictures (width / height).
    private static let tallestAspect: CGFloat = 0.8

    var body: some View {
        Group {
            if let image, image.size.width > 0, image.size.height > 0 {
                let aspect = image.size.width / image.size.height
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 24)
                        .opacity(0.6)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(max(aspect, Self.tallestAspect), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.quaternary.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
            }
        }
        .task(id: url) {
            image = ImageCache.shared.cached(url)
            if image == nil { image = await ImageCache.shared.image(for: url) }
        }
    }
}

/// A picture shown whole in a fixed box (list rows, headers), over a blurred
/// copy of itself, so pictures of any shape line up at the same size.
struct FittedPicture: View {
    let url: URL?
    var cornerRadius: CGFloat = 8
    @State private var image: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary.opacity(0.5))
            .overlay {
                if let image {
                    ZStack {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 12)
                            .opacity(0.6)
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
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
