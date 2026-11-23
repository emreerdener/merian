import Foundation
import SwiftData

/// Saved physical observations, not permission to create, read or remove a file.
/// The partial identity is committed before bytes are written; completion keeps
/// that same inode and binds the final exact descriptor after hashing the file.
struct SharedMediaCaptureArtifactStage: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable { case partial, complete }
    let version: Int
    let requestSHA256: String
    let phase: Phase
    let inventoryRevision: Int64
    let partialIdentity: String
    let finalIdentity: String?

    init(request: SharedMediaCaptureArtifactRequest, inventoryRevision: Int64,
         partialIdentity: String, finalIdentity: String? = nil) throws {
        version = 1; requestSHA256 = try request.digest
        phase = finalIdentity == nil ? .partial : .complete
        self.inventoryRevision = inventoryRevision; self.partialIdentity = partialIdentity
        self.finalIdentity = finalIdentity
        try validate(request)
    }

    func validate(_ request: SharedMediaCaptureArtifactRequest) throws {
        try request.validate()
        guard version == 1, requestSHA256 == (try request.digest),
              inventoryRevision >= (try SharedMediaStoragePolicy.add(request.inventoryRevision, phase == .partial ? 2 : 3)) else {
            throw SharedMediaStorageFailure.conflict
        }
        let partial = try Self.identity(partialIdentity, bytes: 0)
        switch phase {
        case .partial:
            guard finalIdentity == nil else { throw SharedMediaStorageFailure.conflict }
        case .complete:
            guard let finalIdentity,
                  try Self.identity(finalIdentity, bytes: request.byteCount) == partial else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    /// Grammar shared with the native file inspector: device, inode, byte count,
    /// modification seconds/nanoseconds and change seconds/nanoseconds.
    private static func identity(_ value: String, bytes: Int64) throws -> String {
        let identity = try SharedMediaNativeFileIdentity(value)
        guard identity.byteCount == bytes else { throw SharedMediaStorageFailure.conflict }
        return identity.fileID
    }

    func encoded(request: SharedMediaCaptureArtifactRequest) throws -> Data {
        try validate(request)
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes)
    }

    static func decode(_ data: Data, sha256: String, request: SharedMediaCaptureArtifactRequest) throws -> Self {
        guard data.count <= SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes,
              SharedMediaAcquisitionEncoding.isHash(sha256), SharedMediaAcquisitionEncoding.digest(data) == sha256 else {
            throw SharedMediaStorageFailure.conflict
        }
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data, maximum: SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes)
        guard try value.encoded(request: request) == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}

/// Explicit capture-namespace joins. No generic/P1 rejection barrier is relaxed
/// by this reader, and a snapshot conveys no filesystem or mutation authority.
@MainActor
enum SharedMediaCaptureArtifactLedger {
    static let leasePurpose = "captureArtifactV1"
    enum Phase: String, Sendable { case reserved, writing, ready }
    struct Snapshot: Equatable, Sendable {
        let request: SharedMediaCaptureArtifactRequest
        let phase: Phase
        let stage: SharedMediaCaptureArtifactStage?
        let metadataBytes: Int64
        var remoteStage: SharedMediaCaptureRemoteStage?
        var retirement: SharedMediaCaptureArtifactRetirement?
        var acceptedRelease: SharedMediaCaptureMemberRelease?
        var isRetiring: Bool { retirement != nil || acceptedRelease != nil }
        var releasedRevision: Int64? { retirement?.releasedRevision ?? acceptedRelease?.releasedRevision }
    }

    static func receipt(_ row: SharedMediaOrdinaryArtifactRecord) throws -> Snapshot {
        let value = try auditReceipt(row)
        guard !value.isRetiring else { throw SharedMediaStorageFailure.closed }
        return value
    }

