import Foundation
import Testing

@testable import Merian

@Suite("Explore Share State Endpoints")
@MainActor
struct ExploreShareStateEndpointTests {
    @Test func testGetExploreShareStateConstructsPayloadAndParsesJSON() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let scanID = "019f7004-1caa-78e2-b1f0-98f806955892"
        let postID = "019f7004-23fc-7fa6-9852-2cf928e9e81d"
        let testData = Data("""
        {
            "data": {
                "scan_id": "\(scanID)",
                "post_id": "\(postID)",
                "shared_at": "2026-04-29T22:18:03.000Z",
                "community_request_id": null,
                "community_request_status": null,
                "is_explore_feed_visible": true,
                "location_sharing": "open"
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        fixture.transport.register(path: "/get-scan-explore-share-state") { request in
            #expect(request.url?.path.hasSuffix("/get-scan-explore-share-state") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(payload?["scan_id"] as? String == scanID)
            return (mockResponse, testData)
        }

        let response = try await fixture.client.getExploreShareState(
            scanId: scanID
        )

        #expect(response.scanId == scanID)
        #expect(response.postId == postID)
        #expect(response.sharedAt == "2026-04-29T22:18:03.000Z")
        #expect(response.communityRequestId == nil)
        #expect(response.communityRequestStatus == nil)
        #expect(response.isExploreFeedVisible == true)
        #expect(response.locationSharing == .open)
    }

    @Test func testGetExploreShareStateParsesCommunityRequestState() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let scanID = "019f7004-3505-73c0-9e4a-26fe8db264e8"
        let postID = "019f7004-3a81-7cc4-9bd4-dcf6aef91ec3"
        let requestID = "019f7004-41d5-7e34-b08a-d4ec37a3f647"
        let testData = Data("""
        {
            "data": {
                "scan_id": "\(scanID)",
                "post_id": "\(postID)",
                "shared_at": "2026-04-29T22:18:03.000Z",
                "community_request_id": "\(requestID)",
                "community_request_status": "needs_id",
                "is_explore_feed_visible": false,
                "location_sharing": "obscured"
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        fixture.transport.register(path: "/get-scan-explore-share-state") { request in
            #expect(request.url?.path.hasSuffix("/get-scan-explore-share-state") == true)
            return (mockResponse, testData)
        }

        let response = try await fixture.client.getExploreShareState(
            scanId: scanID
        )

        #expect(response.scanId == scanID)
        #expect(response.postId == postID)
        #expect(response.communityRequestId == requestID)
        #expect(response.communityRequestStatus == .needsId)
        #expect(response.isExploreFeedVisible == false)
        #expect(response.locationSharing == .obscured)
    }

    @Test func testGetExploreShareStateAcceptsServerHiddenPostWithoutCommunityRequest() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let scanID = "019f7004-4b3a-7d6a-a8fd-5b7db04e6395"
        let postID = "019f7004-50b2-7a28-8972-38fc70217558"
        let testData = Data("""
        {
            "data": {
                "scan_id": "\(scanID)",
                "post_id": "\(postID)",
                "shared_at": "2026-07-29T12:00:00.000Z",
                "community_request_id": null,
                "community_request_status": null,
                "is_explore_feed_visible": false,
                "location_sharing": "open"
            }
        }
        """.utf8)
        let responseURL = try #require(URL(string: "https://example.com"))
        let mockResponse = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        fixture.transport.register(path: "/get-scan-explore-share-state") { _ in
            (mockResponse, testData)
        }

        let response = try await fixture.client
            .getExploreShareState(scanId: scanID)

        #expect(response.postId == postID)
        #expect(response.communityRequestId == nil)
        #expect(response.isExploreFeedVisible == false)
        #expect(response.locationSharing == .open)
    }

    @Test func testGetExploreShareStateRejectsUnconfirmedState() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let scanID = "019f7004-3505-73c0-9e4a-26fe8db264e8"
        let responseURL = try #require(URL(string: "https://example.com"))
        let mockResponse = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        let invalidResponses = [
            Data("""
            {
              "data": {
                "scan_id": "019f7004-3505-73c0-9e4a-26fe8db264e9",
                "post_id": "019f7004-3a81-7cc4-9bd4-dcf6aef91ec3",
                "shared_at": "2026-04-29T22:18:03.000Z",
                "community_request_id": null,
                "community_request_status": null,
                "is_explore_feed_visible": true,
                "location_sharing": "open"
              }
            }
            """.utf8),
            Data("""
            {
              "data": {
                "scan_id": "\(scanID)",
                "post_id": null,
                "shared_at": null,
                "community_request_id": null,
                "community_request_status": null,
                "is_explore_feed_visible": true,
                "location_sharing": "open"
              }
            }
            """.utf8),
            Data("""
            {
              "data": {
                "scan_id": "\(scanID)",
                "post_id": "019f7004-3a81-7cc4-9bd4-dcf6aef91ec3",
                "shared_at": "not-a-timestamp",
                "community_request_id": null,
                "community_request_status": null,
                "is_explore_feed_visible": true,
                "location_sharing": "open"
              }
            }
            """.utf8),
            Data("""
            {
              "data": {
                "scan_id": "\(scanID)",
                "post_id": "019f7004-3a81-7cc4-9bd4-dcf6aef91ec3",
                "shared_at": "2026-04-29T22:18:03.000Z",
                "community_request_id": null,
                "community_request_status": null,
                "location_sharing": "open"
              }
            }
            """.utf8),
            Data("""
            {
              "data": {
                "scan_id": "\(scanID)",
                "post_id": "019f7004-3a81-7cc4-9bd4-dcf6aef91ec3",
                "shared_at": "2026-04-29T22:18:03.000Z",
                "community_request_id": null,
                "community_request_status": null,
                "is_explore_feed_visible": true,
                "location_sharing": "future-unknown-mode"
              }
            }
            """.utf8)
        ]

        for invalidResponse in invalidResponses {
            fixture.transport.register(path: "/get-scan-explore-share-state") { _ in
                (mockResponse, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await fixture.client
                    .getExploreShareState(scanId: scanID)
            }
        }
    }

    private typealias Responses = ExplorePostManagementEndpointResponses

    @Test(arguments: ["2026-04-29T22:18:03.000Z", "2026-04-29T22:18:03Z"])
    func shareStateKeepsValidatedValuesRatherThanNormalizingThem(_ timestamp: String) async throws {
        let scanID = Responses.scanID.uppercased()
        let postID = " \(Responses.postID.uppercased()) \n"
        let requestID = " \(Responses.requestID.uppercased()) \n"
        let json = try Responses.shareState(
            scanID: scanID, postID: postID, sharedAt: timestamp,
            requestID: requestID, requestStatus: "resolved", visible: true, location: "HiDdEn"
        )
        try await ExplorePostManagementEndpointRequestCase.shareState.withResponse(json) { client in
            let state = try await client.getExploreShareState(scanId: Responses.scanID)
            #expect(state.scanId == scanID && state.postId == postID)
            #expect(state.communityRequestId == requestID && state.communityRequestStatus == .resolved)
            #expect(state.sharedAt == timestamp && state.isExploreFeedVisible)
            #expect(state.locationSharing == .privateLocation)
        }
    }

    @Test(arguments: [true, false], ["resolved", "withdrawn", "needs_id"])
    func communityVisibilityKeepsItsExistingTopology(visible: Bool, status: String) async throws {
        let json = try Responses.shareState(
            requestID: Responses.requestID, requestStatus: status, visible: visible
        )
        try await ExplorePostManagementEndpointRequestCase.shareState.withResponse(json) { client in
            if visible && status == "needs_id" {
                await #expect(throws: MerianError.invalidResponse) {
                    try await client.getExploreShareState(scanId: Responses.scanID)
                }
            } else {
                let state = try await client.getExploreShareState(scanId: Responses.scanID)
                #expect(state.isExploreFeedVisible == visible)
                #expect(state.communityRequestStatus?.rawValue == status)
            }
        }
    }

