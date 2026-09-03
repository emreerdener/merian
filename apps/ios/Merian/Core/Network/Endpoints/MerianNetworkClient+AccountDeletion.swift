import Foundation
import os

extension MerianNetworkClient {
    func safeDeleteAccount(
        recoveryCapability: String? = nil,
        ownedBy authTransitionOwner: AuthTransitionToken? = nil
    ) async throws -> AccountDeletionReceipt {
        let response = try await performAccountDeletionJSONPost(ownedBy: authTransitionOwner) {
            // Legacy intake resolves configuration before validating the proof.
            if let recoveryCapability {
                guard Self.isValidAccountDeletionRecoveryCapability(recoveryCapability) else {
                    throw MerianError.invalidResponse
                }
            }
            return try recoveryCapability.map {
                try JSONEncoder().encode(AccountDeletionIntakePayload(recoveryCapability: $0))
            }
        }
        let receipt = try AccountDeletionResponseDecoder.decode(
            response.data,
            statusCode: response.statusCode,
            for: .intake(requiresRecoveryExpiry: recoveryCapability != nil)
        )
        MerianLog.network.debug("Account deletion accepted.")
        return receipt
    }

    /// Registers both protocol-v2 proofs without creating a deletion job.
    /// Destructive commit remains a separate authenticated request.
    func prepareAccountDeletionRecoveryV2(
        recoveryCapability: String,
        acknowledgementCapability: String,
        ownedBy authTransitionOwner: AuthTransitionToken
    ) async throws -> AccountDeletionReceipt {
        guard Self.isValidAccountDeletionRecoveryCapability(recoveryCapability),
              Self.isValidAccountDeletionRecoveryCapability(acknowledgementCapability),
              recoveryCapability != acknowledgementCapability else {
            throw MerianError.invalidResponse
        }
        let response = try await performAccountDeletionJSONPost(ownedBy: authTransitionOwner) {
            try JSONEncoder().encode(AccountDeletionPreparationPayload(
                recoveryCapability: recoveryCapability,
                acknowledgementCapability: acknowledgementCapability
            ))
        }
        return try AccountDeletionResponseDecoder.decode(
            response.data, statusCode: response.statusCode, for: .preparation
        )
    }

    func commitPreparedAccountDeletionV2(
        recoveryCapability: String,
        ownedBy authTransitionOwner: AuthTransitionToken
    ) async throws -> AccountDeletionReceipt {
        guard Self.isValidAccountDeletionRecoveryCapability(recoveryCapability) else {
            throw MerianError.invalidResponse
        }
        let response = try await performAccountDeletionJSONPost(ownedBy: authTransitionOwner) {
            try JSONEncoder().encode(AccountDeletionCommitPayload(recoveryCapability: recoveryCapability))
        }
        return try AccountDeletionResponseDecoder.decode(
            response.data, statusCode: response.statusCode, for: .commit
        )
    }

    /// Continues an already-authorized deletion without selecting or restoring an account.
    func recoverAcceptedAccountDeletion(
        recoveryCapability: String,
        acknowledge: Bool
    ) async throws -> AccountDeletionReceipt {
        guard Self.isValidAccountDeletionRecoveryCapability(recoveryCapability) else {
            throw MerianError.invalidResponse
        }
        let response = try await performAccountDeletionRecoveryJSONPost {
            try JSONEncoder().encode(AccountDeletionRecoveryPayload(
                operation: acknowledge ? "acknowledge" : "recover",
                recoveryCapability: recoveryCapability
            ))
        }
        return try AccountDeletionResponseDecoder.decode(
            response.data, statusCode: response.statusCode, for: .recovery(acknowledge: acknowledge)
        )
    }

    func recoverPreparedAccountDeletionV2(
        recoveryCapability: String
    ) async throws -> AccountDeletionReceipt {
        try await performAccountDeletionRecoveryV2(operation: "recover", capability: recoveryCapability)
    }

    func acknowledgeAccountDeletionRecoveryV2(
        acknowledgementCapability: String
    ) async throws -> AccountDeletionReceipt {
        try await performAccountDeletionRecoveryV2(operation: "acknowledge", capability: acknowledgementCapability)
    }

    private func performAccountDeletionRecoveryV2(
        operation: String,
        capability: String
    ) async throws -> AccountDeletionReceipt {
        guard operation == "recover" || operation == "acknowledge",
              Self.isValidAccountDeletionRecoveryCapability(capability) else {
            throw MerianError.invalidResponse
        }
        let response = try await performAccountDeletionRecoveryJSONPost {
            try JSONEncoder().encode(AccountDeletionRecoveryV2Payload(
                operation: operation,
                recoveryCapability: operation == "recover" ? capability : nil,
                acknowledgementCapability: operation == "acknowledge" ? capability : nil
            ))
        }
        return try AccountDeletionResponseDecoder.decode(
            response.data, statusCode: response.statusCode, for: .recoveryV2(acknowledge: operation == "acknowledge")
        )
    }

    static func isValidAccountDeletionRecoveryCapability(_ value: String) -> Bool {
        AccountDeletionRecoveryValidation.isValidCapability(value)
    }

    static func isValidAccountDeletionRecoveryExpiry(_ value: String?) -> Bool {
        AccountDeletionRecoveryValidation.isValidExpiry(value)
    }

    static func isValidAccountDeletionRecoveryTimestamp(_ value: String?) -> Bool {
        AccountDeletionRecoveryValidation.isValidTimestamp(value)
    }
}

private struct AccountDeletionIntakePayload: Encodable {
    let recoveryCapability: String

    private enum CodingKeys: String, CodingKey {
        case recoveryCapability = "recovery_capability"
    }
}

private struct AccountDeletionRecoveryPayload: Encodable {
    let operation: String
    let recoveryCapability: String

    private enum CodingKeys: String, CodingKey {
        case operation
        case recoveryCapability = "recovery_capability"
    }
}

private struct AccountDeletionRecoveryV2Payload: Encodable {
    let protocolVersion = 2
    let operation: String
    let recoveryCapability: String?
    let acknowledgementCapability: String?

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case operation
        case recoveryCapability = "recovery_capability"
        case acknowledgementCapability = "acknowledgement_capability"
    }
}
