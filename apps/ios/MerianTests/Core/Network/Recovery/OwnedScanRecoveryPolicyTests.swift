import Foundation
import Testing

@testable import Merian

@Suite("Owned Scan Recovery Policy")
@MainActor
struct OwnedScanRecoveryPolicyTests {
    @Test func testExploreCloudScanRestoreUsesStableNotFoundCodeWithLegacyFallback() {
        let codedMissing = MerianError.httpError(
            statusCode: 404,
            message: #"{"error":"Observation unavailable.","code":"not_found"}"#
        )
        let legacyMissing = MerianError.httpError(
            statusCode: 404,
            message: "Legacy response: Scan not found."
        )
        let contradictoryCode = MerianError.httpError(
            statusCode: 404,
            message: #"{"error":"Scan not found.","code":"forbidden"}"#
        )
        let transientFailure = MerianError.httpError(
            statusCode: 503,
            message: #"{"error":"Scan not found.","code":"not_found"}"#
        )

        #expect(MerianNetworkClient.shouldAttemptExploreCloudScanRestore(
            after: codedMissing
        ))
        #expect(MerianNetworkClient.shouldAttemptExploreCloudScanRestore(
            after: legacyMissing
        ))
        #expect(!MerianNetworkClient.shouldAttemptExploreCloudScanRestore(
            after: contradictoryCode
        ))
        #expect(!MerianNetworkClient.shouldAttemptExploreCloudScanRestore(
            after: transientFailure
        ))
    }

    @Test func testFieldChatCloudPreflightRejectsMismatchedRecordIdentity() async {
        let client = MerianNetworkClient()
        let record = LocalScanRecord(
            speciesId: "field_chat_identity_species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )

        await #expect(throws: MerianError.invalidResponse) {
            try await client.ensureCloudScanAvailableForFieldChat(
                scan: record,
                expectedScanId: UUID().uuidString.lowercased()
            )
        }
    }

    @Test func testMissingScanRecoveryNeverRacesActiveOrRetryableIngestion() {
        #expect(OwnedScanRecoveryPolicy.action(for: .processing) == .retryStatus)
        #expect(OwnedScanRecoveryPolicy.action(for: .finalizing) == .retryStatus)
        #expect(OwnedScanRecoveryPolicy.action(for: .retrying) == .retryStatus)
        #expect(OwnedScanRecoveryPolicy.action(for: .failedRetryable) == .deferRecovery)
        #expect(OwnedScanRecoveryPolicy.action(for: .failed) == .recover)
        #expect(OwnedScanRecoveryPolicy.action(for: .complete) == .recover)
        #expect(OwnedScanRecoveryPolicy.action(for: nil) == .recover)
        #expect(
            OwnedScanRecoveryPolicy.action(
                for: .failed,
                jobStage: "moderation_rejected",
                jobLastError: "Multimodal media rejected by moderation."
            ) == .deferRecovery
        )
        #expect(
            OwnedScanRecoveryPolicy.action(
                for: .failed,
                jobStage: "moderation_rejected",
                jobLastError: "Media rejected by moderation."
            ) == .deferRecovery
        )
        #expect(
            OwnedScanRecoveryPolicy.action(
                for: .failed,
                jobStage: "ai_inference_non_stop_finish",
                jobLastError: "AI finish reason: SAFETY"
            ) == .deferRecovery
        )
        #expect(
            OwnedScanRecoveryPolicy.action(
                for: .failed,
                jobStage: "ai_inference_non_stop_finish",
                jobLastError: "AI finish reason: PROHIBITED_CONTENT"
            ) == .deferRecovery
        )
        #expect(
            OwnedScanRecoveryPolicy.action(
                for: .failed,
                jobStage: "moderation_rejected",
                jobLastError: "Database trigger rejected insert."
            ) == .recover
        )
    }
}
