import Foundation
import Testing

@testable import Merian

@Suite("Inference Response Preparation Service")
struct InferenceResponsePreparationServiceTests {
    @Test func exactScanIdentityCarriesTypedSettlement() async throws {
        let accountId = UUID()
        let prepared = try await InferenceResponsePreparationService.live
            .prepare(
                resultData: responseData(
                    scanId: "scan-owner",
                    accountId: accountId
                ),
                telemetry: nil,
                audioFilePaths: ["bird.wav"],
                videoFilePaths: nil,
                expectedScanId: "SCAN-OWNER"
            )

        #expect(prepared.responseMatchesExpectedScanId)
        #expect(prepared.mappedData.scanId == "scan-owner")
        #expect(prepared.mappedData.audioFilePaths == ["bird.wav"])
        #expect(prepared.planUsed == "pro_paid")
        #expect(prepared.fundingSettlement?.scanId == "scan-owner")
        #expect(prepared.fundingSettlement?.accountId == accountId)
        #expect(prepared.fundingSettlement?.planUsed == "pro_paid")
        #expect(
            prepared.fundingSettlement?.entitlementAfter.currentTier == "pro"
        )
    }

    @Test func mismatchedScanIdentityCannotCarrySettlement() async throws {
        let prepared = try await InferenceResponsePreparationService.live
            .prepare(
                resultData: responseData(
                    scanId: "stale-scan",
                    accountId: UUID()
                ),
                telemetry: nil,
                audioFilePaths: nil,
                videoFilePaths: nil,
                expectedScanId: "current-scan"
            )

        #expect(!prepared.responseMatchesExpectedScanId)
        #expect(prepared.mappedData.scanId == "stale-scan")
        #expect(prepared.fundingSettlement == nil)
    }

    @Test func malformedSettlementAccountDoesNotInvalidateSpeciesResult() async throws {
        let prepared = try await InferenceResponsePreparationService.live
            .prepare(
                resultData: responseData(
                    scanId: "scan-owner",
                    accountIdText: "not-a-user-id"
                ),
                telemetry: nil,
                audioFilePaths: nil,
                videoFilePaths: nil,
                expectedScanId: "scan-owner"
            )

        #expect(prepared.responseMatchesExpectedScanId)
        #expect(prepared.mappedData.scanId == "scan-owner")
        #expect(prepared.fundingSettlement == nil)
    }

    @Test func absentExpectedIdentityPreservesServerAssignedResponse() async throws {
        let accountId = UUID()
        let prepared = try await InferenceResponsePreparationService.live
            .prepare(
                resultData: responseData(
                    scanId: "server-assigned-scan",
                    accountId: accountId
                ),
                telemetry: nil,
                audioFilePaths: nil,
                videoFilePaths: nil,
                expectedScanId: nil
            )

        #expect(prepared.responseMatchesExpectedScanId)
        #expect(prepared.mappedData.scanId == "server-assigned-scan")
        #expect(prepared.fundingSettlement?.accountId == accountId)
    }

    private func responseData(
        scanId: String,
        accountId: UUID
    ) -> Data {
        responseData(scanId: scanId, accountIdText: accountId.uuidString)
    }

    private func responseData(
        scanId: String,
        accountIdText: String
    ) -> Data {
        Data(
            """
            {
              "success": true,
              "data": {
                "scan_id": "\(scanId)",
                "common_name": "Test subject",
                "scientific_name": "Test species",
                "is_biological_subject": true,
                "confidence_score": 0.95
              },
              "entitlement": {
                "user_id": "\(accountIdText)",
                "plan_used": "pro_paid",
                "credit_consumed": false,
                "entitlement_after": {
                  "current_plan": "pro_paid",
                  "current_tier": "pro",
                  "is_paid": true,
                  "scans_remaining": 0,
                  "scans_available_to_start": 0,
                  "in_flight_count": 0,
                  "entitlement_version": 1
                }
              }
            }
            """.utf8
        )
    }
}