    /// Accounting may see permanent retirement receipts. Operational readers
    /// must use receipt/read, which reject every retired source.
    static func auditReceipt(_ row: SharedMediaOrdinaryArtifactRecord) throws -> Snapshot {
        let bytes = try SharedMediaOrdinaryHoldEncoding.metadataBytes([
            (row.requestData, row.requestSHA256), (row.stageReceiptData, row.stageReceiptSHA256),
            (row.acceptanceData, row.acceptanceSHA256), (row.retirementData, row.retirementSHA256)
        ])
        let request = try SharedMediaCaptureArtifactRequest.decode(row.requestData, sha256: row.requestSHA256)
        let membership = [request.profile.ownerID, request.scanID, request.submissionGeneration, request.mediaID]
            .map { $0.uuidString.lowercased() }.joined(separator: ":")
        guard row.schemaVersion == request.schemaVersion, row.id == request.id, row.cursorKey == request.finalName,
              row.membershipKey == membership, row.inventoryID == request.profile.inventoryID,
              row.inventoryGeneration == request.profile.generation, row.ownerID == request.profile.ownerID,
              row.recipientScanID == request.scanID, row.submissionGeneration == request.submissionGeneration,
              row.mediaID == request.mediaID, row.itemIndex == request.itemIndex, row.roleRaw == request.role.rawValue,
              row.frameIndex == request.frameIndex, row.allocationID == request.allocationID,
              row.referenceID == request.referenceID, row.leaseID == request.leaseID, row.writerEpoch == request.writerEpoch else { throw SharedMediaStorageFailure.conflict }
        let acceptedRetired = row.phaseRaw == "acceptedRetiring" || row.phaseRaw == "acceptedReleased"
        let released = row.phaseRaw == "released" || row.phaseRaw == "acceptedReleased"
        let retired = acceptedRetired || row.phaseRaw == "retiring" || row.phaseRaw == "released"
        let phase: Phase
        if retired {
            if let data = row.stageReceiptData, let digest = row.stageReceiptSHA256 {
                phase = try SharedMediaCaptureArtifactStage.decode(data, sha256: digest, request: request).phase == .partial ? .writing : .ready
            } else {
                guard row.stageReceiptData == nil, row.stageReceiptSHA256 == nil else { throw SharedMediaStorageFailure.conflict }
                phase = .reserved
            }
        } else {
            guard let active = Phase(rawValue: row.phaseRaw), row.retirementData == nil, row.retirementSHA256 == nil else {
                throw SharedMediaStorageFailure.conflict
            }
            phase = active
        }
        let retirementSteps: Int64 = retired ? (released ? 2 : 1) : 0
        let stage: SharedMediaCaptureArtifactStage?
        switch phase {
        case .reserved:
            guard row.revision == retirementSteps, row.stageReceiptData == nil, row.stageReceiptSHA256 == nil else {
                throw SharedMediaStorageFailure.conflict
            }
            stage = nil
        case .writing, .ready:
            guard row.revision == (phase == .writing ? 1 : row.acceptanceData == nil ? 2 : 3) + retirementSteps,
                  let data = row.stageReceiptData, let digest = row.stageReceiptSHA256 else { throw SharedMediaStorageFailure.conflict }
            let saved = try SharedMediaCaptureArtifactStage.decode(data, sha256: digest, request: request)
            guard saved.phase == (phase == .writing ? .partial : .complete) else { throw SharedMediaStorageFailure.conflict }
            stage = saved
        }
        let remote: SharedMediaCaptureRemoteStage?
        if row.acceptanceData == nil && row.acceptanceSHA256 == nil { remote = nil } else {
            guard phase == .ready, let stage, let data = row.acceptanceData, let digest = row.acceptanceSHA256 else {
                throw SharedMediaStorageFailure.conflict
            }
            remote = try .decode(data, sha256: digest, request: request, stage: stage)
        }
        let retirement: SharedMediaCaptureArtifactRetirement?
        if retired && !acceptedRetired {
            guard remote == nil, let data = row.retirementData, let digest = row.retirementSHA256 else {
                throw SharedMediaStorageFailure.conflict
            }
            let value = try SharedMediaCaptureArtifactRetirement.decode(data, sha256: digest, request: request, stage: stage)
            guard (value.releasedRevision != nil) == (row.phaseRaw == "released") else { throw SharedMediaStorageFailure.conflict }
            retirement = value
        } else { retirement = nil }
        let acceptedRelease: SharedMediaCaptureMemberRelease?
        if acceptedRetired {
            guard phase == .ready, let stage, let remote,
                  let data = row.retirementData, let digest = row.retirementSHA256 else { throw SharedMediaStorageFailure.conflict }
            let value = try SharedMediaCaptureMemberRelease.decode(data, sha256: digest,
                request: request, stage: stage, remote: remote)
            guard (value.releasedRevision != nil) == released else { throw SharedMediaStorageFailure.conflict }
            acceptedRelease = value
        } else { acceptedRelease = nil }
        return .init(request: request, phase: phase, stage: stage, metadataBytes: bytes, remoteStage: remote,
            retirement: retirement, acceptedRelease: acceptedRelease)
    }

    static func read(id: UUID, profile: SharedMediaNativeAppProfile, rootBindingSHA256: String,
                     context: ModelContext) throws -> Snapshot {
        let value = try auditRead(id: id, profile: profile, rootBindingSHA256: rootBindingSHA256, context: context)
        guard !value.isRetiring else { throw SharedMediaStorageFailure.closed }
        let parent = try SharedMediaCaptureSubmissionReceipt.auditMatching(scanID: value.request.scanID,
            generation: value.request.submissionGeneration, in: context)
        guard parent?.release == nil else { throw SharedMediaStorageFailure.closed }
        return value
    }

    static func auditRead(id: UUID, profile: SharedMediaNativeAppProfile, rootBindingSHA256: String,
                          context: ModelContext) throws -> Snapshot {
        try auditRead(id: id, profile: profile, rootBindingSHA256: rootBindingSHA256, context: context, erasure: nil)
    }