    @Test(arguments: [true, false])
    func noPostAllowsAbsentOrNullOptionalFields(_ omitFields: Bool) async throws {
        let json = omitFields
            ? #"{"data":{"scan_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","is_explore_feed_visible":false,"location_sharing":"obscured"}}"#
            : try Responses.shareState(postID: nil, sharedAt: nil, visible: false, location: "obscured")
        try await ExplorePostManagementEndpointRequestCase.shareState.withResponse(json) { client in
            let state = try await client.getExploreShareState(scanId: Responses.scanID)
            #expect(state.postId == nil && state.sharedAt == nil)
            #expect(state.communityRequestId == nil && state.communityRequestStatus == nil)
            #expect(!state.isExploreFeedVisible && state.locationSharing == .obscured)
        }
    }

    @Test func malformedAndContradictoryShareStateNeverBecomesConfirmed() async throws {
        let invalidStates = try [
            Responses.shareState(scanID: " \(Responses.scanID) "),
            Responses.shareState(postID: ""),
            Responses.shareState(postID: "not-a-uuid"),
            Responses.shareState(postID: nil),
            Responses.shareState(sharedAt: nil),
            Responses.shareState(sharedAt: ""),
            Responses.shareState(requestID: Responses.requestID),
            Responses.shareState(requestStatus: "resolved"),
            Responses.shareState(requestID: "", requestStatus: "resolved"),
            Responses.shareState(requestID: "bad-request", requestStatus: "resolved"),
            Responses.shareState(requestID: Responses.requestID, requestStatus: "unknown"),
            Responses.shareState(postID: nil, sharedAt: nil, requestID: Responses.requestID,
                                 requestStatus: "resolved", visible: false),
            Responses.shareState(location: nil),
            Responses.shareState(location: ""),
            Responses.shareState(location: " private "),
            Responses.shareState(location: "future-value")
        ]
        for json in invalidStates {
            try await ExplorePostManagementEndpointRequestCase.shareState.withResponse(json) { client in
                await #expect(throws: MerianError.invalidResponse) {
                    try await client.getExploreShareState(scanId: Responses.scanID)
                }
            }
        }
    }

    @Test(arguments: ["missing", "null", "string", "number"])
    func visibilityIsRequiredAndMustBeABoolean(_ variant: String) async throws {
        let suffix: String
        switch variant {
        case "missing": suffix = ""
        case "null": suffix = #","is_explore_feed_visible":null"#
        case "string": suffix = #","is_explore_feed_visible":"false""#
        default: suffix = #","is_explore_feed_visible":0"#
        }
        let json = #"{"data":{"scan_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","location_sharing":"open"\#(suffix)}}"#
        try await ExplorePostManagementEndpointRequestCase.shareState.withResponse(json) { client in
            await #expect(throws: MerianError.invalidResponse) {
                try await client.getExploreShareState(scanId: Responses.scanID)
            }
        }
    }
}
