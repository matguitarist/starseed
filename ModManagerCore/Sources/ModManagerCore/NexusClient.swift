// Nexus Mods API client.
//
// - Browsing/searching and file lists use the public v2 GraphQL API (no key).
// - Download links use the v1 REST API and need the user's personal API key.
//   Premium accounts can request a link for any file. Free accounts need the
//   one-time `key`/`expires` pair from an nxm:// link, which the website hands
//   out when you click "Mod Manager Download".
//
// Nexus API acceptable use policy:
// https://help.nexusmods.com/article/114-api-acceptable-use-policy

import Foundation

public struct NexusMod: Identifiable, Hashable, Sendable, Decodable {
    public let modId: Int
    public let name: String
    public let summary: String?
    public let author: String?
    public let version: String?
    public let downloads: Int?
    public let endorsements: Int?
    public let thumbnailUrl: String?
    public let pictureUrl: String?
    public let updatedAt: String?

    public var id: Int { modId }
    public var pageURL: URL { NexusClient.modPageURL(modId) }
    public var thumbnailURL: URL? { thumbnailUrl.flatMap(URL.init(string:)) }
    public var pictureURL: URL? { pictureUrl.flatMap(URL.init(string:)) }
}

public struct NexusFile: Identifiable, Hashable, Sendable, Decodable {
    public let fileId: Int
    public let name: String
    public let version: String?
    public let category: String      // MAIN, OPTIONAL, UPDATE, MISCELLANEOUS, OLD_VERSION, ARCHIVED...
    public let sizeInBytes: String?  // BigInt comes back as a string
    public let date: Int             // unix seconds
    public let description: String?

    public var id: Int { fileId }
    public var uploadedAt: Date { Date(timeIntervalSince1970: TimeInterval(date)) }
    public var byteCount: Int64? { sizeInBytes.flatMap { Int64($0) } }
    public var isCurrent: Bool { !["OLD_VERSION", "ARCHIVED", "REMOVED", "DELETED"].contains(category) }

    /// "MAIN" -> "Main files", etc., matching the sections on the Nexus files tab.
    public var categoryTitle: String {
        switch category {
        case "MAIN": "Main files"
        case "OPTIONAL": "Optional files"
        case "UPDATE": "Updates"
        case "MISCELLANEOUS": "Miscellaneous"
        case "OLD_VERSION": "Old versions"
        case "ARCHIVED": "Archived"
        default: category.capitalized
        }
    }

    /// Lower sorts first: main files at the top, like on the website.
    public var categoryOrder: Int {
        ["MAIN", "UPDATE", "OPTIONAL", "MISCELLANEOUS", "OLD_VERSION", "ARCHIVED"].firstIndex(of: category) ?? 99
    }
}

/// Another Nexus mod that a mod lists under "Requirements".
public struct NexusRequirement: Identifiable, Hashable, Sendable {
    public let modID: Int?        // nil for external (non-Nexus) requirements
    public let name: String
    public let notes: String?
    public let externalURL: URL?

    public var id: String { modID.map(String.init) ?? name }
}

public struct NexusUser: Sendable, Equatable, Decodable {
    public let name: String
    public let isPremium: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case isPremium = "is_premium"
    }

    public init(name: String, isPremium: Bool) {
        self.name = name
        self.isPremium = isPremium
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        isPremium = try container.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
    }
}

public enum NexusSort: String, CaseIterable, Sendable {
    case endorsements, downloads, updatedAt, createdAt, name

    public var title: String {
        switch self {
        case .endorsements: "Most Endorsed"
        case .downloads: "Most Downloaded"
        case .updatedAt: "Recently Updated"
        case .createdAt: "Newest"
        case .name: "Name"
        }
    }
}

/// A Nexus "Mod Manager Download" link, e.g.
/// nxm://stardewvalley/mods/1915/files/12345?key=abc&expires=1700000000&user_id=42
public struct NXMLink: Sendable, Equatable {
    init(gameDomain: String, modID: Int, fileID: Int, key: String?, expires: String?) {
        self.gameDomain = gameDomain
        self.modID = modID
        self.fileID = fileID
        self.key = key
        self.expires = expires
    }