    static func auditErasureRead(id: UUID, profile: SharedMediaNativeAppProfile, rootBindingSHA256: String,
                                 context: ModelContext, erasure: SharedMediaNativeErasureAuditScope) throws -> Snapshot {
        guard erasure.profile == profile else { throw SharedMediaStorageFailure.conflict }
        try erasure.requireCurrent(context)
        let result = try auditRead(id: id, profile: profile, rootBindingSHA256: rootBindingSHA256, context: context, erasure: erasure)
        try erasure.requireCurrent(context)
        return result
    }

    private static func auditRead(id: UUID, profile: SharedMediaNativeAppProfile, rootBindingSHA256: String,
                                  context: ModelContext, erasure: SharedMediaNativeErasureAuditScope?) throws -> Snapshot {
        try Task.checkCancellation()
        guard !context.hasChanges, !context.container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let row = try one(context, FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.id == id }))
        let value = try auditReceipt(row), request = value.request, inventoryID = profile.inventoryID
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let savedProfile = try erasure == nil ? SharedMediaNativeAppEligibility.profile(inventory)
            : SharedMediaNativeAppEligibility.profileAssertion(inventory)
        guard savedProfile == profile,
              request.profile == profile, request.rootBindingSHA256 == rootBindingSHA256,
              inventory.revision >= (try SharedMediaStoragePolicy.add(request.inventoryRevision, 1)),
              value.stage.map({ $0.inventoryRevision <= inventory.revision }) ?? true,
              value.remoteStage.map({ $0.inventoryRevision <= inventory.revision }) ?? true,
              value.retirement.map({ ($0.releasedRevision ?? $0.inventoryRevision) <= inventory.revision }) ?? true,
              value.acceptedRelease.map({ ($0.releasedRevision ?? $0.inventoryRevision) <= inventory.revision }) ?? true else { throw SharedMediaStorageFailure.conflict }
        let allocationID = request.allocationID, leaseID = request.leaseID, referenceID = request.referenceID
        // Reverse joins prevent an extra lease/reference or another artifact
        // from borrowing this allocation, even if its forward fields look valid.
        let namespace = SharedMediaCaptureRootJournal.namespace, fileToken = request.finalName
        let allocation = try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate {
            $0.id == allocationID || ($0.namespaceRaw == namespace && $0.fileToken == fileToken)
        }))
        let lease = try one(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID || $0.allocationID == allocationID }))
        let reference = try one(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID || $0.allocationID == allocationID }))
        let reverse = try one(context, FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate {
            $0.allocationID == allocationID || $0.referenceID == referenceID || $0.leaseID == leaseID
        }))
        let ready = value.phase == .ready, retired = value.isRetiring
        let released = value.releasedRevision != nil
        guard reverse.id == id, allocation.id == allocationID,
              allocation.inventoryID == profile.inventoryID, allocation.accountID == profile.ownerID,
              allocation.packageID == request.scanID, allocation.namespaceRaw == SharedMediaCaptureRootJournal.namespace,
              allocation.fileToken == request.finalName, allocation.poolRaw == "durable",
              allocation.stateRaw == (retired ? (released ? "released" : "retiring") : value.phase.rawValue),
              allocation.materializedBytes == (ready && !released ? request.byteCount : 0),
              allocation.reservedBytes == (ready || released ? 0 : request.byteCount),
              allocation.physicalIdentity == (released ? nil : ready ? value.stage?.finalIdentity : value.stage?.partialIdentity),
              lease.id == leaseID, lease.allocationID == allocationID, lease.processEpoch == request.writerEpoch,
              lease.purposeRaw == leasePurpose, lease.stateRaw == (ready || retired ? "closed" : "open"),
              reference.id == referenceID, reference.allocationID == allocationID, reference.accountID == profile.ownerID,
              reference.ownerID == request.id.uuidString.lowercased(), reference.roleRaw == SharedMediaCaptureRootJournal.namespace,
              reference.stateRaw == (released ? "released" : "held"), reference.revision == (released ? 1 : 0) else { throw SharedMediaStorageFailure.conflict }
        try Task.checkCancellation()
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}

/// Canonical stat descriptor shared by original-media receipts and erasure
/// evidence. Darwin device IDs are signed Int32; inode IDs are unsigned UInt64.
struct SharedMediaNativeFileIdentity {
    let fileID: String
    let byteCount: Int64

    init(_ value: String) throws {
        guard value.utf8.count <= 160 else { throw SharedMediaStorageFailure.conflict }
        let fields = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 7, let device = Int32(fields[0]), String(device) == fields[0],
              let inode = UInt64(fields[1]), inode > 0, String(inode) == fields[1],
              let count = Int64(fields[2]), count >= 0, String(count) == fields[2] else {
            throw SharedMediaStorageFailure.conflict
        }
        for index in 3...6 {
            guard let number = Int64(fields[index]), String(number) == fields[index],
                  index % 2 != 0 || (0...999_999_999).contains(number) else { throw SharedMediaStorageFailure.conflict }
        }
        fileID = fields[0] + ":" + fields[1]; byteCount = count
    }
}
