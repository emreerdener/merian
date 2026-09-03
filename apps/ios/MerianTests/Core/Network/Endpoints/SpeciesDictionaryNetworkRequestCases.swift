import Foundation
import Testing

@testable import Merian

struct SpeciesDictionaryNetworkRequestCase: Sendable, CustomTestStringConvertible {
    enum Kind: Sendable { case dictionary, catalog, overview, stats }

    private typealias Fixtures = SpeciesDictionaryNetworkFixtures
    let name: String
    let kind: Kind
    let expectedJSON: String
    let invoke: @MainActor @Sendable (MerianNetworkClient) async throws -> Void

    var testDescription: String { name }
    var function: String { kind == .stats ? "species-observation-stats" : "species-dictionary" }
    var path: String { "/\(function)" }
    var isCacheable: Bool { kind == .dictionary || kind == .stats }
    var responseJSON: String {
        switch kind {
        case .dictionary: Fixtures.dictionaryJSON
        case .catalog: Fixtures.catalogJSON
        case .overview: Fixtures.overviewJSON
        case .stats: Fixtures.statsJSON
        }
    }

    static let detailName = Self(
        name: "detail by name", kind: .dictionary,
        expectedJSON: #"{"scientific_name":"Testus floridus"}"#
    ) { client in
        _ = try await client.getSpeciesDictionary(scientificName: Fixtures.scientificName)
    }
    static let detailID = Self(
        name: "detail by ID omits name", kind: .dictionary,
        expectedJSON: #"{"species_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}"#
    ) { client in
        _ = try await client.getSpeciesDictionary(speciesId: Fixtures.speciesID)
    }
    static let catalog = Self(
        name: "full catalog defaults", kind: .catalog, expectedJSON: #"{"mode":"catalog","limit":40}"#
    ) { client in
        _ = try await client.getSpeciesDictionaryCatalog(category: .all)
    }
    static let convenienceCatalog = Self(
        name: "convenience catalog defaults", kind: .catalog, expectedJSON: #"{"mode":"catalog","limit":40}"#
    ) { client in
        _ = try await client.getSpeciesDictionaryCatalog()
    }
    static let overview = Self(
        name: "overview defaults", kind: .overview, expectedJSON: #"{"mode":"overview"}"#
    ) { client in
        _ = try await client.getSpeciesDictionaryOverview()
    }
    static let stats = Self(name: "stats GET", kind: .stats, expectedJSON: "{}") { client in
        _ = try await client.getSpeciesObservationStats(speciesId: Fixtures.speciesID, scientificName: Fixtures.scientificName)
    }

    static var operations: [Self] { [detailName, detailID, catalog, convenienceCatalog, overview, stats] }
    static var all: [Self] { operations + variants }

