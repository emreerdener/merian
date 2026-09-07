import Foundation
@testable import Merian
import Testing

@Suite("Background Inference Policy")
struct BackgroundInferencePolicyTests {
    @Test @MainActor
    func scheduledServerFailureRetryBreaksStatusUploadDeadlock() {
        #expect(
            OfflineQueueManager.isServerRetryableFailureCode(
                OfflineQueueManager.serverRetryableFailureCode
            )
        )
        #expect(
            !OfflineQueueManager.isServerRetryableFailureCode(nil)
        )
        #expect(
            !OfflineQueueManager.isServerRetryableFailureCode(
                "inference_retry"
            )
        )

        #expect(
            !BackgroundInferencePolicy.scanStatusActionPermitsInferenceDispatch(
                .retryAfter(1),
                hasScheduledServerFailureRetry: false
            )
        )
        #expect(
            BackgroundInferencePolicy.scanStatusActionPermitsInferenceDispatch(
                .retryAfter(1),
                hasScheduledServerFailureRetry: true
            )
        )
        #expect(
            BackgroundInferencePolicy.scanStatusActionPermitsInferenceDispatch(
                .unresolved,
                hasScheduledServerFailureRetry: false
            )
        )
        for action in [
            ScanStatusRecoveryAction.recovered,
            .waitForServer(1),
            .terminalFailure("No retry")
        ] {
            #expect(
                !BackgroundInferencePolicy.scanStatusActionPermitsInferenceDispatch(
                    action,
                    hasScheduledServerFailureRetry: true
                )
            )
        }
    }

    @Test func backgroundInferencePlatformRoute404RemainsRetryable() throws {
        let url = try #require(
            URL(string: "https://example.supabase.co/functions/v1/identify-multimodal")
        )
        let officialPayload = Data(
            #"{"code":"NOT_FOUND","message":"Requested function was not found"}"#.utf8
        )
        let platformResponse = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["SB-Error-Code": "NOT_FOUND"]
            )
        )
        let handlerResponse = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: nil,
                headerFields: [
                    "X-Merian-Handler": "1",
                    "SB-Error-Code": "NOT_FOUND"
                ]
            )
        )

        #expect(BackgroundInferencePolicy.shouldRetryBackgroundInferenceRouteFailure(
            statusCode: 404,
            functionRouteEvidence: EdgeFunctionRouteResponseEvidence(
                response: platformResponse
            ),
            responseData: officialPayload
        ))
        #expect(!BackgroundInferencePolicy.shouldRetryBackgroundInferenceRouteFailure(
            statusCode: 404,
            functionRouteEvidence: EdgeFunctionRouteResponseEvidence(
                response: handlerResponse
            ),
            responseData: officialPayload
        ))
        #expect(!BackgroundInferencePolicy.shouldRetryBackgroundInferenceRouteFailure(
            statusCode: 503,
            functionRouteEvidence: EdgeFunctionRouteResponseEvidence(
                response: platformResponse
            ),
            responseData: officialPayload
        ))
    }

    @Test func backgroundInferencePreservesRecoverableHTTPFailures() throws {
        let url = try #require(
            URL(string: "https://example.supabase.co/functions/v1/identify-multimodal")
        )

        func evidence(
            statusCode: Int,
            headers: [String: String] = ["X-Merian-Handler": "1"]
        ) throws -> EdgeFunctionRouteResponseEvidence {
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: headers
                )
            )
            return EdgeFunctionRouteResponseEvidence(response: response)
        }

        for statusCode in [401, 408, 409, 425, 429, 503] {
            #expect(
                BackgroundInferencePolicy.backgroundInferenceResponseDisposition(
                    statusCode: statusCode,
                    functionRouteEvidence: try evidence(statusCode: statusCode),
                    responseData: Data()
                ) == .retry
            )
        }

        let rateLimitEvidence = try evidence(
            statusCode: 429,
            headers: [
                "X-Merian-Handler": "1",
                "Retry-After": "3600"
            ]
        )
        #expect(rateLimitEvidence.retryAfterSeconds == 3600)

        let rejectedPayload = Data(
            #"{"code":"observation_rejected","error":"Unable to process."}"#.utf8
        )
        #expect(
            BackgroundInferencePolicy.backgroundInferenceResponseDisposition(
                statusCode: 400,
                functionRouteEvidence: try evidence(statusCode: 400),
                responseData: rejectedPayload
            ) == .terminal
        )
        #expect(
            BackgroundInferencePolicy.backgroundInferenceResponseDisposition(
                statusCode: 400,
                functionRouteEvidence: try evidence(statusCode: 400),
                responseData: Data(#"{"code":"bad_request"}"#.utf8)
            ) == .needsAttention
        )
        #expect(
            BackgroundInferencePolicy.backgroundInferenceResponseDisposition(
                statusCode: 404,
                functionRouteEvidence: try evidence(statusCode: 404),
                responseData: Data(#"{"code":"not_found"}"#.utf8)
            ) == .needsAttention
        )
        #expect(
            BackgroundInferencePolicy.backgroundInferenceResponseDisposition(
                statusCode: 403,
                functionRouteEvidence: try evidence(statusCode: 403),
                responseData: Data(
                    #"{"code":"ai_consent_required"}"#.utf8
                )
            ) == .consentRequired
        )
        #expect(
            BackgroundInferencePolicy.backgroundInferenceResponseDisposition(
                statusCode: 403,
                functionRouteEvidence: try evidence(statusCode: 403),
                responseData: Data(#"{"code":"forbidden"}"#.utf8)
            ) == .needsAttention
        )
        let validSuccessPayload = Data(
            """
            {
              "success": true,
              "data": {
                "scan_id": "queued-valid-response",
                "is_biological_subject": false,
                "confidence_score": 0
              }
            }
            """.utf8
        )
        #expect(
            BackgroundInferencePolicy.backgroundInferenceResponseDisposition(
                statusCode: 200,
                functionRouteEvidence: try evidence(statusCode: 200),
                responseData: validSuccessPayload
            ) == .success
        )
        for invalidSuccessPayload in [
            Data(),
            Data(#"{"success":true,"data":"truncated"}"#.utf8),
            Data(
                #"{"success":false,"data":{"scan_id":"queued-failure","confidence_score":0}}"#.utf8
            ),
            Data(
                #"{"success":true,"data":{"scan_id":"queued-missing-confidence"}}"#.utf8
            ),
            Data(
                #"{"success":true,"data":{"scan_id":"queued-invalid-confidence","confidence_score":2}}"#.utf8
            )
        ] {
            #expect(
                BackgroundInferencePolicy.backgroundInferenceResponseDisposition(
                    statusCode: 200,
                    functionRouteEvidence: try evidence(statusCode: 200),
                    responseData: invalidSuccessPayload
                ) == .retry
            )
        }
    }

    @Test func testScanStatusRecoveryActionRespectsServerIngestionState() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = try #require(
            formatter.date(from: "2026-07-05T15:00:00.000Z")
        )
        let finalizing = ScanStatusResponse(
            status: .notFound,
            jobStatus: .finalizing,
            jobStage: "video_promotion_started",
            jobAttemptCount: 1,
            retryAfter: "2026-07-05T15:02:00.000Z",
            lastError: nil
        )
        let retryable = ScanStatusResponse(
            status: .notFound,
            jobStatus: .failedRetryable,
            jobStage: "video_promotion_failed",
            jobAttemptCount: 1,
            retryAfter: nil,
            lastError: "Video promotion failed."
        )
        let serverDirectedRetryable = ScanStatusResponse(
            status: .notFound,
            jobStatus: .failedRetryable,
            jobStage: "video_promotion_failed",
            jobAttemptCount: 1,
            retryAfter: "2026-07-05T15:02:00.000Z",
            lastError: "Video promotion failed."
        )
        let staleRetryDate = ScanStatusResponse(
            status: .notFound,
            jobStatus: .retrying,
            jobStage: "video_promotion_failed",
            jobAttemptCount: 1,
            retryAfter: "2026-07-05T14:59:00.000Z",
            lastError: "Retry already due."
        )
        let terminal = ScanStatusResponse(
            status: .notFound,
            jobStatus: .failed,
            jobStage: "moderation_rejected",
            jobAttemptCount: 1,
            retryAfter: nil,
            lastError: "Rejected by moderation."
        )
        let found = ScanStatusResponse(
            status: .found,
            jobStatus: nil,
            jobStage: nil,
            jobAttemptCount: nil,
            retryAfter: nil,
            lastError: nil
        )

        #expect(BackgroundInferencePolicy.scanStatusRecoveryAction(for: found, now: now) == .recovered)
        #expect(BackgroundInferencePolicy.scanStatusRecoveryAction(for: finalizing, now: now) == .waitForServer(120))
        #expect(BackgroundInferencePolicy.scanStatusRecoveryAction(for: retryable, now: now) == .retryAfter(30))
        #expect(
            BackgroundInferencePolicy.scanStatusRecoveryAction(
                for: serverDirectedRetryable,
                now: now
            ) == .retryAfter(120)
        )
        #expect(BackgroundInferencePolicy.scanStatusRecoveryAction(for: staleRetryDate, now: now) == .waitForServer(1))
        #expect(BackgroundInferencePolicy.scanStatusRecoveryAction(for: terminal, now: now) == .terminalFailure("Rejected by moderation."))
        #expect(
            BackgroundInferencePolicy.requiresMediaRestagingAfterServerFailure(
                ScanStatusResponse(
                    status: .notFound,
                    jobStatus: .failedRetryable,
                    jobStage: "background_ingestion_failed",
                    jobAttemptCount: 1,
                    retryAfter: nil,
                    lastError: "Scan insert failed."
                )
            )
        )
        #expect(
            BackgroundInferencePolicy.requiresMediaRestagingAfterServerFailure(
                ScanStatusResponse(
                    status: .notFound,
                    jobStatus: .failedRetryable,
                    jobStage: "identity_merge_interrupted",
                    jobAttemptCount: 1,
                    retryAfter: nil,
                    lastError: "Account ownership changed."
                )
            )
        )
        #expect(
            BackgroundInferencePolicy.requiresMediaRestagingAfterServerFailure(retryable)
        )
        #expect(
            !BackgroundInferencePolicy.requiresMediaRestagingAfterServerFailure(
                ScanStatusResponse(
                    status: .notFound,
                    jobStatus: .failedRetryable,
                    jobStage: "ai_inference_failed",
                    jobAttemptCount: 1,
                    retryAfter: nil,
                    lastError: "Provider request failed."
                )
            )
        )
        #expect(
            !BackgroundInferencePolicy.requiresMediaRestagingAfterServerFailure(
                ScanStatusResponse(
                    status: .found,
                    jobStatus: .failedRetryable,
                    jobStage: "background_ingestion_failed",
                    jobAttemptCount: 1,
                    retryAfter: nil,
                    lastError: "Post-insert finalization failed."
                )
            )
        )
    }
}
