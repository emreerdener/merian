import Foundation
import Testing

@testable import Merian

@Suite("Account Deletion Response Decoder")
struct AccountDeletionResponseDecoderTests {
    private typealias Operation = AccountDeletionResponseDecoder.Operation

    @Test(arguments: [AccountDeletionStatus.prepared, .notCommitted, .pending, .completed], [200, 201, 202])
    func intakeAndCommitRequireMatchingHTTPAndReceiptStatus(status: AccountDeletionStatus, httpStatus: Int) throws {
        let data = try AccountDeletionTestSupport.receiptData(status: status)
        let accepted = (status == .pending && httpStatus == 202) || (status == .completed && httpStatus == 200)
        for operation in [Operation.intake(requiresRecoveryExpiry: false), .intake(requiresRecoveryExpiry: true), .commit] {
            if accepted {
                #expect(try decode(data, statusCode: httpStatus, operation: operation).status == status)
            } else {
                #expect(throws: MerianError.invalidResponse) { try decode(data, statusCode: httpStatus, operation: operation) }
            }
        }
    }

    @Test(arguments: [AccountDeletionStatus.prepared, .notCommitted, .pending, .completed], [200, 202])
    func preparationRequiresOnlyThePrepared200Receipt(status: AccountDeletionStatus, httpStatus: Int) throws {
        let data = try AccountDeletionTestSupport.receiptData(status: status)
        if status == .prepared && httpStatus == 200 {
            #expect(try decode(data, operation: .preparation).status == .prepared)
        } else {
            #expect(throws: MerianError.invalidResponse) { try decode(data, statusCode: httpStatus, operation: .preparation) }
        }
    }

    @Test(arguments: [nil, 1, 2, 3] as [Int?])
    func versionTwoIsRequiredOnlyByVersionTwoOperations(version: Int?) throws {
        let pending = try AccountDeletionTestSupport.receiptData(protocolVersion: version)
        let prepared = try AccountDeletionTestSupport.receiptData(status: .prepared, protocolVersion: version)
        #expect(try decode(pending, statusCode: 202, operation: .intake(requiresRecoveryExpiry: true)).status == .pending)
        #expect(try decode(pending, operation: .recovery(acknowledge: false)).status == .pending)
        for (operation, statusCode, data) in [(Operation.preparation, 200, prepared), (.commit, 202, pending),
                                             (.recoveryV2(acknowledge: false), 200, pending)] {
            if version == 2 {
                #expect(try decode(data, statusCode: statusCode, operation: operation).protocolVersion == 2)
            } else {
                #expect(throws: MerianError.invalidResponse) { try decode(data, statusCode: statusCode, operation: operation) }
            }
        }
    }

    @Test(arguments: [nil, AccountDeletionTestSupport.expiredTimestamp, "invalid"] as [String?])
    func expiryIsOptionalOnlyForLegacyIntakeWithoutAProof(expiry: String?) throws {
        let pending = try AccountDeletionTestSupport.receiptData(expiry: expiry)
        #expect(try decode(pending, statusCode: 202, operation: .intake(requiresRecoveryExpiry: false)).status == .pending)
        for operation in [Operation.intake(requiresRecoveryExpiry: true), .commit] {
            #expect(throws: MerianError.invalidResponse) { try decode(pending, statusCode: 202, operation: operation) }
        }
        let prepared = try AccountDeletionTestSupport.receiptData(status: .prepared, expiry: expiry)
        #expect(throws: MerianError.invalidResponse) { try decode(prepared, operation: .preparation) }
    }

    @Test(arguments: [AccountDeletionStatus.prepared, .notCommitted, .pending, .completed], [false, true])
    func publicRecoveryDoesNotAddANewStatusAllowlist(status: AccountDeletionStatus, acknowledged: Bool) throws {
        let data = try AccountDeletionTestSupport.receiptData(status: status, acknowledged: acknowledged)
        for operation in [Operation.recovery(acknowledge: false), .recoveryV2(acknowledge: false)] {
            #expect(try decode(data, operation: operation).status == status)
        }
        for operation in [Operation.recovery(acknowledge: true), .recoveryV2(acknowledge: true)] {
            if acknowledged {
                #expect(try decode(data, operation: operation).recoveryAcknowledged == true)
            } else {
                #expect(throws: MerianError.invalidResponse) { try decode(data, operation: operation) }
            }
        }
    }

