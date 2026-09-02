import Foundation
import Testing

@testable import Merian

@Suite("Explore Media Incident Endpoints")
@MainActor
struct ExploreMediaIncidentEndpointTests {
    @Test func testExploreMediaIncidentsRejectsUnknownSuccessShape() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let response = HTTPURLResponse(
            url: try #require(URL(string: "https://example.com")),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        fixture.transport.register(path: "/get-explore-media-incidents") { _ in
            (response, Data(#"{"incidents":[]}"#.utf8))
        }

        await #expect(throws: MerianError.invalidResponse) {
            try await fixture.client.getExploreMediaIncidents()
        }
    }

    @Test func testExploreMediaIncidentsAcceptsLegacyEmptyArrayAtNetworkBoundary() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let response = HTTPURLResponse(
            url: try #require(URL(string: "https://example.com")),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        fixture.transport.register(path: "/get-explore-media-incidents") { _ in
            (response, Data([0x5B, 0x5D]))
        }

        let incidents = try await fixture.client
            .getExploreMediaIncidents()

        #expect(incidents.isEmpty)
    }

    private typealias Responses = ExplorePostManagementEndpointResponses

    @Test(arguments: [true, false])
    func wrappedAndLegacyIncidentsKeepServerOrderAndMetadata(_ legacy: Bool) async throws {
        let json = legacy ? Responses.incidentsArray : Responses.incidents
        try await ExplorePostManagementEndpointRequestCase.incidents.withResponse(json) { client in
            let incidents = try await client.getExploreMediaIncidents()
            #expect(incidents.map(\.postId) == ["quarantined-post", "degraded-post"])
            #expect(incidents.map(\.scanId) == ["quarantined-scan", "degraded-scan"])
            #expect(incidents.map(\.mediaHealthStatus) == [.quarantined, .degraded])
            #expect(incidents.map(\.missingMediaCount) == [2, 1])
            #expect(incidents.map(\.totalMediaCount) == [2, 3])
            #expect(incidents.first?.speciesCommonName == "Test species")
            #expect(incidents.last?.speciesCommonName == nil)
            #expect(incidents.first?.mediaQuarantinedAt == "2026-07-26T12:00:00Z")
            #expect(incidents.last?.mediaQuarantinedAt == nil)
            #expect(incidents.last?.mediaHealthUpdatedAt == "2026-07-26T11:00:00Z")
            #expect(incidents.first?.missingMediaUrls == [
                "https://media.example.test/two.webp", "https://media.example.test/one.webp"
            ])
        }
    }

    @Test func canonicalEmptyIncidentsAreNotARecoveryFailure() async throws {
        try await ExplorePostManagementEndpointRequestCase.incidents.withResponse(#"{"data":[]}"#) { client in
            let incidents = try await client.getExploreMediaIncidents()
            #expect(incidents.isEmpty)
        }
    }

    @Test(arguments: [
        #"{"data":null}"#, #"{"data":{}}"#, #"{"data":[{}]}"#, "[{}]",
        #"{"incidents":[]}"#, "null", "false"
    ])
    func malformedEnvelopeOrEntryRetainsInvalidResponse(_ json: String) async throws {
        try await ExplorePostManagementEndpointRequestCase.incidents.withResponse(json) { client in
            await #expect(throws: MerianError.invalidResponse) {
                try await client.getExploreMediaIncidents()
            }
        }
    }

    @Test(arguments: [true, false])
    func unknownHealthStatusIsRejectedInBothEnvelopes(_ legacy: Bool) async throws {
        let json = (legacy ? Responses.incidentsArray : Responses.incidents)
            .replacingOccurrences(of: "\"degraded\"", with: "\"future-status\"")
        try await ExplorePostManagementEndpointRequestCase.incidents.withResponse(json) { client in
            await #expect(throws: MerianError.invalidResponse) {
                try await client.getExploreMediaIncidents()
            }
        }
    }
}
