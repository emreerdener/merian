import Foundation
import Testing

@testable import Merian

@Suite("Species Observation Stats Endpoint")
@MainActor
struct SpeciesObservationStatsEndpointTests {
    private let networkClient: MerianNetworkClient
    private let mockTransport: ScopedMockTransport

    init() {
        let mockTransport = ScopedMockTransport()
        let networkClient = MerianNetworkClient()
        networkClient.overridingSession = mockTransport.makeSession()
        networkClient.overridingAuthUserID = UUID(
            uuidString: "22222222-2222-4222-8222-222222222222"
        )
        networkClient.resetSpeciesDictionaryCacheForTesting()
        self.mockTransport = mockTransport
        self.networkClient = networkClient
    }

    @Test func testGetSpeciesObservationStatsConstructsPayloadAndMemoizes() async throws {
        let testData = Data("""
        {
            "schema_version": 2,
            "data": {
                "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                "scientific_name": "Danaus plexippus",
                "source": {
                    "provider": "inaturalist",
                    "scope": "global",
                    "inaturalist_taxon_id": 48662,
                    "fetched_at": "2026-05-17T12:00:00.000Z"
                },
                "status": "fresh",
                "total_observations": 450448,
                "last_observation_date": "2026-05-17",
                "fetched_at": "2026-05-17T12:00:00.000Z",
                "provider_errors": [],
                "seasonality": [{ "month": 5, "count": 1200 }],
                "history": [{ "year": 2026, "month": 5, "count": 1200 }],
                "life_stage": [],
                "sex": []
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        var requestCount = 0

        mockTransport.register(path: "/species-observation-stats") { request in
            requestCount += 1
            #expect(request.url?.path.hasSuffix("/species-observation-stats") == true)
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            })
            #expect(queryItems["species_id"] == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
            #expect(queryItems["scientific_name"] == "Danaus plexippus")
            #expect(MockURLProtocol.bodyData(for: request) == nil)
            return (mockResponse, testData)
        }

        let first = try await networkClient.getSpeciesObservationStats(
            speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "Danaus plexippus"
        )
        let second = try await networkClient.getSpeciesObservationStats(
            speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "  Danaus   plexippus  "
        )

        #expect(first.totalObservations == 450448)
        #expect(second.totalObservations == 450448)
        #expect(requestCount == 1)

        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: "   "
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "not-a-uuid",
                scientificName: "Danaus plexippus"
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: String(repeating: "x", count: 161)
            )
        }
        #expect(requestCount == 1)
    }

    @Test func testGetSpeciesObservationStatsRejectsLegacyOrMismatchedResponses() async throws {
        func responseData(
            schemaVersion: Int,
            speciesId: String,
            scientificName: String
        ) -> Data {
            Data("""
            {
                "schema_version": \(schemaVersion),
                "data": {
                    "species_id": "\(speciesId)",
                    "scientific_name": "\(scientificName)",
                    "source": {
                        "provider": "inaturalist",
                        "scope": "global",
                        "inaturalist_taxon_id": 48662,
                        "fetched_at": "2026-05-17T12:00:00.000Z"
                    },
                    "status": "fresh",
                    "total_observations": 1,
                    "last_observation_date": "2026-05-17",
                    "fetched_at": "2026-05-17T12:00:00.000Z",
                    "provider_errors": [],
                    "seasonality": [],
                    "history": [],
                    "life_stage": [],
                    "sex": []
                }
            }
            """.utf8)
        }

        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        var responses = [
            responseData(
                schemaVersion: 1,
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: "Danaus plexippus"
            ),
            responseData(
                schemaVersion: 2,
                speciesId: "00000000-0000-4000-8000-000000000999",
                scientificName: "Danaus plexippus"
            )
        ]
        var requestCount = 0
        mockTransport.register(path: "/species-observation-stats") { _ in
            requestCount += 1
            return (mockResponse, responses.removeFirst())
        }

        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: "Danaus plexippus"
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: "Danaus plexippus"
            )
        }
        #expect(requestCount == 2)
    }
}