    public let gameDomain: String
    public let modID: Int
    public let fileID: Int
    public let key: String?
    public let expires: String?

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "nxm",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host
        else { return nil }

        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[0] == "mods", parts[2] == "files",
              let modID = Int(parts[1]), let fileID = Int(parts[3])
        else { return nil }

        let query = components.queryItems ?? []
        gameDomain = host.lowercased()
        self.modID = modID
        self.fileID = fileID
        key = query.first { $0.name == "key" }?.value
        expires = query.first { $0.name == "expires" }?.value
    }
}

public struct NexusError: LocalizedError, Sendable {
    public let message: String
    /// A message to show the user, translated from this package's String Catalog.
    public init(_ message: String.LocalizationValue) { self.message = String(localized: message, bundle: .module) }
    /// A message used as is (e.g. Nexus's own error text).
    public init(verbatim message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct NexusClient: Sendable {
    public static let gameDomain = "stardewvalley"
    public static let gameID = 1303  // Stardew Valley's numeric Nexus game ID
    public static let smapiModID = 2400

    /// Nexus account sign-in; returns to the site afterwards.
    public static let signInURL = URL(string: "https://users.nexusmods.com/auth/sign_in")!

    public static let apiKeyPageURL = URL(string: "https://www.nexusmods.com/users/myaccount?tab=api")!

    public static func modPageURL(_ modID: Int) -> URL {
        URL(string: "https://www.nexusmods.com/\(gameDomain)/mods/\(modID)")!
    }

    /// The Nexus mod number in a pasted link or ID: "https://www.nexusmods.com/
    /// stardewvalley/mods/7286?tab=files", "nexusmods.com/stardewvalley/mods/7286",
    /// "#7286" or "7286". Links to other games don't count.
    public static func modID(fromLinkOrNumber text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = trimmed.wholeMatch(of: /#?(\d{1,7})/) {
            return Int(match.1)
        }
        guard let match = trimmed.firstMatch(of: /nexusmods\.com\/(?:games\/)?([A-Za-z0-9]+)\/mods\/(\d+)/.ignoresCase()),
              match.1.lowercased() == gameDomain
        else { return nil }
        return Int(match.2)
    }

    /// The website's files tab with the "Mod Manager Download" flow pre-selected
    /// for one file. Clicking through it sends an nxm:// link back to us.
    public static func modManagerDownloadPageURL(modID: Int, fileID: Int) -> URL {
        URL(string: "https://www.nexusmods.com/\(gameDomain)/mods/\(modID)?tab=files&file_id=\(fileID)&nmm=1")!
    }

    private static let graphQLURL = URL(string: "https://api.nexusmods.com/v2/graphql")!
    private static let restBaseURL = URL(string: "https://api.nexusmods.com/v1/")!

    let apiKey: String?
    let appVersion: String
    let session: URLSession

    public init(apiKey: String?, appVersion: String, session: URLSession = .shared) {
        self.apiKey = apiKey?.isEmpty == true ? nil : apiKey
        self.appVersion = appVersion
        self.session = session
    }

    public var hasAPIKey: Bool { apiKey != nil }

    // MARK: Browsing (GraphQL, no key needed)

    public struct SearchPage: Sendable {
        public let mods: [NexusMod]
        public let totalCount: Int
    }

    public func searchMods(
        query: String,
        sort: NexusSort,
        offset: Int = 0,
        count: Int = 30,
        uploader: String? = nil
    ) async throws -> SearchPage {
        var filter: [String: Any] = [
            "gameDomainName": [["value": Self.gameDomain, "op": "EQUALS"]],
            "adultContent": [["value": false, "op": "EQUALS"]],
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            filter["name"] = [["value": trimmed, "op": "WILDCARD"]]
        }
        if let uploader {
            filter["uploader"] = [["value": uploader, "op": "EQUALS"]]
        }
        let direction = sort == .name ? "ASC" : "DESC"

        struct Response: Decodable {
            struct Mods: Decodable { let totalCount: Int; let nodes: [NexusMod] }
            let mods: Mods
        }
        let response: Response = try await graphQL(
            """
            query Search($filter: ModsFilter, $sort: [ModsSort!], $offset: Int, $count: Int) {
              mods(filter: $filter, sort: $sort, offset: $offset, count: $count) {
                totalCount
                nodes { modId name summary author version downloads endorsements thumbnailUrl pictureUrl updatedAt }
              }
            }
            """,
            variables: [
                "filter": filter,
                "sort": [[sort.rawValue: ["direction": direction]]],
                "offset": offset,
                "count": count,
            ]
        )
        return SearchPage(mods: response.mods.nodes, totalCount: response.mods.totalCount)
    }

    public func mod(id modID: Int) async throws -> NexusMod {
        struct Response: Decodable { let mod: NexusMod }
        let response: Response = try await graphQL(
            """
            query Mod($modId: ID!, $gameId: ID!) {
              mod(modId: $modId, gameId: $gameId) {
                modId name summary author version downloads endorsements thumbnailUrl pictureUrl updatedAt
              }
            }
            """,
            variables: ["modId": String(modID), "gameId": String(Self.gameID)]
        )
        return response.mod
    }

    /// The mod's "Requirements" list from its Nexus page.
    public func requirements(forMod modID: Int) async throws -> [NexusRequirement] {
        struct Node: Decodable {
            let modId: String?
            let modName: String?
            let externalRequirement: Bool?
            let url: String?
            let notes: String?
        }
        struct Response: Decodable {
            struct Mod: Decodable {
                struct Requirements: Decodable {
                    struct Page: Decodable { let nodes: [Node] }
                    let nexusRequirements: Page
                }
                let modRequirements: Requirements?
            }
            let mod: Mod
        }
        let response: Response = try await graphQL(
            """
            query Requirements($modId: ID!, $gameId: ID!) {
              mod(modId: $modId, gameId: $gameId) {
                modRequirements { nexusRequirements { nodes { modId modName externalRequirement url notes } } }
              }
            }
            """,
            variables: ["modId": String(modID), "gameId": String(Self.gameID)]
        )
        return (response.mod.modRequirements?.nexusRequirements.nodes ?? []).compactMap { node in
            let isExternal = node.externalRequirement ?? false
            let id = isExternal ? nil : node.modId.flatMap(Int.init)
            guard let name = node.modName, !name.isEmpty, id != modID else { return nil }
            let notes = node.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            return NexusRequirement(
                modID: id,
                name: name,
                notes: notes?.isEmpty == false ? notes : nil,
                externalURL: isExternal ? node.url.flatMap(URL.init(string:)) : nil
            )
        }
    }

    /// All files for a mod, main files first and newest first within a section.
    public func files(forMod modID: Int) async throws -> [NexusFile] {
        struct Response: Decodable { let modFiles: [NexusFile] }
        let response: Response = try await graphQL(
            """
            query Files($modId: ID!, $gameId: ID!) {
              modFiles(modId: $modId, gameId: $gameId) {
                fileId name version category sizeInBytes date description
              }
            }
            """,
            variables: ["modId": String(modID), "gameId": String(Self.gameID)]
        )
        return response.modFiles.sorted {
            ($0.categoryOrder, -$0.date) < ($1.categoryOrder, -$1.date)
        }
    }

    // MARK: Account + downloads (REST, key needed)

    public func validateKey() async throws -> NexusUser {
        try await rest("users/validate.json")
    }

    /// A short-lived CDN URL for one file. Free accounts must pass the
    /// key/expires values from an nxm:// link; premium accounts can omit them.
    public func downloadURL(modID: Int, fileID: Int, key: String? = nil, expires: String? = nil) async throws -> URL {
        struct Mirror: Decodable {
            let URI: String
        }
        var query: [URLQueryItem] = []
        if let key, let expires {
            query = [URLQueryItem(name: "key", value: key), URLQueryItem(name: "expires", value: expires)]
        }
        let mirrors: [Mirror] = try await rest(
            "games/\(Self.gameDomain)/mods/\(modID)/files/\(fileID)/download_link.json",
            query: query
        )
        guard let first = mirrors.first, let url = URL(string: first.URI) else {
            throw NexusError("Nexus didn't return a download link for this file.")
        }
        return url
    }

    // MARK: Plumbing

    /// Identifies this app to Nexus, as the API policy asks.
    private func addAppHeaders(to request: inout URLRequest) {
        request.setValue("Starseed (Stardew Valley mod manager for macOS)", forHTTPHeaderField: "Application-Name")
        request.setValue(appVersion, forHTTPHeaderField: "Application-Version")
        request.setValue("Starseed-macOS/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "apikey") }
    }

    func graphQL<T: Decodable>(_ query: String, variables: [String: Any]) async throws -> T {
        var request = URLRequest(url: Self.graphQLURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAppHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, data: data)

        let envelope = try JSONDecoder().decode(GraphQLEnvelope<T>.self, from: data)
        if let result = envelope.data {
            return result
        }
        if let errors = envelope.errors, !errors.isEmpty {
            throw NexusError(verbatim: errors.map(\.message).joined(separator: "\n"))
        }
        throw NexusError("Nexus returned no data.")
    }

    private func rest<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await send("GET", path, query: query))
    }

    func restData(_ path: String) async throws -> Data {
        try await send("GET", path)
    }

    /// One REST call; `form` is sent URL-encoded, `json` as a JSON body.
    @discardableResult
    private func send(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        form: [String: String]? = nil,
        json: [String: String]? = nil
    ) async throws -> Data {
        guard apiKey != nil else {
            throw NexusError("Add your Nexus Mods API key in Settings to download mods.")
        }
        var url = Self.restBaseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        addAppHeaders(to: &request)
        if let form {
            var components = URLComponents()
            components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        } else if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, data: data)
        return data
    }

