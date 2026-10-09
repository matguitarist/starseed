import Foundation
import Testing
@testable import ModManagerCore

/// Answers requests from canned responses and records what was sent.
final class MockNexus: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (Int, String)] = [:]   // "METHOD path" -> (status, body)
    nonisolated(unsafe) static var requests: [(method: String, url: URL, body: String, headers: [String: String])] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        var body = request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body += String(decoding: buffer[0..<read], as: UTF8.self)
            }
            stream.close()
        }
        let method = request.httpMethod ?? "GET"
        Self.requests.append((method, url, body, request.allHTTPHeaderFields ?? [:]))
        let key = "\(method) \(url.path())"
        let (status, text) = Self.responses[key] ?? (404, #"{"message":"not mocked: \#(key)"}"#)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func client() -> NexusClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockNexus.self]
        return NexusClient(apiKey: "test-key", appVersion: "test", session: URLSession(configuration: config))
    }
}

@Suite(.serialized) struct EndorseTrackTests {
    init() {
        MockNexus.responses = [:]
        MockNexus.requests = []
    }

    @Test func readsEndorsementsAndTrackedModsForStardewOnly() async throws {
        MockNexus.responses["GET /v1/user/endorsements.json"] = (200, """
        [{"mod_id": 1915, "domain_name": "stardewvalley", "date": 1, "version": "2.9.1", "status": "Endorsed"},
         {"mod_id": 7286, "domain_name": "stardewvalley", "date": 1, "version": "2.0", "status": "Abstained"},
         {"mod_id": 266, "domain_name": "skyrimspecialedition", "date": 1, "version": "1", "status": "Endorsed"}]
        """)
        MockNexus.responses["GET /v1/user/tracked_mods.json"] = (200, #"[{"mod_id": 1915, "domain_name": "stardewvalley"}, {"mod_id": 3, "domain_name": "skyrim"}]"#)
        let client = MockNexus.client()
        #expect(try await client.endorsements() == [1915: .endorsed, 7286: .abstained])
        #expect(try await client.trackedMods() == [1915])
        #expect(MockNexus.requests.allSatisfy { $0.headers["apikey"] == "test-key" })
    }

    @Test func sendsEndorseAndTrackRequestsNexusExpects() async throws {
        MockNexus.responses["POST /v1/games/stardewvalley/mods/1915/endorse.json"] = (200, #"{"message":"Updated","status":"Endorsed"}"#)
        MockNexus.responses["POST /v1/user/tracked_mods.json"] = (201, #"{"message":"User is now Tracking Mod: 1915"}"#)
        MockNexus.responses["DELETE /v1/user/tracked_mods.json"] = (200, #"{"message":"User is no longer tracking 1915"}"#)
        let client = MockNexus.client()

        try await client.endorse(modID: 1915, version: "2.9.1")
        try await client.track(modID: 1915)
        try await client.untrack(modID: 1915)

        let endorse = MockNexus.requests[0]
        #expect(endorse.method == "POST")
        #expect(endorse.body.contains(#""Version":"2.9.1""#))
        let track = MockNexus.requests[1]
        #expect(track.url.query() == "domain_name=stardewvalley")
        #expect(track.body == "mod_id=1915")
        #expect(track.headers["Content-Type"] == "application/x-www-form-urlencoded")
        #expect(MockNexus.requests[2].method == "DELETE")
    }

    @Test func surfacesNexusRefusals() async {
        MockNexus.responses["POST /v1/games/stardewvalley/mods/5/endorse.json"] = (403, #"{"message":"NOT_DOWNLOADED_MOD"}"#)
        await #expect(throws: NexusError.self) { try await MockNexus.client().endorse(modID: 5, version: nil) }
    }
}
