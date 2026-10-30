import Foundation

/// Immutable local liability. Neither decoding nor a saved claim grants create,
/// upload, execution, replacement or release authority.
struct SharedMediaNativePhotoAllocation: Codable, Equatable, Sendable {
    static let maximumBytes = Int(PhotoPreparationPolicy.metadata)
    struct Claim: Codable, Equatable, Sendable {
        let profile: SharedMediaNativeAppProfile
        let packageID: UUID, draftGeneration: UUID, operationID: UUID, observationID: UUID, attemptID: UUID
        let preparedSHA256: String, receivedSHA256: String
        let candidateCanonical: String, candidateDigest: String, contentDigest: String

        init(prepared: SharedMediaNativeReceivingIntent.Prepared,
             received: SharedMediaNativeReceivingIntent.Received, attemptID: UUID) throws {
            let candidate = try SharedMediaNativePhotoCandidate(prepared: prepared)
            let content = try SharedMediaNativePhotoContent(prepared: prepared)
            guard let text = String(data: candidate.canonicalBytes, encoding: .utf8) else {
                throw SharedMediaStorageFailure.invalid
            }
            _ = try received.reconstruct(prepared)
            profile = prepared.profile; packageID = prepared.package.id
            draftGeneration = prepared.package.generation; operationID = prepared.operationID
            observationID = prepared.observationID; self.attemptID = attemptID
            preparedSHA256 = SharedMediaAcquisitionEncoding.digest(try prepared.encoded())
            receivedSHA256 = SharedMediaAcquisitionEncoding.digest(try received.encoded(prepared: prepared))
            candidateCanonical = text; candidateDigest = candidate.unverifiedDigest
            contentDigest = content.unverifiedDigest
        }