    // MARK: Endorsements and tracking

    public enum EndorsementStatus: String, Sendable {
        case endorsed = "Endorsed"
        case abstained = "Abstained"
        case undecided = "Undecided"
    }

    /// Your endorsements of Stardew Valley mods, by mod number.
    public func endorsements() async throws -> [Int: EndorsementStatus] {
        struct Item: Decodable {
            let mod_id: Int
            let domain_name: String
            let status: String
        }
        let items: [Item] = try await rest("user/endorsements.json")
        var result: [Int: EndorsementStatus] = [:]
        for item in items where item.domain_name == Self.gameDomain {
            result[item.mod_id] = EndorsementStatus(rawValue: item.status) ?? .undecided
        }
        return result
    }

    /// Stardew Valley mods you track on Nexus (notified of their updates).
    public func trackedMods() async throws -> Set<Int> {
        struct Item: Decodable {
            let mod_id: Int
            let domain_name: String
        }
        let items: [Item] = try await rest("user/tracked_mods.json")
        return Set(items.filter { $0.domain_name == Self.gameDomain }.map(\.mod_id))
    }

    /// Endorses a mod. Nexus only accepts endorsements for mods you've
    /// downloaded (and not right away); its error message explains which.
    public func endorse(modID: Int, version: String?) async throws {
        try await send("POST", "games/\(Self.gameDomain)/mods/\(modID)/endorse.json", json: version.map { ["Version": $0] } ?? [:])
    }

