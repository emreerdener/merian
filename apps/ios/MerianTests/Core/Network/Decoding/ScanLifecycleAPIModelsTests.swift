import Foundation
import Testing

@testable import Merian

@Suite("Scan Lifecycle API Models")
struct ScanLifecycleAPIModelsTests {
    @Test func explicitWireKeysRetainEveryStatusField() throws {
        let response = try decode(ScanLifecycleNetworkFixtures.detailedStatusJSON)
        #expect(response.scanId == ScanLifecycleNetworkFixtures.scanID)
        #expect(response.status == .notFound && !response.isFound)
        #expect(response.jobStatus == .finalizing)
        #expect(response.jobStage == "video_promotion_started")
        #expect(response.jobAttemptCount == 2)
        #expect(response.retryAfter == "2026-09-01T12:00:00Z")
        #expect(response.lastError == "Synthetic retry detail")
        #expect(response.complimentaryState == .held)
    }

    @Test func minimalCompatibilityResponseKeepsOptionalFieldsAbsent() throws {
        let response = try decode(#"{"status":"found"}"#)
        #expect(response.isFound)
        #expect(response.scanId == nil && response.jobStatus == nil && response.jobStage == nil)
        #expect(response.jobAttemptCount == nil && response.retryAfter == nil && response.lastError == nil)
        #expect(response.complimentaryState == nil)
    }

    @Test func knownJobStatesKeepOnlyTheReviewedLegacyAlias() throws {
        let values: [(String, ScanIngestionJobStatus)] = [
            ("processing", .processing), ("finalizing", .finalizing), ("retrying", .retrying),
            ("failed_retryable", .failedRetryable), ("failed", .failed), ("complete", .complete),
            ("failed_terminal", .failed)
        ]
        for (raw, expected) in values {
            let response = try decode(#"{"status":"not_found","job_status":"\#(raw)"}"#)
            #expect(response.jobStatus == expected)
        }
    }

    @Test func complimentarySettlementStatesStayDistinct() throws {
        let values: [(String, ComplimentaryScanState?)] = [
            (#""held""#, .held), (#""consumed""#, .consumed), (#""released""#, .released), ("null", nil)
        ]
        for (raw, expected) in values {
            let response = try decode(#"{"status":"found","complimentary_state":\#(raw)}"#)
            #expect(response.complimentaryState == expected)
        }
    }

    @Test func unknownEnumAndWrongScalarValuesFailWireDecoding() {
        for json in [
            #"{"status":"FOUND"}"#, #"{"status":"unknown"}"#,
            #"{"status":"found","job_status":"FAILED_TERMINAL"}"#,
            #"{"status":"found","job_status":"new_state"}"#,
            #"{"status":"found","complimentary_state":"pending"}"#,
            #"{"status":"found","job_attempt_count":"2"}"#,
            #"{"status":"found","job_attempt_count":true}"#
        ] {
            #expect(throws: DecodingError.self) { try decode(json) }
        }
    }

    @Test func additiveFieldsDoNotChangeExplicitKeyDecoding() throws {
        let response = try decode("""
        {"status":"found","scanId":"ignored-alias","jobStatus":"processing",
         "jobAttemptCount":9,"schema_version":999,"future_field":[]}
        """)
        #expect(response.scanId == nil && response.jobStatus == nil && response.jobAttemptCount == nil)
        #expect(response.isFound)
    }

    private func decode(_ json: String) throws -> ScanStatusResponse {
        try JSONDecoder().decode(ScanStatusResponse.self, from: Data(json.utf8))
    }
}
