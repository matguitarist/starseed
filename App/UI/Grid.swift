import CoreGraphics

/// Corner radii. The first three are the scale every Mac app of mine shares:
/// small boxes, fields and pictures use `control`, notices `banner`, cards on a page `card`.
enum Radius {
    static let control: CGFloat = 8
    static let banner: CGFloat = 12
    static let card: CGFloat = 16

    // Starseed's own.
    /// The small mod picture in a list row.
    static let thumbnail: CGFloat = 4
    /// A collection's tile art in its header.
    static let artwork: CGFloat = 10
}
