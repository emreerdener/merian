import Foundation
import Testing

@testable import Merian

@Suite("Account Deletion API Models")
struct AccountDeletionAPIModelsTests {
    @Test func testPreparedAccountDeletionPayloadsUseExactTwoStageProtocol() throws {
        let recovery = String(repeating: "R", count: 43)
        let acknowledgement = String(repeating: "K", count: 43)
        let preparationData = try JSONEncoder().encode(
            AccountDeletionPreparationPayload(
                recoveryCapability: recovery,
                acknowledgementCapability: acknowledgement
            )
        )
        let preparation = try #require(
            JSONSerialization.jsonObject(with: preparationData)
                as? [String: Any]
        )
        #expect(preparation.count == 4)
        #expect(preparation["protocol_version"] as? Int == 2)
        #expect(preparation["operation"] as? String == "prepare")
        #expect(preparation["recovery_capability"] as? String == recovery)
        #expect(
            preparation["acknowledgement_capability"] as? String
                == acknowledgement
        )

        let commitData = try JSONEncoder().encode(
            AccountDeletionCommitPayload(
                recoveryCapability: recovery
            )
        )
        let commit = try #require(
            JSONSerialization.jsonObject(with: commitData)
                as? [String: Any]
        )
        #expect(commit.count == 3)
        #expect(commit["protocol_version"] as? Int == 2)
        #expect(commit["operation"] as? String == "commit")
        #expect(commit["recovery_capability"] as? String == recovery)
        #expect(commit["acknowledgement_capability"] == nil)
    }

    @Test(arguments: [AccountDeletionStatus.prepared, .notCommitted, .pending, .completed])
    func statusAndRequiredDispositionDecodeWithoutDefaults(status: AccountDeletionStatus) throws {
        let data = try AccountDeletionTestSupport.receiptData(status: status)
        let receipt = try JSONDecoder().decode(AccountDeletionReceipt.self, from: data)
        #expect(receipt.success && receipt.status == status)
        #expect(!receipt.manualProviderRevocationRequired)
        #expect(receipt.recoveryCapabilityExpiresAt == AccountDeletionTestSupport.futureExpiry)
        #expect(receipt.protocolVersion == 2)
    }

    @Test(arguments: ["success", "status", "manual_provider_revocation_required"], ["missing", "null", "wrongType"])
    func requiredFieldsRejectAbsenceNullAndWrongTypes(key: String, corruption: String) throws {
        var payload: [String: Any] = ["success": true, "status": "pending", "manual_provider_revocation_required": false]
        switch corruption {
        case "missing": payload.removeValue(forKey: key)
        case "null": payload[key] = NSNull()
        default: payload[key] = ["invalid"]
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(AccountDeletionReceipt.self, from: data) }
    }

    @Test(arguments: [false, true])
    func optionalFieldsAllowAbsenceOrNull(useNull: Bool) throws {
        var payload: [String: Any] = ["success": true, "status": "pending", "manual_provider_revocation_required": true]
        if useNull {
            for key in ["recovery_capability_expires_at", "recovery_acknowledged", "protocol_version"] {
                payload[key] = NSNull()
            }
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let receipt = try JSONDecoder().decode(AccountDeletionReceipt.self, from: data)
        #expect(receipt.manualProviderRevocationRequired)
        #expect(receipt.recoveryCapabilityExpiresAt == nil)
        #expect(receipt.recoveryAcknowledged == nil && receipt.protocolVersion == nil)
    }

    @Test(arguments: ["recovery_capability_expires_at", "recovery_acknowledged", "protocol_version"])
    func optionalFieldsDoNotCoerceWrongWireTypes(key: String) throws {
        var payload: [String: Any] = ["success": true, "status": "pending", "manual_provider_revocation_required": false]
        payload[key] = ["invalid"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(AccountDeletionReceipt.self, from: data) }
    }
}
