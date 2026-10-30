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
            try self.init(prepared: prepared, received: received, attemptID: attemptID,
                          content: SharedMediaNativePhotoContent(prepared: prepared))
        }

        private init(prepared: SharedMediaNativeReceivingIntent.Prepared,
                     received: SharedMediaNativeReceivingIntent.Received, attemptID: UUID,
                     content: SharedMediaNativePhotoContent) throws {
            guard let admission = prepared.photoAdmission else { throw SharedMediaStorageFailure.closed }
            let candidate = try SharedMediaNativePhotoCandidate(content: content, admission: admission)
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
            if self == (try? Self(prepared: prepared, received: received, attemptID: attemptID)) { return }
            // Match the complete historical claim, including both canonical digests.
            // Never normalize or replace an already accepted declaration on recovery.
            guard self == (try Self(prepared: prepared, received: received, attemptID: attemptID,
                                   content: SharedMediaNativePhotoContent(prepared: prepared, legacyLocalTypes: true))) else {
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

    /// Saved historical identity, never a destination, capability or fresh ticket.
    struct BackendBinding: Codable, Equatable, Sendable {
        let generation: UUID
        let configurationDigest: String
        func validate() throws {
            guard SharedMediaAcquisitionEncoding.isHash(configurationDigest) else { throw SharedMediaStorageFailure.conflict }
        }
    }

    let version: Int
    let claim: Claim
    let receipt: Receipt?
    let roleMapping: SharedMediaNativePhotoRoleMapping?
    let transferReservation: SharedMediaNativePhotoTransferReservation?
    let remoteAttempt: RemoteAttempt?
    /// Durable uncertainty before a fresh ticket request, never PUT authority.
    let ticketRequestStarted: Bool?
    let backendBinding: BackendBinding?
    var remainingAdvances: Int64 {
        if version == 6 { return (receipt == nil ? 1 : 0) + (backendBinding == nil ? 1 : 0) }
        if version == 7 { return 0 }
        if (4...5).contains(version) || (8...9).contains(version) { return remoteAttempt?.remainingAdvances ?? 3 }
        return (receipt == nil ? 1 : 0) + (version == 2 && roleMapping == nil ? 1 : 0)
    }

    init(claim: Claim) { self.init(version: 1, claim: claim, receipt: nil, roleMapping: nil) }
    private init(version: Int, claim: Claim, receipt: Receipt?, roleMapping: SharedMediaNativePhotoRoleMapping?, transferReservation: SharedMediaNativePhotoTransferReservation? = nil, remoteAttempt: RemoteAttempt? = nil, ticketRequestStarted: Bool? = nil, backendBinding: BackendBinding? = nil) {
        self.version = version; self.claim = claim; self.receipt = receipt; self.roleMapping = roleMapping
        self.transferReservation = transferReservation; self.remoteAttempt = remoteAttempt
        self.ticketRequestStarted = ticketRequestStarted; self.backendBinding = backendBinding
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

    /// Explicitly reserve the whole v3 response before dispatch. Accepted legacy
    /// transfer/ticket uncertainty is never upgraded into a new issuance path.
    func reservingBackendBinding() throws -> Self {
        _ = try encoded()
        if version == 6 { return self }
        guard version == 1 || version == 2 else { throw SharedMediaStorageFailure.closed }
        let after = Self(version: 6, claim: claim, receipt: receipt, roleMapping: roleMapping)
        _ = try after.storageCharge
        return after
    }

    func legacyEncoded() throws -> Data {
        try Self(version: 1, claim: claim, receipt: receipt, roleMapping: nil).encoded()
    }

    func enriching(_ value: Receipt, mapping: SharedMediaNativePhotoRoleMapping, binding: BackendBinding? = nil) throws -> Self {
        guard ((6...9).contains(version) && binding != nil) || ((2...5).contains(version) && binding == nil) else { throw SharedMediaStorageFailure.closed }
        try mapping.validate(claim)
        try binding?.validate()
        if let backendBinding { guard backendBinding == binding else { throw SharedMediaStorageFailure.conflict } }
        let settled = try settling(value)
        if let roleMapping {
            guard roleMapping == mapping else { throw SharedMediaStorageFailure.conflict }
            if version != 6 { return settled }
        }
        return Self(version: version == 6 ? 6 : 2, claim: claim, receipt: settled.receipt,
                    roleMapping: mapping, backendBinding: binding)
    }

    func reservingTransfer(_ value: SharedMediaNativePhotoTransferReservation) throws -> Self {
        _ = try encoded()
        guard (2...9).contains(version), let receipt, let roleMapping,
              version < 6 || backendBinding != nil else { throw SharedMediaStorageFailure.closed }
        try value.validate(claim: claim, mapping: roleMapping)
        if let transferReservation {
            guard transferReservation == value else { throw SharedMediaStorageFailure.inUse }
            return self
        }
        return Self(version: version >= 6 ? 7 : 3, claim: claim, receipt: receipt, roleMapping: roleMapping,
                    transferReservation: value, backendBinding: backendBinding)
    }

    /// Explicitly reserve all future status metadata and up to three saves.
    /// An empty slot represents no saved fact, never fresh dispatch permission.
    func reservingRemoteAttempt() throws -> Self {
        _ = try encoded()
        guard (3...5).contains(version) || (7...9).contains(version) else { throw SharedMediaStorageFailure.closed }
        if (4...5).contains(version) || (8...9).contains(version) { return self }
        let after = Self(version: version == 7 ? 8 : 4, claim: claim, receipt: receipt, roleMapping: roleMapping,
                         transferReservation: transferReservation, backendBinding: backendBinding)
        _ = try after.storageCharge
        return after
    }

    /// The owner reserves this save plus three future status saves before any
    /// request. Existing remote facts or a decoded marker cannot mint permission.
    func startingTicketRequest() throws -> Self {
        _ = try encoded()
        guard version == 4 || version == 8, remoteAttempt == nil else { throw SharedMediaStorageFailure.closed }
        let after = Self(version: version == 8 ? 9 : 5, claim: claim, receipt: receipt, roleMapping: roleMapping,
            transferReservation: transferReservation, ticketRequestStarted: true, backendBinding: backendBinding)
        _ = try after.storageCharge
        return after
    }

    func observing(_ status: InitialPhotoUploadStatus) throws -> Self {
        _ = try encoded()
        guard (4...5).contains(version) || (8...9).contains(version), let transferReservation else { throw SharedMediaStorageFailure.closed }
        try status.requireMatch(self, objectID: transferReservation.selection.objectID)
        let value = status.attempt.map {
            RemoteAttempt(id: $0.id, state: $0.state == .bound ? .bound : .mayHaveIssued,
                createdAtMilliseconds: $0.createdAtMilliseconds,
                capabilityExpiresAtMilliseconds: $0.capabilityExpiresAtMilliseconds, writeClosed: $0.writeClosed)
        }
        return try recording(value)
    }

    private func recording(_ value: RemoteAttempt?) throws -> Self {
        guard (4...5).contains(version) || (8...9).contains(version) else { throw SharedMediaStorageFailure.closed }
        try remoteAttempt?.requireSuccessor(value)
        let after = Self(version: version, claim: claim, receipt: receipt, roleMapping: roleMapping,
                         transferReservation: transferReservation, remoteAttempt: value, ticketRequestStarted: ticketRequestStarted,
                         backendBinding: backendBinding)
        _ = try after.encoded()
        return after
    }

    /// Exact permitted one-save transitions. No downgrade, replacement or
    /// enrichment before reservation can enter the sidecar write set.
    func requireSuccessor(_ after: Self) throws {
        _ = try encoded(); _ = try after.encoded()
        if (version == 2 && after.version == 3) || (version == 6 && after.version == 7), let value = after.transferReservation {
            guard try reservingTransfer(value) == after else { throw SharedMediaStorageFailure.conflict }
            return
        }
        guard after != self else { throw SharedMediaStorageFailure.closed }
        if (version == 3 && after.version == 4) || (version == 7 && after.version == 8) {
            guard try reservingRemoteAttempt() == after else { throw SharedMediaStorageFailure.conflict }
            return
        }
        if (version == 4 && after.version == 5) || (version == 8 && after.version == 9) {
            guard try startingTicketRequest() == after else { throw SharedMediaStorageFailure.conflict }
            return
        }
        if version == 1 || version == 2, after.version == 6 {
            guard try reservingBackendBinding() == after else { throw SharedMediaStorageFailure.conflict }
            return
        }
        if version == 6, let binding = after.backendBinding, let mapping = after.roleMapping, let value = after.receipt {
            guard try enriching(value, mapping: mapping, binding: binding) == after else { throw SharedMediaStorageFailure.conflict }
            return
        }
        if (4...5).contains(version) || (8...9).contains(version) {
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
        return .init(version: version, claim: claim, receipt: value, roleMapping: roleMapping, transferReservation: transferReservation, remoteAttempt: remoteAttempt, ticketRequestStarted: ticketRequestStarted, backendBinding: backendBinding)
    }

    func encoded() throws -> Data {
        guard (1...9).contains(version), !claim.candidateCanonical.isEmpty,
              claim.candidateCanonical.utf8.count <= 1_048_576,
              [claim.preparedSHA256, claim.receivedSHA256, claim.candidateDigest, claim.contentDigest]
                .allSatisfy(SharedMediaAcquisitionEncoding.isHash) else { throw SharedMediaStorageFailure.conflict }
        guard version >= 2 || roleMapping == nil, roleMapping == nil || receipt != nil,
              ((3...5).contains(version) || (7...9).contains(version)) == (transferReservation != nil),
              transferReservation == nil || (receipt != nil && roleMapping != nil),
              (4...5).contains(version) || (8...9).contains(version) || remoteAttempt == nil,
              version >= 6 || backendBinding == nil,
              version < 7 || backendBinding != nil,
              backendBinding == nil || (receipt != nil && roleMapping != nil),
              (version == 5 || version == 9) ? ticketRequestStarted == true : ticketRequestStarted == nil else {
            throw SharedMediaStorageFailure.conflict
        }
        try receipt?.validate()
        try backendBinding?.validate()
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
            if version >= 6 {
                // Every bound phase retains V6's full receipt/mapping/tuple charge.
                // Later reservations add transfer and maximum remote-slot metadata;
                // status or closure never shrinks this liability.
                let receipt = Receipt(assignmentDigest: String(repeating: "f", count: 64),
                    createdAtMilliseconds: 8_639_999_998_200_000, expiresAtMilliseconds: 8_640_000_000_000_000)
                let remote: RemoteAttempt? = version >= 8 ? .init(id: claim.attemptID, state: .mayHaveIssued,
                    createdAtMilliseconds: receipt.expiresAtMilliseconds - 1,
                    capabilityExpiresAtMilliseconds: receipt.expiresAtMilliseconds, writeClosed: false) : nil
                let maximum = Self(version: version, claim: claim, receipt: receipt,
                    roleMapping: try roleMapping ?? .reservation(claim), transferReservation: transferReservation,
                    remoteAttempt: remote, ticketRequestStarted: ticketRequestStarted,
                    backendBinding: .init(generation: claim.attemptID, configurationDigest: String(repeating: "f", count: 64)))
                return try PhotoPreparationPolicy.add([Int64(max(current, maximum.encoded().count)), 64])
            }
            if version >= 4, let receipt {
                // Retain the maximum slot charge even after closure. A shorter
                // observation is not authority to release metadata or copy liability.
                let maximum = RemoteAttempt(id: claim.attemptID, state: .mayHaveIssued,
                    createdAtMilliseconds: receipt.expiresAtMilliseconds - 1,
                    capabilityExpiresAtMilliseconds: receipt.expiresAtMilliseconds, writeClosed: false)
                let successor = Self(version: version, claim: claim, receipt: receipt, roleMapping: roleMapping,
                    transferReservation: transferReservation, remoteAttempt: maximum, ticketRequestStarted: ticketRequestStarted)
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