    @Test(arguments: [AccountDeletionStatus.notCommitted, .pending, .completed], [false, true])
    func expiredRecoveryAcceptsOnlyExistingReplayExceptions(status: AccountDeletionStatus, acknowledged: Bool) throws {
        let data = try AccountDeletionTestSupport.receiptData(
            status: status, expiry: AccountDeletionTestSupport.expiredTimestamp, acknowledged: acknowledged
        )
        for (operation, expected) in [(Operation.recovery(acknowledge: false), acknowledged),
                                      (.recoveryV2(acknowledge: false), acknowledged || status == .notCommitted)] {
            if expected {
                let receipt = try AccountDeletionResponseDecoder.decode(data, statusCode: 200, for: operation) {
                    Issue.record("Terminal replay must validate the timestamp without reading the clock")
                    return AccountDeletionTestSupport.now
                }
                #expect(receipt.status == status)
            } else {
                #expect(throws: MerianError.invalidResponse) { try decode(data, operation: operation) }
            }
        }
    }

    @Test(arguments: [nil, "", "invalid", String(repeating: "A", count: 41)] as [String?])
    func acknowledgedAndNotCommittedReceiptsStillRequireAValidTimestamp(expiry: String?) throws {
        for status in [AccountDeletionStatus.notCommitted, .completed] {
            let data = try AccountDeletionTestSupport.receiptData(status: status, expiry: expiry, acknowledged: true)
            for operation in publicOperations {
                #expect(throws: MerianError.invalidResponse) { try decode(data, operation: operation) }
            }
        }
    }

    @Test func everyOperationRejectsAnUnsuccessfulReceipt() throws {
        for (operation, status, httpStatus) in [(Operation.intake(requiresRecoveryExpiry: false), AccountDeletionStatus.pending, 202),
                                              (.preparation, .prepared, 200), (.commit, .pending, 202)] {
            let data = try AccountDeletionTestSupport.receiptData(status: status, success: false)
            #expect(throws: MerianError.invalidResponse) { try decode(data, statusCode: httpStatus, operation: operation) }
        }
        let data = try AccountDeletionTestSupport.receiptData(success: false, acknowledged: true)
        for operation in publicOperations {
            #expect(throws: MerianError.invalidResponse) { try decode(data, operation: operation) }
        }
    }

    @Test(arguments: [201, 202, 204])
    func publicRecoveryRequiresHTTP200(statusCode: Int) throws {
        let data = try AccountDeletionTestSupport.receiptData(acknowledged: true)
        for operation in publicOperations {
            #expect(throws: MerianError.invalidResponse) { try decode(data, statusCode: statusCode, operation: operation) }
        }
    }

    @Test(arguments: ["", "null", "[]", "{}", #"{"success":true,"status":"pending"}"#,
                      #"{"success":true,"status":"other","manual_provider_revocation_required":false}"#])
    func decodingFailuresAreMappedToInvalidResponse(json: String) {
        for operation in [Operation.intake(requiresRecoveryExpiry: false), .preparation, .commit] + publicOperations {
            #expect(throws: MerianError.invalidResponse) { try decode(Data(json.utf8), operation: operation) }
        }
    }

    private var publicOperations: [Operation] {
        [.recovery(acknowledge: false), .recovery(acknowledge: true),
         .recoveryV2(acknowledge: false), .recoveryV2(acknowledge: true)]
    }

    private func decode(_ data: Data, statusCode: Int = 200, operation: Operation) throws -> AccountDeletionReceipt {
        try AccountDeletionResponseDecoder.decode(data, statusCode: statusCode, for: operation) {
            AccountDeletionTestSupport.now
        }
    }
}