    @discardableResult
    func expectRequest(_ request: URLRequest) throws -> SpeciesDictionaryRequestSnapshot {
        let snapshot: NetworkEndpointRequestSnapshot
        if kind == .stats {
            expectCommonHeaders(request)
            #expect(request.httpMethod == "GET")
            #expect(request.timeoutInterval == 20)
            #expect(MockURLProtocol.bodyData(for: request) == nil)
            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(components.queryItems == [
                URLQueryItem(name: "species_id", value: Fixtures.speciesID),
                URLQueryItem(name: "scientific_name", value: Fixtures.scientificName)
            ])
            snapshot = NetworkEndpointRequestSnapshot(body: Data(), idempotencyKey: nil, timeout: request.timeoutInterval)
        } else if kind == .overview {
            expectCommonHeaders(request)
            #expect(request.httpMethod == "POST")
            #expect(request.timeoutInterval == 30)
            #expect(request.url?.query == nil)
            // Read once: a URLProtocol request can carry a one-shot body stream.
            let body = try #require(MockURLProtocol.bodyData(for: request))
            var payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let cacheBuster = try #require(payload.removeValue(forKey: "cache_buster") as? String)
            #expect(UUID(uuidString: cacheBuster) != nil && cacheBuster == cacheBuster.uppercased())
            let withoutBuster = try JSONSerialization.data(withJSONObject: payload)
            #expect(try NetworkEndpointTestSupport.canonicalRequestJSON(withoutBuster) ==
                NetworkEndpointTestSupport.canonicalRequestJSON(Data(expectedJSON.utf8)))
            snapshot = NetworkEndpointRequestSnapshot(body: body, idempotencyKey: nil, timeout: request.timeoutInterval)
        } else {
            snapshot = try NetworkEndpointTestSupport.expectPOST(request, function: function, json: expectedJSON)
        }
        return SpeciesDictionaryRequestSnapshot(url: request.url, transport: snapshot)
    }

    @MainActor
    func withResponse(_ json: String? = nil, body: (MerianNetworkClient) async throws -> Void) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        try await confirmation("Exactly one Dictionary network request") { sent in
            fixture.transport.register(path: path) { request in
                sent()
                try expectRequest(request)
                return try NetworkEndpointTestSupport.response(to: request, json: json ?? responseJSON)
            }
            try await body(fixture.client)
        }
    }

    private func expectCommonHeaders(_ request: URLRequest) {
        #expect(request.url?.scheme == "https")
        #expect(request.url?.path == "/functions/v1/\(function)")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Merian-Entitlement-Protocol") == "3")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == nil)
    }

    private static var variants: [Self] {
        [
            Self(name: "detail name normalization retains case", kind: .dictionary,
                 expectedJSON: #"{"scientific_name":"TESTUS floridus"}"#) { client in
                _ = try await client.getSpeciesDictionary(scientificName: " \n TESTUS \t floridus ")
            },
            Self(name: "detail ID and name normalization", kind: .dictionary,
                 expectedJSON: #"{"species_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","scientific_name":"Testus floridus"}"#) { client in
                _ = try await client.getSpeciesDictionary(
                    speciesId: " \(Fixtures.speciesID.uppercased()) \n", scientificName: " Testus \n floridus "
                )
            },
            Self(name: "invalid ID permits valid name", kind: .dictionary,
                 expectedJSON: #"{"scientific_name":"Testus floridus"}"#) { client in
                _ = try await client.getSpeciesDictionary(speciesId: "not-a-uuid", scientificName: Fixtures.scientificName)
            },
            Self(name: "valid ID permits omitted overlong name", kind: .dictionary,
                 expectedJSON: #"{"species_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}"#) { client in
                _ = try await client.getSpeciesDictionary(speciesId: Fixtures.speciesID, scientificName: String(repeating: "x", count: 161))
            },
            Self(name: "catalog trims optional filters but keeps internal whitespace and raw limit", kind: .catalog,
                 expectedJSON: #"{"mode":"catalog","limit":-4,"category":"region","region":"North  America","group":"birds","query":"Testus  floridus"}"#) { client in
                _ = try await client.getSpeciesDictionaryCatalog(
                    category: .region, region: " North  America \n", group: " birds ", query: " Testus  floridus ", limit: -4
                )
            },
            Self(name: "catalog omits all category and blank filters", kind: .catalog,
                 expectedJSON: #"{"mode":"catalog","limit":0}"#) { client in
                _ = try await client.getSpeciesDictionaryCatalog(category: .all, region: " \n ", group: "", query: "\t", limit: 0)
            },
            Self(name: "catalog raw cursor includes empty created_at", kind: .catalog,
                 expectedJSON: #"{"mode":"catalog","limit":40,"category":"recently_added","cursor":{"scientific_name":" RAW name ","species_id":" RAW-ID ","created_at":""}}"#) { client in
                _ = try await client.getSpeciesDictionaryCatalog(
                    category: .recentlyAdded,
                    cursor: SpeciesDictionaryCatalogCursor(scientificName: " RAW name ", speciesId: " RAW-ID ", createdAt: "")
                )
            },
            Self(name: "convenience overload forwards query limit and cursor without created_at", kind: .catalog,
                 expectedJSON: #"{"mode":"catalog","limit":250,"query":"Testus","cursor":{"scientific_name":" RAW name ","species_id":" RAW-ID "}}"#) { client in
                _ = try await client.getSpeciesDictionaryCatalog(
                    query: " Testus ", limit: 250,
                    cursor: SpeciesDictionaryCatalogCursor(scientificName: " RAW name ", speciesId: " RAW-ID ")
                )
            },
            Self(name: "overview trims region", kind: .overview,
                 expectedJSON: #"{"mode":"overview","user_region":"US"}"#) { client in
                _ = try await client.getSpeciesDictionaryOverview(userRegion: " \n US ")
            },
            Self(name: "overview omits blank region", kind: .overview,
                 expectedJSON: #"{"mode":"overview"}"#) { client in
                _ = try await client.getSpeciesDictionaryOverview(userRegion: " \n ")
            },
            Self(name: "stats canonicalizes ID and collapses name whitespace", kind: .stats, expectedJSON: "{}") { client in
                _ = try await client.getSpeciesObservationStats(
                    speciesId: " \(Fixtures.speciesID.uppercased()) \n", scientificName: " Testus \t floridus "
                )
            }
        ]
    }
}

struct SpeciesDictionaryRequestSnapshot: Equatable, Sendable {
    let url: URL?
    let transport: NetworkEndpointRequestSnapshot
}
