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
    /// Accepted V13 records retain the exact positive response without retiring
    /// the original role, remote attempt, or its copy liability.
    let liveRoleReceipt: Data?
    /// V14…16 retain earlier roles in original assignment order and use the
    /// same request, PUT, observation and receipt phases as V11…13.
    struct CompletedRole: Codable, Sendable, Equatable {
        let transfer: SharedMediaNativePhotoTransferReservation
        let attempt: RemoteAttempt
        let liveReceipt: Data
    }
    let completedRoles: [CompletedRole]?
    var transferPhase: Int { (14...16).contains(version) ? version - 3 : version }
    var remainingAdvances: Int64 {
        if version == 17 { return 0 }
        if completedRoles != nil { return activeRole.remainingAdvances }
        if version == 13 { return 0 }
        if version == 6 { return (receipt == nil ? 1 : 0) + (backendBinding == nil ? 1 : 0) }
        if version == 7 { return 0 }
        if version == 10 || version == 11 { return (version == 10 ? 2 : 1) + (remoteAttempt?.remainingAdvances ?? 3) }
        if version == 12 { return remoteAttempt?.remainingAdvances ?? 0 }
        if (4...5).contains(version) || (8...9).contains(version) { return remoteAttempt?.remainingAdvances ?? 3 }
        return (receipt == nil ? 1 : 0) + (version == 2 && roleMapping == nil ? 1 : 0)
    }

    init(claim: Claim) { self.init(version: 1, claim: claim, receipt: nil, roleMapping: nil) }
    private init(version: Int, claim: Claim, receipt: Receipt?, roleMapping: SharedMediaNativePhotoRoleMapping?, transferReservation: SharedMediaNativePhotoTransferReservation? = nil, remoteAttempt: RemoteAttempt? = nil, ticketRequestStarted: Bool? = nil, backendBinding: BackendBinding? = nil, liveRoleReceipt: Data? = nil, completedRoles: [CompletedRole]? = nil) {
        self.completedRoles = completedRoles
        self.version = version; self.claim = claim; self.receipt = receipt; self.roleMapping = roleMapping
        self.liveRoleReceipt = liveRoleReceipt
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
        guard (2...12).contains(version), let receipt, let roleMapping,
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
        guard (3...5).contains(version) || (7...12).contains(version) else { throw SharedMediaStorageFailure.closed }
        if (4...5).contains(version) || (8...12).contains(version) { return self }
        let after = Self(version: version == 7 ? 8 : 4, claim: claim, receipt: receipt, roleMapping: roleMapping,
                         transferReservation: transferReservation, backendBinding: backendBinding)
        _ = try after.storageCharge
        return after
    }

    /// Reserve the complete future ticket/PUT/status liability before issuance.
    /// Legacy ticket uncertainty and observed attempts never enter this branch.
    func reservingPutStart() throws -> Self {
        _ = try encoded()
        if (10...12).contains(version) { return self }
        guard version == 8, remoteAttempt == nil else { throw SharedMediaStorageFailure.closed }
        let after = Self(version: 10, claim: claim, receipt: receipt, roleMapping: roleMapping,
            transferReservation: transferReservation, backendBinding: backendBinding)
        _ = try after.storageCharge
        return after
    }

    /// Historical value only. A fresh consumed ticket and acknowledged owner
    /// save/readback are separately required before any upload can be constructed.
    func startingPut(_ attempt: RemoteAttempt) throws -> Self {
        _ = try encoded()
        if let prefix = completedRoles { return try activeRole.startingPut(attempt).appendingPrefix(prefix) }
        guard version == 11, remoteAttempt == nil, attempt.state == .mayHaveIssued,
              !attempt.writeClosed else { throw SharedMediaStorageFailure.closed }
        let after = Self(version: 12, claim: claim, receipt: receipt, roleMapping: roleMapping,
            transferReservation: transferReservation, remoteAttempt: attempt,
            ticketRequestStarted: true, backendBinding: backendBinding)
        _ = try after.encoded()
        return after
    }

    /// The owner reserves this save plus three future status saves before any
    /// request. Existing remote facts or a decoded marker cannot mint permission.
    func startingTicketRequest() throws -> Self {
        _ = try encoded()
        if let prefix = completedRoles { return try activeRole.startingTicketRequest().appendingPrefix(prefix) }
        guard version == 4 || version == 8 || version == 10, remoteAttempt == nil else { throw SharedMediaStorageFailure.closed }
        let after = Self(version: version == 10 ? 11 : (version == 8 ? 9 : 5), claim: claim, receipt: receipt, roleMapping: roleMapping,
            transferReservation: transferReservation, ticketRequestStarted: true, backendBinding: backendBinding)
        _ = try after.storageCharge
        return after
    }

    func observing(_ status: InitialPhotoUploadStatus) throws -> Self {
        _ = try encoded()
        if let prefix = completedRoles, let transferReservation {
            try status.requireMatch(self, objectID: transferReservation.selection.objectID)
            let next = status.attempt.map {
                RemoteAttempt(id: $0.id, state: $0.state == .bound ? .bound : .mayHaveIssued,
                              createdAtMilliseconds: $0.createdAtMilliseconds, capabilityExpiresAtMilliseconds: $0.capabilityExpiresAtMilliseconds,
                              writeClosed: $0.writeClosed)
            }
            if version == 16 {
                guard next == remoteAttempt else { throw SharedMediaStorageFailure.conflict }
                return self
            }
            return try activeRole.recording(next).appendingPrefix(prefix)
        }
        if version == 13 {
            let original = liveRoleVersion(12, receiptBytes: nil)
            guard try original.observing(status) == original else { throw SharedMediaStorageFailure.conflict }
            return self
        }
        guard (4...5).contains(version) || (8...12).contains(version), let transferReservation else { throw SharedMediaStorageFailure.closed }
        try status.requireMatch(self, objectID: transferReservation.selection.objectID)
        let value = status.attempt.map {
            RemoteAttempt(id: $0.id, state: $0.state == .bound ? .bound : .mayHaveIssued,
                createdAtMilliseconds: $0.createdAtMilliseconds,
                capabilityExpiresAtMilliseconds: $0.capabilityExpiresAtMilliseconds, writeClosed: $0.writeClosed)
        }
        return try recording(value)
    }

    private func recording(_ value: RemoteAttempt?) throws -> Self {
        guard (4...5).contains(version) || (8...12).contains(version) else { throw SharedMediaStorageFailure.closed }
        try remoteAttempt?.requireSuccessor(value)
        let after = Self(version: version, claim: claim, receipt: receipt, roleMapping: roleMapping,
                         transferReservation: transferReservation, remoteAttempt: value, ticketRequestStarted: ticketRequestStarted,
                         backendBinding: backendBinding)
        _ = try after.encoded()
        return after
    }

    private func liveRoleVersion(_ phase: Int, receiptBytes: Data?) -> Self {
        Self(version: phase, claim: claim, receipt: receipt, roleMapping: roleMapping,
             transferReservation: transferReservation, remoteAttempt: remoteAttempt,
             ticketRequestStarted: ticketRequestStarted, backendBinding: backendBinding, liveRoleReceipt: receiptBytes)
    }

    private var activeRole: Self {
        Self(version: transferPhase, claim: claim, receipt: receipt, roleMapping: roleMapping,
             transferReservation: transferReservation, remoteAttempt: remoteAttempt,
             ticketRequestStarted: ticketRequestStarted, backendBinding: backendBinding, liveRoleReceipt: liveRoleReceipt)
    }

    private func appendingPrefix(_ prefix: [CompletedRole]) throws -> Self {
        guard (11...13).contains(version), completedRoles == nil else { throw SharedMediaStorageFailure.closed }
        return Self(version: version + 3, claim: claim, receipt: receipt, roleMapping: roleMapping,
                    transferReservation: transferReservation, remoteAttempt: remoteAttempt, ticketRequestStarted: ticketRequestStarted,
                    backendBinding: backendBinding, liveRoleReceipt: liveRoleReceipt, completedRoles: prefix)
    }

    private func historicalRole(_ member: CompletedRole) -> Self {
        Self(version: 13, claim: claim, receipt: receipt, roleMapping: roleMapping,
             transferReservation: member.transfer, remoteAttempt: member.attempt, ticketRequestStarted: true,
             backendBinding: backendBinding, liveRoleReceipt: member.liveReceipt)
    }

    func requireRetiredOriginal(_ original: Self) throws {
        guard transferPhase == 13, original.transferPhase == 12,
              completedRoles == original.completedRoles, let remoteAttempt, remoteAttempt.writeClosed else {
            throw SharedMediaStorageFailure.stale
        }
        let closed = try original.activeRole.recording(remoteAttempt)
        try activeRole.historicalLiveRole().requireOriginal(closed)
    }

    func sealingCompletedRoster() throws -> Self {
        guard transferPhase == 13, let transferReservation, let remoteAttempt, let liveRoleReceipt,
              let mapping = roleMapping else { throw SharedMediaStorageFailure.closed }
        var all = completedRoles ?? []
        all.append(.init(transfer: transferReservation, attempt: remoteAttempt, liveReceipt: liveRoleReceipt))
        guard all.map(\.transfer.selection) == mapping.entries else { throw SharedMediaStorageFailure.conflict }
        return Self(version: 17, claim: claim, receipt: receipt, roleMapping: mapping,
                    backendBinding: backendBinding, completedRoles: all)
    }

    private func finalPredecessor() throws -> Self {
        guard version == 17, let all = completedRoles, let last = all.last, let mapping = roleMapping,
              (3...6).contains(all.count), all.count == mapping.entries.count else { throw SharedMediaStorageFailure.conflict }
        return try historicalRole(last).appendingPrefix(Array(all.dropLast()))
    }

    /// Value proposal only. Only the receiving owner may persist it, after
    /// consuming a live local retirement witness for this precise predecessor.
    func reservingFollowingRole(_ next: SharedMediaNativePhotoTransferReservation) throws -> Self {
        _ = try encoded()
        guard transferPhase == 13, let transferReservation, let remoteAttempt, let liveRoleReceipt,
              let mapping = roleMapping else { throw SharedMediaStorageFailure.closed }
        var prefix = completedRoles ?? []
        guard prefix.count + 1 < mapping.entries.count,
              transferReservation.selection == mapping.entries[prefix.count],
              next.selection == mapping.entries[prefix.count + 1] else { throw SharedMediaStorageFailure.conflict }
        prefix.append(.init(transfer: transferReservation, attempt: remoteAttempt, liveReceipt: liveRoleReceipt))
        let nextActive = Self(version: 11, claim: claim, receipt: receipt, roleMapping: mapping,
                              transferReservation: next, ticketRequestStarted: true, backendBinding: backendBinding)
        let after = try nextActive.appendingPrefix(prefix)
        _ = try after.encoded()
        return after
    }

    func retainingLiveRole(_ proof: InitialPhotoRoleProgress) throws -> Self {
        try proof.requireOriginal(self)
        if let prefix = completedRoles {
            if version == 16, liveRoleReceipt == proof.canonicalReceipt { return self }
            guard version == 15 else { throw SharedMediaStorageFailure.closed }
            let after = try activeRole.liveRoleVersion(13, receiptBytes: proof.canonicalReceipt).appendingPrefix(prefix)
            _ = try after.encoded()
            return after
        }
        if version == 13, liveRoleReceipt == proof.canonicalReceipt { return self }
        guard version == 12 else { throw SharedMediaStorageFailure.closed }
        let after = liveRoleVersion(13, receiptBytes: proof.canonicalReceipt)
        _ = try after.encoded()
        return after
    }

    /// A saved receipt describes the original attempt only. Fresh next-role
    /// admission must still check current server eligibility and local storage.
    func historicalLiveRole() throws -> InitialPhotoRoleProgress {
        guard version == 13, let bytes = liveRoleReceipt else { throw SharedMediaStorageFailure.closed }
        let original = liveRoleVersion(12, receiptBytes: nil)
        let request = try InitialPhotoTransferRequest(allocation: original, action: .roleProgress)
        let proof = try InitialPhotoRoleProgress(data: bytes, matching: request)
        guard proof.canonicalReceipt == bytes else { throw SharedMediaStorageFailure.conflict }
        return proof
    }

    /// Exact permitted one-save transitions. No downgrade, replacement or
    /// enrichment before reservation can enter the sidecar write set.
    func requireSuccessor(_ after: Self) throws {
        _ = try encoded(); _ = try after.encoded()
        if after.version == 17 {
            guard try sealingCompletedRoster() == after else { throw SharedMediaStorageFailure.conflict }
            return
        }
        guard version != 17 else { throw SharedMediaStorageFailure.closed }
        if transferPhase == 13, after.version == 14, let next = after.transferReservation {
            guard try reservingFollowingRole(next) == after else { throw SharedMediaStorageFailure.conflict }
            return
        }
        if let prefix = completedRoles {
            guard prefix == after.completedRoles, (14...16).contains(after.version) else { throw SharedMediaStorageFailure.conflict }
            try activeRole.requireSuccessor(after.activeRole)
            return
        }
        if version == 12, after.version == 13 {
            try after.historicalLiveRole().requireOriginal(self)
            return
        }
        if (version == 2 && after.version == 3) || (version == 6 && after.version == 7), let value = after.transferReservation {
            guard try reservingTransfer(value) == after else { throw SharedMediaStorageFailure.conflict }
            return
        }
        guard after != self else { throw SharedMediaStorageFailure.closed }
        if (version == 3 && after.version == 4) || (version == 7 && after.version == 8) {
            guard try reservingRemoteAttempt() == after else { throw SharedMediaStorageFailure.conflict }
            return
        }
        if (version == 4 && after.version == 5) || (version == 8 && after.version == 9) || (version == 10 && after.version == 11) {
            guard try startingTicketRequest() == after else { throw SharedMediaStorageFailure.conflict }
            return
        }
        if version == 8, after.version == 10 {
            guard try reservingPutStart() == after else { throw SharedMediaStorageFailure.conflict }
            return
        }
        if version == 11, after.version == 12, let attempt = after.remoteAttempt {
            guard try startingPut(attempt) == after else { throw SharedMediaStorageFailure.conflict }
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
        if (4...5).contains(version) || (8...12).contains(version) {
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
        if version == 17 {
            let final = try finalPredecessor()
            _ = try final.encoded()
            guard try final.sealingCompletedRoster() == self else { throw SharedMediaStorageFailure.conflict }
            return try SharedMediaAcquisitionEncoding.encode(self, maximum: Self.maximumBytes)
        }
        if let prefix = completedRoles {
            guard (14...16).contains(version), let mapping = roleMapping,
                  !prefix.isEmpty, prefix.count < mapping.entries.count, mapping.entries.count <= 6,
                  mapping.entries[prefix.count] == transferReservation?.selection else { throw SharedMediaStorageFailure.conflict }
            _ = try activeRole.encoded()
            var attempts = Set<UUID>()
            for (index, member) in prefix.enumerated() {
                guard mapping.entries[index] == member.transfer.selection,
                      attempts.insert(member.attempt.id).inserted else { throw SharedMediaStorageFailure.conflict }
                _ = try historicalRole(member).historicalLiveRole()
            }
            if let remoteAttempt, attempts.contains(remoteAttempt.id) { throw SharedMediaStorageFailure.conflict }
            return try SharedMediaAcquisitionEncoding.encode(self, maximum: Self.maximumBytes)
        }
        if version == 13 {
            _ = try historicalLiveRole()
            return try SharedMediaAcquisitionEncoding.encode(self, maximum: Self.maximumBytes)
        }
        guard liveRoleReceipt == nil, (1...12).contains(version), !claim.candidateCanonical.isEmpty,
              claim.candidateCanonical.utf8.count <= 1_048_576,
              [claim.preparedSHA256, claim.receivedSHA256, claim.candidateDigest, claim.contentDigest]
                .allSatisfy(SharedMediaAcquisitionEncoding.isHash) else { throw SharedMediaStorageFailure.conflict }
        guard version >= 2 || roleMapping == nil, roleMapping == nil || receipt != nil,
              ((3...5).contains(version) || (7...12).contains(version)) == (transferReservation != nil),
              transferReservation == nil || (receipt != nil && roleMapping != nil),
              (4...5).contains(version) || (8...12).contains(version) || remoteAttempt == nil,
              version >= 6 || backendBinding == nil,
              version < 7 || backendBinding != nil,
              backendBinding == nil || (receipt != nil && roleMapping != nil),
              (version == 5 || version == 9 || version >= 11) ? ticketRequestStarted == true : ticketRequestStarted == nil else {
            throw SharedMediaStorageFailure.conflict
        }
        guard version != 12 || remoteAttempt?.state == .mayHaveIssued else { throw SharedMediaStorageFailure.conflict }
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
            if version == 17 {
                let prior = try finalPredecessor()
                let growth = max(0, current - (try prior.encoded().count))
                return try PhotoPreparationPolicy.add([prior.storageCharge, Int64(growth)])
            }
            if let prefix = completedRoles {
                let active = activeRole
                let delta = current - (try active.encoded().count)
                guard delta > 0 else { throw SharedMediaStorageFailure.conflict }
                // The framing delta includes every materialized historical
                // field. Keep the unused historical reservation headroom too.
                var charges = [try active.storageCharge, Int64(delta)]
                for member in prefix {
                    let previous = historicalRole(member)
                    let reserved = try previous.storageCharge - Int64(previous.encoded().count) - 64
                    guard reserved >= 0 else { throw SharedMediaStorageFailure.conflict }
                    charges.append(reserved)
                }
                return try PhotoPreparationPolicy.add(charges)
            }
            if version == 13 {
                let prior = liveRoleVersion(12, receiptBytes: nil)
                let delta = current - (try prior.encoded().count)
                guard delta > 0 else { throw SharedMediaStorageFailure.conflict }
                return try PhotoPreparationPolicy.add([prior.storageCharge, Int64(delta)])
            }
            if version >= 6 {
                // Every bound phase retains V6's full receipt/mapping/tuple charge.
                // Later reservations add transfer and maximum remote-slot metadata;
                // status or closure never shrinks this liability.
                let receipt = Receipt(assignmentDigest: String(repeating: "f", count: 64),
                    createdAtMilliseconds: 8_639_999_998_200_000, expiresAtMilliseconds: 8_640_000_000_000_000)
                let remote: RemoteAttempt? = version >= 8 ? .init(id: claim.attemptID, state: .mayHaveIssued,
                    createdAtMilliseconds: receipt.expiresAtMilliseconds - 1,
                    capabilityExpiresAtMilliseconds: receipt.expiresAtMilliseconds, writeClosed: false) : nil
                let phases = version >= 10 ? [10, 11, 12] : [version]
                let sizes = try phases.map { phase in
                    try Self(version: phase, claim: claim, receipt: receipt,
                        roleMapping: roleMapping ?? .reservation(claim), transferReservation: transferReservation,
                        remoteAttempt: remote, ticketRequestStarted: phase >= 10 ? (phase >= 11 ? true : nil) : ticketRequestStarted,
                        backendBinding: .init(generation: claim.attemptID, configurationDigest: String(repeating: "f", count: 64))).encoded().count
                }
                return try PhotoPreparationPolicy.add([Int64(max(current, sizes.max() ?? current)), 64])
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