        func requireMatch(prepared: SharedMediaNativeReceivingIntent.Prepared,
                          received: SharedMediaNativeReceivingIntent.Received) throws {
            guard self == (try Self(prepared: prepared, received: received, attemptID: attemptID)) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    /// Historical assignment evidence only. Original clocks never renew.
    struct Receipt: Codable, Equatable, Sendable {
        let assignmentDigest: String
        let createdAtMilliseconds: Int64, expiresAtMilliseconds: Int64

        func validate() throws {
            guard SharedMediaAcquisitionEncoding.isHash(assignmentDigest),
                  (1...8_639_999_998_200_000).contains(createdAtMilliseconds),
                  expiresAtMilliseconds == createdAtMilliseconds + 1_800_000 else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    /// Historical facts only; this slot never contains a capability or upload ticket.
    enum RemoteAttemptState: String, Codable, Sendable { case bound, mayHaveIssued }
    struct RemoteAttempt: Codable, Equatable, Sendable {
        let id: UUID
        let state: RemoteAttemptState
        let createdAtMilliseconds: Int64, capabilityExpiresAtMilliseconds: Int64
        let writeClosed: Bool

        var remainingAdvances: Int64 { writeClosed ? 0 : (state == .bound ? 2 : 1) }
        func validate(_ receipt: Receipt) throws {
            try receipt.validate()
            guard createdAtMilliseconds >= receipt.createdAtMilliseconds,
                  createdAtMilliseconds < receipt.expiresAtMilliseconds,
                  capabilityExpiresAtMilliseconds == min(receipt.expiresAtMilliseconds, createdAtMilliseconds + 600_000),
                  !writeClosed || state == .mayHaveIssued else { throw SharedMediaStorageFailure.conflict }
        }
        func requireSuccessor(_ after: Self?) throws {
            guard let after, after.id == id, after.createdAtMilliseconds == createdAtMilliseconds,
                  after.capabilityExpiresAtMilliseconds == capabilityExpiresAtMilliseconds,
                  state != .mayHaveIssued || after.state == state,
                  !writeClosed || after.writeClosed else { throw SharedMediaStorageFailure.conflict }
        }
    }

    let version: Int
    let claim: Claim
    let receipt: Receipt?
    let roleMapping: SharedMediaNativePhotoRoleMapping?
    let transferReservation: SharedMediaNativePhotoTransferReservation?
    let remoteAttempt: RemoteAttempt?
    var remainingAdvances: Int64 {
        if version == 4 { return remoteAttempt?.remainingAdvances ?? 3 }
        return (receipt == nil ? 1 : 0) + (version == 2 && roleMapping == nil ? 1 : 0)
    }

    init(claim: Claim) { self.init(version: 1, claim: claim, receipt: nil, roleMapping: nil) }
    private init(version: Int, claim: Claim, receipt: Receipt?, roleMapping: SharedMediaNativePhotoRoleMapping?, transferReservation: SharedMediaNativePhotoTransferReservation? = nil, remoteAttempt: RemoteAttempt? = nil) {
        self.version = version; self.claim = claim; self.receipt = receipt; self.roleMapping = roleMapping
        self.transferReservation = transferReservation; self.remoteAttempt = remoteAttempt
    }

    /// Explicit metadata/revision reservation proposal. Only a fresh audited
    /// persistence owner can make it durable; this value grants no dispatch.
    func reservingRoleMapping() throws -> Self {
        _ = try encoded()
        if version >= 2 { return self }
        let after = Self(version: 2, claim: claim, receipt: receipt, roleMapping: nil)
        guard try after.legacyEncoded() == encoded() else { throw SharedMediaStorageFailure.conflict }
        _ = try after.storageCharge
        return after
    }

    func legacyEncoded() throws -> Data {
        try Self(version: 1, claim: claim, receipt: receipt, roleMapping: nil).encoded()
    }

    func enriching(_ value: Receipt, mapping: SharedMediaNativePhotoRoleMapping) throws -> Self {
        guard version >= 2 else { throw SharedMediaStorageFailure.closed }
        try mapping.validate(claim)
        let settled = try settling(value)
        if let roleMapping {
            guard roleMapping == mapping else { throw SharedMediaStorageFailure.conflict }
            return settled
        }
        return Self(version: 2, claim: claim, receipt: settled.receipt, roleMapping: mapping)
    }

    func reservingTransfer(_ value: SharedMediaNativePhotoTransferReservation) throws -> Self {
        _ = try encoded()
        guard version >= 2, let receipt, let roleMapping else { throw SharedMediaStorageFailure.closed }
        try value.validate(claim: claim, mapping: roleMapping)
        if let transferReservation {
            guard transferReservation == value else { throw SharedMediaStorageFailure.inUse }
            return self
        }
        return Self(version: 3, claim: claim, receipt: receipt, roleMapping: roleMapping, transferReservation: value)
    }

    /// Explicitly reserve all future status metadata and up to three saves.
    /// An empty slot represents no saved fact, never fresh dispatch permission.
    func reservingRemoteAttempt() throws -> Self {
        _ = try encoded()
        guard version >= 3 else { throw SharedMediaStorageFailure.closed }
        if version == 4 { return self }
        let after = Self(version: 4, claim: claim, receipt: receipt, roleMapping: roleMapping,
                         transferReservation: transferReservation)
        _ = try after.storageCharge
        return after
    }

    func observing(_ status: InitialPhotoUploadStatus) throws -> Self {
        _ = try encoded()
        guard version == 4, let transferReservation else { throw SharedMediaStorageFailure.closed }
        try status.requireMatch(self, objectID: transferReservation.selection.objectID)
        let value = status.attempt.map {
            RemoteAttempt(id: $0.id, state: $0.state == .bound ? .bound : .mayHaveIssued,
                createdAtMilliseconds: $0.createdAtMilliseconds,
                capabilityExpiresAtMilliseconds: $0.capabilityExpiresAtMilliseconds, writeClosed: $0.writeClosed)
        }
        return try recording(value)
    }

    private func recording(_ value: RemoteAttempt?) throws -> Self {
        guard version == 4 else { throw SharedMediaStorageFailure.closed }
        try remoteAttempt?.requireSuccessor(value)
        let after = Self(version: 4, claim: claim, receipt: receipt, roleMapping: roleMapping,
                         transferReservation: transferReservation, remoteAttempt: value)
        _ = try after.encoded()
        return after
    }

    /// Exact permitted one-save transitions. No downgrade, replacement or
    /// enrichment before reservation can enter the sidecar write set.
    func requireSuccessor(_ after: Self) throws {
        _ = try encoded(); _ = try after.encoded()
        if version == 2, after.version == 3, let value = after.transferReservation {
            guard try reservingTransfer(value) == after else { throw SharedMediaStorageFailure.conflict }
            return
        }
        guard after != self else { throw SharedMediaStorageFailure.closed }
        if version == 3, after.version == 4 {
            guard try reservingRemoteAttempt() == after else { throw SharedMediaStorageFailure.conflict }
            return
        }
        if version == 4 {
            guard try recording(after.remoteAttempt) == after else { throw SharedMediaStorageFailure.conflict }
            return
        }
        if version == 1, after.version == 2 {
            guard try reservingRoleMapping() == after, try after.legacyEncoded() == encoded() else {
                throw SharedMediaStorageFailure.conflict
            }
        } else if let mapping = after.roleMapping, roleMapping == nil, let value = after.receipt {
            guard try enriching(value, mapping: mapping) == after else { throw SharedMediaStorageFailure.conflict }
        } else if receipt == nil, let value = after.receipt {
            guard try settling(value) == after else { throw SharedMediaStorageFailure.conflict }
        } else { throw SharedMediaStorageFailure.closed }
    }

    func settling(_ value: Receipt) throws -> Self {
        try value.validate()
        if let receipt {
            guard receipt == value else { throw SharedMediaStorageFailure.conflict }
            return self
        }
        return .init(version: version, claim: claim, receipt: value, roleMapping: roleMapping, transferReservation: transferReservation, remoteAttempt: remoteAttempt)
    }

    func encoded() throws -> Data {
        guard (1...4).contains(version), !claim.candidateCanonical.isEmpty,
              claim.candidateCanonical.utf8.count <= 1_048_576,
              [claim.preparedSHA256, claim.receivedSHA256, claim.candidateDigest, claim.contentDigest]
                .allSatisfy(SharedMediaAcquisitionEncoding.isHash) else { throw SharedMediaStorageFailure.conflict }
        guard version >= 2 || roleMapping == nil, roleMapping == nil || receipt != nil,
              (version >= 3) == (transferReservation != nil), version < 3 || (receipt != nil && roleMapping != nil),
              version == 4 || remoteAttempt == nil else {
            throw SharedMediaStorageFailure.conflict
        }
        try receipt?.validate()
        if let remoteAttempt, let receipt { try remoteAttempt.validate(receipt) }
        if version >= 2 { _ = try SharedMediaNativePhotoRoleMapping.references(claim) }
        try roleMapping?.validate(claim)
        if let transferReservation, let roleMapping { try transferReservation.validate(claim: claim, mapping: roleMapping) }
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Self.maximumBytes)
    }

    static func decode(_ data: Data, sha256: String) throws -> Self {
        guard SharedMediaAcquisitionEncoding.isHash(sha256),
              SharedMediaAcquisitionEncoding.digest(data) == sha256 else { throw SharedMediaStorageFailure.conflict }
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data, maximum: maximumBytes)
        guard try value.encoded() == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    /// Reserve the largest actual canonical successor including JSON escaping,
    /// the receipt key, decimal clocks and the separately stored SHA string.
    var storageCharge: Int64 {
        get throws {
            let current = try encoded().count
            if version == 4, let receipt {
                // Retain the maximum slot charge even after closure. A shorter
                // observation is not authority to release metadata or copy liability.
                let maximum = RemoteAttempt(id: claim.attemptID, state: .mayHaveIssued,
                    createdAtMilliseconds: receipt.expiresAtMilliseconds - 1,
                    capabilityExpiresAtMilliseconds: receipt.expiresAtMilliseconds, writeClosed: false)
                let successor = Self(version: 4, claim: claim, receipt: receipt, roleMapping: roleMapping,
                    transferReservation: transferReservation, remoteAttempt: maximum)
                return try PhotoPreparationPolicy.add([Int64(max(current, successor.encoded().count)), 64])
            }
            if remainingAdvances == 0 { return try PhotoPreparationPolicy.add([Int64(current), 64]) }
            let maximum = Receipt(assignmentDigest: String(repeating: "f", count: 64),
                createdAtMilliseconds: 8_639_999_998_200_000, expiresAtMilliseconds: 8_640_000_000_000_000)
            let settled = try settling(receipt ?? maximum)
            let successor: Self
            if version == 2 {
                successor = try settled.enriching(receipt ?? maximum, mapping: roleMapping ?? .reservation(claim))
            } else { successor = settled }
            return try PhotoPreparationPolicy.add([Int64(max(current, successor.encoded().count)), 64])
        }
    }
}
