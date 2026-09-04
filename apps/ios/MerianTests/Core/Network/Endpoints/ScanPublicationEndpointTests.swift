import Foundation
import Testing

@testable import Merian

@Suite("Scan Publication Endpoints")
@MainActor
struct ScanPublicationEndpointTests {
    @Test func testExploreShareSendsStableAIIdempotencyKey() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let requestID = "019f6ff1-89ad-7d42-84d8-74dc8b1b5bb0"
        let scanID = "019f6ff1-9ef3-77b1-a331-a86678f53043"

        fixture.transport.register(path: "/share-scan-to-explore") { request in
            #expect(
                request.value(forHTTPHeaderField: "Idempotency-Key")
                    == requestID
            )
            return try NetworkEndpointTestSupport.response(
                to: request,
                json: Self.shareResponse(scanID: scanID)
            )
        }

        let result = try await fixture.client.shareScanToExplore(
            scanId: scanID,
            idempotencyKey: requestID
        )

        #expect(result.success)
        #expect(result.scanId == scanID)
    }

    @Test func testExploreShareRejectsContradictorySuccessResponses() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let requestID = "019faaac-bfd7-7a2e-99ea-100554f24f01"
        let scanID = "019faaac-c177-71a6-883d-eb5a50b7d013"
        let invalidResponseBodies = [
            Self.shareResponse(scanID: scanID, success: false),
            Self.shareResponse(scanID: scanID, postID: "not-a-uuid"),
            Self.shareResponse(
                scanID: "019faaac-cb5f-724d-8112-16701a8d3645"
            ),
            Self.shareResponse(scanID: scanID, sharedAt: "not-a-timestamp"),
            Self.shareResponse(scanID: scanID, publicationStatus: "draft"),
            Self.shareResponse(
                scanID: scanID,
                includesLocationSharing: false
            ),
            Self.shareResponse(
                scanID: scanID,
                includesPublicationStatus: false
            ),
            Self.shareResponse(
                scanID: scanID,
                locationSharing: "future-unknown-mode"
            )
        ]

        for responseJSON in invalidResponseBodies {
            fixture.transport.register(
                path: "/share-scan-to-explore"
            ) { request in
                try NetworkEndpointTestSupport.response(
                    to: request,
                    json: responseJSON
                )
            }

            await #expect(throws: MerianError.invalidResponse) {
                try await fixture.client.shareScanToExplore(
                    scanId: scanID,
                    idempotencyKey: requestID
                )
            }
        }

        fixture.transport.register(path: "/share-scan-to-explore") { request in
            try NetworkEndpointTestSupport.response(
                to: request,
                json: Self.shareResponse(
                    scanID: scanID,
                    locationSharing: "open"
                )
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await fixture.client.shareScanToExplore(
                scanId: scanID,
                locationSharing: .privateLocation,
                idempotencyKey: requestID
            )
        }
    }

    @Test func testExploreShareSendsMissingScanRecoveryPayload() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let scanID = "019f6ff1-9ef3-77b1-a331-a86678f53043"
        let userID = "019f6ff1-c6c4-77b1-a331-a86678f53043"
        let recoveryScan = ScanLifecycleNetworkFixtures.recoveryScan(
            id: scanID,
            userId: userID,
            gpsLatExact: 30.2672
        )

        fixture.transport.register(path: "/share-scan-to-explore") { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let recovery = try #require(
                payload["recovery_scan"] as? [String: Any]
            )
            #expect(recovery["id"] as? String == scanID)
            #expect(recovery["user_id"] as? String == userID)
            #expect(recovery["image_storage_urls"] as? [String] == [])
            #expect(recovery["geoprivacy"] as? String == "private")
            #expect(recovery["gps_lat_exact"] as? Double == 30.2672)
            #expect(recovery["gps_lat_public"] == nil)
            return try NetworkEndpointTestSupport.response(
                to: request,
                json: Self.shareResponse(scanID: scanID)
            )
        }

        let result = try await fixture.client.shareScanToExplore(
            scanId: scanID,
            idempotencyKey: "019f6ff1-e6c4-77b1-a331-a86678f53043",
            recoveryScan: recoveryScan
        )

        #expect(result.success)
        #expect(result.scanId == scanID)
    }

    @Test func testCommunityRequestSendsStableAIIdempotencyKey() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let requestID = "019f7004-cb18-7cd0-84e5-b4a97b759666"
        let scanID = "019f7004-d6c4-7da1-8561-9cc101f6db62"
        let restoredImageKey = "staging/user/restored-image.webp"
        let restoredVideoKey = "staging/user/restored-video.mp4"
        let restoredAudioKey = "staging/user/restored-audio.wav"

        fixture.transport.register(
            path: "/request-community-identification"
        ) { request in
            #expect(
                request.value(forHTTPHeaderField: "Idempotency-Key")
                    == requestID
            )
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(
                payload["restored_object_keys"] as? [String]
                    == [restoredImageKey]
            )
            #expect(
                payload["restored_video_object_keys"] as? [String]
                    == [restoredVideoKey]
            )
            #expect(
                payload["restored_audio_object_keys"] as? [String]
                    == [restoredAudioKey]
            )
            return try NetworkEndpointTestSupport.response(
                to: request,
                json: Self.communityResponse(scanID: scanID)
            )
        }

        let result = try await fixture.client.requestCommunityIdentification(
            scanId: scanID,
            restoredObjectKeys: [restoredImageKey],
            restoredVideoObjectKeys: [restoredVideoKey],
            restoredAudioObjectKeys: [restoredAudioKey],
            idempotencyKey: requestID
        )

        #expect(result.scanId == scanID)
        #expect(result.status == .needsId)
    }

    @Test func testCommunityRequestRejectsUnconfirmedSuccessResponse() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let scanID = "019f7004-d6c4-7da1-8561-9cc101f6db62"
        let invalidResponses = [
            Self.communityResponse(scanID: scanID, success: false),
            Self.communityResponse(
                scanID: "019f7004-d6c4-7da1-8561-9cc101f6db63"
            ),
            Self.communityResponse(scanID: scanID, requestedAt: "not-a-timestamp"),
            Self.communityResponse(
                scanID: scanID,
                status: "future-unknown-status"
            )
        ]

        for responseJSON in invalidResponses {
            fixture.transport.register(
                path: "/request-community-identification"
            ) { request in
                try NetworkEndpointTestSupport.response(
                    to: request,
                    json: responseJSON
                )
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await fixture.client.requestCommunityIdentification(
                    scanId: scanID
                )
            }
        }
    }

    private static func shareResponse(
        scanID: String,
        success: Bool = true,
        postID: String = "019faaac-c229-790a-949e-9aeb6a710f32",
        sharedAt: String = "2026-07-28T23:45:00Z",
        locationSharing: String = "private",
        publicationStatus: String = "published",
        includesLocationSharing: Bool = true,
        includesPublicationStatus: Bool = true
    ) -> String {
        var fields = [
            #""success": \#(success ? "true" : "false")"#,
            #""post_id": "\#(postID)""#,
            #""scan_id": "\#(scanID)""#,
            #""shared_at": "\#(sharedAt)""#
        ]
        if includesLocationSharing {
            fields.append(#""location_sharing": "\#(locationSharing)""#)
        }
        if includesPublicationStatus {
            fields.append(
                #""publication_status": "\#(publicationStatus)""#
            )
        }
        return "{\(fields.joined(separator: ","))}"
    }

    private static func communityResponse(
        scanID: String,
        success: Bool = true,
        requestedAt: String = "2026-07-23T18:00:00Z",
        status: String = "needs_id"
    ) -> String {
        """
        {
          "success": \(success),
          "data": {
            "id": "019f7004-e4c2-7feb-8f4d-39ab2a89ca1e",
            "post_id": "019f7004-ee31-7e9e-961d-30b49352f12a",
            "scan_id": "\(scanID)",
            "requested_by": "019f7004-f66f-71bf-845c-bf05dff2eb30",
            "requested_at": "\(requestedAt)",
            "status": "\(status)",
            "initial_taxon_node_id": "019f7004-c59b-74ab-8730-45bcae1bb390",
            "taxonomy_version_id": "019f7004-ca4e-7c3a-a9e8-5ff84002063e",
            "consensus_identification_count": 0
          }
        }
        """
    }
}