    /// Withdraws an endorsement ("abstain").
    public func abstain(modID: Int, version: String?) async throws {
        try await send("POST", "games/\(Self.gameDomain)/mods/\(modID)/abstain.json", json: version.map { ["Version": $0] } ?? [:])
    }

    public func track(modID: Int) async throws {
        try await send("POST", "user/tracked_mods.json", query: [URLQueryItem(name: "domain_name", value: Self.gameDomain)], form: ["mod_id": String(modID)])
    }

    public func untrack(modID: Int) async throws {
        try await send("DELETE", "user/tracked_mods.json", query: [URLQueryItem(name: "domain_name", value: Self.gameDomain)], form: ["mod_id": String(modID)])
    }

    private struct GraphQLEnvelope<T: Decodable>: Decodable {
        struct GraphQLError: Decodable { let message: String }
        let data: T?
        let errors: [GraphQLError]?
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        struct Message: Decodable { let message: String? }
        let serverMessage = (try? JSONDecoder().decode(Message.self, from: data))?.message
        switch http.statusCode {
        case 401:
            throw serverMessage.map(NexusError.init(verbatim:)) ?? NexusError("Your Nexus Mods API key was rejected. Check it in Settings.")
        case 403:
            throw serverMessage.map(NexusError.init(verbatim:)) ?? NexusError("Nexus only allows direct downloads for Premium members. Use “Mod Manager Download” on the website instead.")
        case 429:
            throw NexusError("Nexus rate limit reached. Try again in a little while.")
        default:
            throw serverMessage.map(NexusError.init(verbatim:)) ?? NexusError("Nexus request failed (HTTP \(http.statusCode)).")
        }
    }
}
