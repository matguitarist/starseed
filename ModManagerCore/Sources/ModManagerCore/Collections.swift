// Nexus collections: curated lists of mods pinned to exact files.
// Browsing and reading a collection's file list use the public GraphQL API.

import Foundation

public struct NexusCollection: Identifiable, Hashable, Sendable {
    public let slug: String
    public let name: String
    public let summary: String?
    public let author: String?
    public let endorsements: Int?
    public let totalDownloads: Int?
    public let tileImageURL: URL?
    public let latestRevision: Int?
    public let modCount: Int?
    public let totalSize: Int64?  // bytes

    public var id: String { slug }
    public var pageURL: URL {
        URL(string: "https://www.nexusmods.com/games/\(NexusClient.gameDomain)/collections/\(slug)")!
    }
}

/// One pinned file in a collection revision.
public struct CollectionMod: Identifiable, Hashable, Sendable {
    public let modID: Int
    public let fileID: Int
    public let modName: String
    public let fileName: String
    public let version: String?
    public let isOptional: Bool
    public let sizeKB: Int?

    public var id: Int { fileID }
}

public struct CollectionRevision: Sendable {
    public let collection: NexusCollection
    public let revisionNumber: Int
    public let mods: [CollectionMod]
}

public enum CollectionSort: String, CaseIterable, Sendable {
    case endorsements, downloads, rating, updatedAt, createdAt

    public var title: String {
        switch self {
        case .endorsements: "Most Endorsed"
        case .downloads: "Most Downloaded"
        case .rating: "Top Rated"
        case .updatedAt: "Recently Updated"
        case .createdAt: "Newest"
        }
    }
}

/// nxm://stardewvalley/collections/{slug}/revisions/{n} — Nexus's
/// "Add to Vortex" / mod-manager link for a collection.
public struct NXMCollectionLink: Sendable, Equatable {
    public let gameDomain: String
    public let slug: String
    public let revision: Int?

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "nxm", let host = url.host() else { return nil }
        let parts = url.path().split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "collections" else { return nil }
        gameDomain = host.lowercased()
        slug = parts[1]
        revision = parts.count >= 4 && parts[2] == "revisions" ? Int(parts[3]) : nil
    }
}

// MARK: - API

private struct CollectionNode: Decodable {
    struct Image: Decodable { let url: String?; let thumbnailUrl: String? }
    struct User: Decodable { let name: String? }
    struct Revision: Decodable { let revisionNumber: Int?; let modCount: Int?; let totalSize: String? }

    let slug: String
    let name: String
    let summary: String?
    let endorsements: Int?
    let totalDownloads: Int?
    let tileImage: Image?
    let user: User?
    let latestPublishedRevision: Revision?

    static let fields = """
        slug name summary endorsements totalDownloads
        tileImage { url thumbnailUrl(size: med) }
        user { name }
        latestPublishedRevision { revisionNumber modCount totalSize }
        """

    var model: NexusCollection {
        NexusCollection(
            slug: slug,
            name: name,
            summary: summary,
            author: user?.name,
            endorsements: endorsements,
            totalDownloads: totalDownloads,
            tileImageURL: (tileImage?.thumbnailUrl ?? tileImage?.url).flatMap(URL.init(string:)),
            latestRevision: latestPublishedRevision?.revisionNumber,
            modCount: latestPublishedRevision?.modCount,
            totalSize: latestPublishedRevision?.totalSize.flatMap { Int64($0) }
        )
    }
}

extension NexusClient {
    public struct CollectionPage: Sendable {
        public let collections: [NexusCollection]
        public let totalCount: Int
    }

    public func searchCollections(
        query: String,
        sort: CollectionSort,
        offset: Int = 0,
        count: Int = 30
    ) async throws -> CollectionPage {
        var filter: [String: Any] = [
            "gameDomain": [["value": Self.gameDomain, "op": "EQUALS"]],
            "adultContent": [["value": false, "op": "EQUALS"]],
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            filter["generalSearch"] = [["value": trimmed, "op": "WILDCARD"]]
        }

        struct Response: Decodable {
            struct Page: Decodable { let totalCount: Int; let nodes: [CollectionNode] }
            let collectionsV2: Page
        }
        let response: Response = try await graphQL(
            """
            query Collections($filter: CollectionsSearchFilter, $sort: [CollectionsSearchSort!], $offset: Int, $count: Int) {
              collectionsV2(filter: $filter, sort: $sort, offset: $offset, count: $count) {
                totalCount
                nodes { \(CollectionNode.fields) }
              }
            }
            """,
            variables: [
                "filter": filter,
                "sort": [[sort.rawValue: ["direction": "DESC"]]],
                "offset": offset,
                "count": count,
            ]
        )
        return CollectionPage(
            collections: response.collectionsV2.nodes.map(\.model),
            totalCount: response.collectionsV2.totalCount
        )
    }

    /// A collection's pinned files. `revision` nil means the latest published one.
    public func collectionRevision(slug: String, revision: Int? = nil) async throws -> CollectionRevision {
        struct Response: Decodable {
            struct Revision: Decodable {
                struct ModFile: Decodable {
                    struct File: Decodable {
                        struct Mod: Decodable { let name: String?; let modId: Int }
                        let name: String?
                        let modId: Int?
                        let size: Int?
                        let mod: Mod?
                    }
                    let fileId: Int
                    let optional: Bool
                    let version: String?
                    let file: File?
                }
                let revisionNumber: Int
                let collection: CollectionNode
                let modFiles: [ModFile]
            }
            let collectionRevision: Revision
        }
        var variables: [String: Any] = ["slug": slug, "domainName": Self.gameDomain]
        if let revision { variables["revision"] = revision }

        let response: Response = try await graphQL(
            """
            query Revision($slug: String!, $revision: Int, $domainName: String) {
              collectionRevision(slug: $slug, revision: $revision, domainName: $domainName) {
                revisionNumber
                collection { \(CollectionNode.fields) }
                modFiles { fileId optional version file { name modId size mod { name modId } } }
              }
            }
            """,
            variables: variables
        )
        let revision = response.collectionRevision
        let mods = revision.modFiles.compactMap { entry -> CollectionMod? in
            guard let file = entry.file, let modID = file.mod?.modId ?? file.modId else { return nil }
            return CollectionMod(
                modID: modID,
                fileID: entry.fileId,
                modName: file.mod?.name ?? file.name ?? "Mod \(modID)",
                fileName: file.name ?? "",
                version: entry.version,
                isOptional: entry.optional,
                sizeKB: file.size
            )
        }
        return CollectionRevision(collection: revision.collection.model, revisionNumber: revision.revisionNumber, mods: mods)
    }
}
