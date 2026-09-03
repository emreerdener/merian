import Foundation

enum AccountDeletionStatus: String, Decodable, Equatable, Sendable {
    case prepared
    case notCommitted = "not_committed"
    case pending
    case completed
}

struct AccountDeletionReceipt: Decodable, Equatable, Sendable {
    let success: Bool
    let status: AccountDeletionStatus
    let manualProviderRevocationRequired: Bool
    let recoveryCapabilityExpiresAt: String?
    let recoveryAcknowledged: Bool?
    let protocolVersion: Int?

    init(
        success: Bool,
        status: AccountDeletionStatus,
        manualProviderRevocationRequired: Bool,
        recoveryCapabilityExpiresAt: String? = nil,
        recoveryAcknowledged: Bool? = nil,
        protocolVersion: Int? = nil
    ) {
        self.success = success
        self.status = status
        self.manualProviderRevocationRequired =
            manualProviderRevocationRequired
        self.recoveryCapabilityExpiresAt = recoveryCapabilityExpiresAt
        self.recoveryAcknowledged = recoveryAcknowledged
        self.protocolVersion = protocolVersion
    }

    private enum CodingKeys: String, CodingKey {
        case success
        case status
        case manualProviderRevocationRequired = "manual_provider_revocation_required"
        case recoveryCapabilityExpiresAt = "recovery_capability_expires_at"
        case recoveryAcknowledged = "recovery_acknowledged"
        case protocolVersion = "protocol_version"
    }
}

/// Confirms that protocol-v2 recovery proofs were registered without accepting
/// account deletion. Provider revocation is decided only by destructive intake.
struct AccountDeletionPreparationReceipt: Decodable, Equatable, Sendable {
    let success: Bool
    let status: AccountDeletionStatus
    let protocolVersion: Int
    let recoveryCapabilityExpiresAt: String

    private enum CodingKeys: String, CodingKey {
        case success
        case status
        case protocolVersion = "protocol_version"
        case recoveryCapabilityExpiresAt = "recovery_capability_expires_at"
    }
}

struct AccountDeletionPreparationPayload: Encodable {
    let protocolVersion = 2
    let operation = "prepare"
    let recoveryCapability: String
    let acknowledgementCapability: String

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case operation
        case recoveryCapability = "recovery_capability"
        case acknowledgementCapability = "acknowledgement_capability"
    }
}

struct AccountDeletionCommitPayload: Encodable {
    let protocolVersion = 2
    let operation = "commit"
    let recoveryCapability: String

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case operation
        case recoveryCapability = "recovery_capability"
    }
}
