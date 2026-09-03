import Foundation
import Testing

@testable import Merian

@Suite("Scan Status Endpoints")
@MainActor
struct ScanStatusEndpointTests {
    @Test func testCheckScanStatusDetailsDecodesJobStateAndRequiredVideoCount() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let responseData = Data("""
        {
          "status": "not_found",
          "job_status": "finalizing",
          "job_stage": "video_promotion_started",
          "job_attempt_count": 2,
          "retry_after": "2026-07-05T15:00:00.000Z",
          "last_error": null
        }
        """.utf8)

        fixture.transport.register(path: "/check-scan-status") { request in
            #expect(request.url?.path.hasSuffix("/check-scan-status") == true)
            let bodyData = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(payload["scan_id"] as? String == "scan-video-status")
            #expect(payload["required_video_count"] as? Int == 1)
            return (mockResponse, responseData)
        }

        let status = try await fixture.client.checkScanStatusDetails(
            scanId: "scan-video-status",
            requiredVideoCount: 1
        )

        #expect(status.status == .notFound)
        #expect(status.jobStatus == .finalizing)
        #expect(status.jobStage == "video_promotion_started")
        #expect(status.jobAttemptCount == 2)
        #expect(status.retryAfter == "2026-07-05T15:00:00.000Z")
        #expect(status.lastError == nil)

        let legacyStatus = try await fixture.client.checkScanStatus(
            scanId: "scan-video-status",
            requiredVideoCount: 1
        )
        #expect(legacyStatus == "not_found")
    }

    @Test func testCheckScanStatusDetailsSendsOwnedRecoveryPayload() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let scanID = "019f6ff1-9ef3-77b1-a331-a86678f53043"
        let userID = "019f6ff1-c6c4-77b1-a331-a86678f53043"
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let recoveryScan = OwnedScanRecoveryPayload(
            id: scanID,
            userId: userID,
            speciesId: "019f6ff1-d6c4-77b1-a331-a86678f53043",
            confirmedSpeciesId: nil,
            imageStorageUrls: [],
            timestamp: "2026-07-23T18:00:00Z",
            gpsLatExact: nil,
            gpsLongExact: nil,
            gpsLatPublic: nil,
            gpsLongPublic: nil,
            gpsElevation: nil,
            geoprivacy: "private",
            weatherCondition: "Clear",
            weatherTemperatureF: 86,
            aiConfidenceScore: 0.94,
            ecologyType: "wild",
            isInvasive: false,
            invasiveStatusRegion: nil,
            invasiveRationale: nil,
            invasiveConfidence: nil,
            isLiveCapture: true,
            isBiologicalSubject: true,
            aiReasoning: "Long bill and dark crown.",
            semanticLocation: "Synthetic fixture region",
            publicLocationLabel: nil,
            inferenceTier: "flash",
            imageQualityScore: 82,
            userIdentificationOverride: nil,
            userConfirmedIdentification: false,
            userReviewState: "unreviewed"
        )

        fixture.transport.register(path: "/check-scan-status") { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let recovery = try #require(payload["recovery_scan"] as? [String: Any])
            #expect(payload["scan_id"] as? String == scanID)
            #expect(recovery["id"] as? String == scanID)
            #expect(recovery["user_id"] as? String == userID)
            #expect(recovery["image_storage_urls"] as? [String] == [])
            #expect(recovery["geoprivacy"] as? String == "private")
            return (response, Data(#"{"status":"found"}"#.utf8))
        }

        let status = try await fixture.client.checkScanStatusDetails(
            scanId: scanID,
            recoveryScan: recoveryScan
        )

        #expect(status.isFound)
    }

    @Test func testCheckScanStatusRejectsMalformedOrMismatchedSuccess() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let scanID = "019f6ff1-9ef3-77b1-a331-a86678f53043"
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let invalidResponses = [
            Data(#"{"status":"unknown"}"#.utf8),
            Data(#"{"status":"found","scan_id":"019f6ff1-c6c4-77b1-a331-a86678f53043"}"#.utf8),
            Data(#"{"status":"not_found","job_attempt_count":-1}"#.utf8),
            Data(#"{"ok":true}"#.utf8)
        ]

        for invalidResponse in invalidResponses {
            fixture.transport.register(path: "/check-scan-status") { _ in
                (response, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await fixture.client.checkScanStatusDetails(
                    scanId: scanID
                )
            }
        }
    }

    @Test func testBulkScanStatusRejectsDuplicateMissingOrForeignRows() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let firstScanID = "019f6ff1-9ef3-77b1-a331-a86678f53043"
        let secondScanID = "019f6ff1-c6c4-77b1-a331-a86678f53043"
        let foreignScanID = "019f6ff1-d6c4-77b1-a331-a86678f53043"
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let invalidResponses = [
            Data("""
            {"results":[
              {"scan_id":"\(firstScanID)","status":"found"},
              {"scan_id":"\(firstScanID)","status":"found"}
            ]}
            """.utf8),
            Data("""
            {"results":[
              {"scan_id":"\(firstScanID)","status":"found"}
            ]}
            """.utf8),
            Data("""
            {"results":[
              {"scan_id":"\(firstScanID)","status":"found"},
              {"scan_id":"\(foreignScanID)","status":"not_found"}
            ]}
            """.utf8),
            Data("""
            {"results":[
              {"scan_id":"\(firstScanID)","status":"found"},
              {"scan_id":"\(secondScanID)","status":"not_found",
               "job_attempt_count":-1}
            ]}
            """.utf8)
        ]

        for invalidResponse in invalidResponses {
            fixture.transport.register(path: "/check-scan-status") { _ in
                (response, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await fixture.client.checkScanStatuses([
                    firstScanID: 0,
                    secondScanID: 1
                ])
            }
        }
    }
}
