// Talks to SMAPI's public web API — the same service SMAPI uses for its
// "update available" console messages. It knows Nexus, GitHub, ModDrop,
// CurseForge and Chucklefish update keys, plus SMAPI's mod compatibility
// list, which maps a mod's UniqueID to its Nexus page even when its
// manifest has no update keys. No account needed.

import Foundation

public struct ModUpdate: Hashable, Sendable {
    public let installedVersion: String  // the version we asked about
    public let version: String           // the suggested newer version
    public let url: URL?

    public init(installedVersion: String, version: String, url: URL?) {
        self.installedVersion = installedVersion
        self.version = version
        self.url = url
    }

    /// The Nexus mod ID, when the update lives on Nexus.
    public var nexusModID: Int? {
        guard let url, url.host()?.hasSuffix("nexusmods.com") == true,
              let match = url.path().firstMatch(of: /\/mods\/(\d+)/)
        else { return nil }
        return Int(match.1)
    }
}

/// What SMAPI's database knows about a mod.
public struct SMAPIModRecord: Hashable, Sendable {
    public let uniqueID: String
    public let name: String?
    public let nexusID: Int?
}

public struct SMAPIResults: Sendable {
    /// Available updates keyed by lowercased UniqueID. Up-to-date mods are absent.
    public var updates: [String: ModUpdate] = [:]
    /// Known mods keyed by lowercased UniqueID.
    public var records: [String: SMAPIModRecord] = [:]
}

public struct UpdateChecker: Sendable {
    private static let endpoint = URL(string: "https://smapi.io/api/v3.0/mods")!
    private static let batchSize = 100

    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Checks installed mods for updates and collects their SMAPI records.
    public func check(_ mods: [ModInfo]) async throws -> SMAPIResults {
        let queries = mods
            .filter { !$0.uniqueID.isEmpty && $0.parseError == nil }
            .map { mod in
                Query(
                    id: mod.uniqueID,
                    updateKeys: mod.updateKeys,
                    installedVersion: Self.isValidSemanticVersion(mod.version) ? mod.version : nil
                )
            }
        return try await run(queries)
    }

    /// Looks up mods that aren't installed (e.g. missing dependencies) by UniqueID.
    public func lookup(uniqueIDs: [String]) async throws -> [String: SMAPIModRecord] {
        let queries = uniqueIDs.map { Query(id: $0, updateKeys: [], installedVersion: nil) }
        return try await run(queries).records
    }

    /// SMAPI's API rejects the *entire* batch (returns `[]`) if any mod has a
    /// version it can't parse, e.g. "?", "1", "1.2.3.4" or "0.0.0". Versions
    /// failing this check are left out, so one odd manifest can't hide
    /// everyone else's updates.
    static func isValidSemanticVersion(_ version: String) -> Bool {
        guard let match = version.wholeMatch(of: /(\d+)\.(\d+)(?:\.(\d+))?(?:-[0-9A-Za-z.\-]+)?(?:\+[0-9A-Za-z.\-]+)?/) else {
            return false
        }
        return [match.1, match.2, match.3 ?? "0"].contains { Int($0) != 0 }
    }

    // MARK: Plumbing

    private struct Query: Encodable {
        let id: String
        let updateKeys: [String]
        let installedVersion: String?  // omitted when nil
    }

    private func run(_ queries: [Query]) async throws -> SMAPIResults {
        var results = SMAPIResults()
        for start in stride(from: 0, to: queries.count, by: Self.batchSize) {
            let batch = Array(queries[start..<min(start + Self.batchSize, queries.count)])
            let partial = try await runBatch(batch)
            results.updates.merge(partial.updates) { _, new in new }
            results.records.merge(partial.records) { _, new in new }
        }
        return results
    }

    private func runBatch(_ queries: [Query]) async throws -> SMAPIResults {
        struct Request: Encodable {
            let mods: [Query]
            let apiVersion = "4.0.0"
            let platform = "Mac"
            let includeExtendedMetadata = true
        }
        struct Result: Decodable {
            struct Suggested: Decodable { let version: String; let url: String? }
            struct Metadata: Decodable { let name: String?; let nexusID: Int? }
            let id: String
            let suggestedUpdate: Suggested?
            let metadata: Metadata?
        }

        let installed = Dictionary(queries.map { ($0.id.lowercased(), $0.installedVersion ?? "") }, uniquingKeysWith: { first, _ in first })

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(mods: queries))

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NexusError("SMAPI mod lookup failed (HTTP \(http.statusCode)).")
        }

        var results = SMAPIResults()
        for result in try JSONDecoder().decode([Result].self, from: data) {
            let id = result.id.lowercased()
            if let metadata = result.metadata, metadata.name != nil || metadata.nexusID != nil {
                results.records[id] = SMAPIModRecord(uniqueID: result.id, name: metadata.name, nexusID: metadata.nexusID)
            }
            if let suggested = result.suggestedUpdate {
                results.updates[id] = ModUpdate(
                    installedVersion: installed[id] ?? "",
                    version: suggested.version,
                    url: suggested.url.flatMap(URL.init(string:))
                )
            }
        }
        return results
    }
}
