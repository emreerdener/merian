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
        let data = try preparationData(status: status)
        if status == .prepared && httpStatus == 200 {
            #expect(try decodePreparation(data).status == .prepared)
        } else {
            #expect(throws: MerianError.invalidResponse) {
                try decodePreparation(data, statusCode: httpStatus)
            }
        }
    }

    @Test func preparationAcceptsTheHandlerShapeWithoutProviderDisposition() throws {
        let data = try AccountDeletionTestSupport
            .preparationHandlerResponseData()

        let preparation = try decodePreparation(data)

        #expect(preparation.status == .prepared)
        #expect(preparation.protocolVersion == 2)
        #expect(
            preparation.recoveryCapabilityExpiresAt
                == AccountDeletionTestSupport.futureExpiry
        )
    }

    @Test(arguments: [nil, 1, 2, 3] as [Int?])
    func versionTwoIsRequiredOnlyByVersionTwoOperations(version: Int?) throws {
        let pending = try AccountDeletionTestSupport.receiptData(
            acknowledged: false,
            protocolVersion: version
        )
        let prepared = try preparationData(protocolVersion: version)
        #expect(try decode(pending, statusCode: 202, operation: .intake(requiresRecoveryExpiry: true)).status == .pending)
        #expect(try decode(pending, operation: .recovery(acknowledge: false)).status == .pending)
        for (operation, statusCode) in [(Operation.commit, 202), (.recoveryV2(acknowledge: false), 200)] {
            if version == 2 {
                #expect(try decode(pending, statusCode: statusCode, operation: operation).protocolVersion == 2)
            } else {
                #expect(throws: MerianError.invalidResponse) {
                    try decode(pending, statusCode: statusCode, operation: operation)
                }
            }
        }
        if version == 2 {
            #expect(try decodePreparation(prepared).protocolVersion == 2)
        } else {
            #expect(throws: MerianError.invalidResponse) {
                try decodePreparation(prepared)
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
        let prepared = try preparationData(expiry: expiry)
        #expect(throws: MerianError.invalidResponse) {
            try decodePreparation(prepared)
        }
    }

    @Test(arguments: [AccountDeletionStatus.prepared, .notCommitted, .pending, .completed], [false, true])
    func publicRecoveryEnforcesEachOperationStatusContract(
        status: AccountDeletionStatus,
        acknowledged: Bool
    ) throws {
        let data = try AccountDeletionTestSupport.receiptData(status: status, acknowledged: acknowledged)
        let isAcceptedDeletion = status == .pending || status == .completed
        let expectations: [(Operation, Bool)] = [
            (.recovery(acknowledge: false), isAcceptedDeletion),
            (
                .recovery(acknowledge: true),
                isAcceptedDeletion && acknowledged
            ),
            (
                .recoveryV2(acknowledge: false),
                isAcceptedDeletion ||
                    (status == .notCommitted && !acknowledged)
            ),
            (
                .recoveryV2(acknowledge: true),
                isAcceptedDeletion && acknowledged
            )
        ]

        for (operation, isAccepted) in expectations {
            if isAccepted {
                #expect(try decode(data, operation: operation).status == status)
            } else {
                #expect(throws: MerianError.invalidResponse) {
                    try decode(data, operation: operation)
                }
            }
        }
    }

    @Test func publicRecoveryRequiresExplicitAcknowledgementState() throws {
        let data = try AccountDeletionTestSupport.receiptData(
            acknowledged: nil
        )

        for operation in publicOperations {
            #expect(throws: MerianError.invalidResponse) {
                try decode(data, operation: operation)
            }
        }
    }

    @Test func nonCommitReceiptCannotClaimDeletionDisposition() throws {
        let acknowledged = try AccountDeletionTestSupport.receiptData(
            status: .notCommitted,
            acknowledged: true
        )
        let manualDisposition = try AccountDeletionTestSupport.receiptData(
            status: .notCommitted,
            acknowledged: false,
            manualProviderRevocationRequired: true
        )

        for data in [acknowledged, manualDisposition] {
            #expect(throws: MerianError.invalidResponse) {
                try decode(
                    data,
                    operation: .recoveryV2(acknowledge: false)
                )
            }
        }
    }

    @Test(arguments: [AccountDeletionStatus.notCommitted, .pending, .completed], [false, true])
    func expiredRecoveryAcceptsOnlyExistingReplayExceptions(status: AccountDeletionStatus, acknowledged: Bool) throws {
        let data = try AccountDeletionTestSupport.receiptData(
            status: status, expiry: AccountDeletionTestSupport.expiredTimestamp, acknowledged: acknowledged
        )
        for (operation, expected) in [
            (
                Operation.recovery(acknowledge: false),
                acknowledged && status != .notCommitted
            ),
            (
                .recoveryV2(acknowledge: false),
                (acknowledged && status != .notCommitted)
                    || (!acknowledged && status == .notCommitted)
            )
        ] {
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
                                                (.commit, .pending, 202)] {
            let data = try AccountDeletionTestSupport.receiptData(status: status, success: false)
            #expect(throws: MerianError.invalidResponse) { try decode(data, statusCode: httpStatus, operation: operation) }
        }
        let preparation = try preparationData(success: false)
        #expect(throws: MerianError.invalidResponse) {
            try decodePreparation(preparation)
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
        for operation in [Operation.intake(requiresRecoveryExpiry: false), .commit] + publicOperations {
            #expect(throws: MerianError.invalidResponse) { try decode(Data(json.utf8), operation: operation) }
        }
        #expect(throws: MerianError.invalidResponse) {
            try decodePreparation(Data(json.utf8))
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

    private func decodePreparation(
        _ data: Data,
        statusCode: Int = 200
    ) throws -> AccountDeletionPreparationReceipt {
        try AccountDeletionResponseDecoder.decodePreparation(
            data,
            statusCode: statusCode
        ) {
            AccountDeletionTestSupport.now
        }
    }

    private func preparationData(
        status: AccountDeletionStatus = .prepared,
        success: Bool = true,
        expiry: String? = AccountDeletionTestSupport.futureExpiry,
        protocolVersion: Int? = 2
    ) throws -> Data {
        var payload: [String: Any] = [
            "success": success,
            "status": status.rawValue
        ]
        payload["protocol_version"] = protocolVersion
        payload["recovery_capability_expires_at"] = expiry
        return try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
    }
}
