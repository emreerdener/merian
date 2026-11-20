import Foundation

/// Original-handoff lifecycle authority stays separate from derivative work.
struct SharedMediaInboxDestinationFiles {
    let access: SharedMediaInboxDestinationAccess
    let handoff: SharedMediaInboxHandoff
    let binding: SharedMediaPhotoBinding
    #if DEBUG
    var fault: ((SharedMediaInboxHandoffBoundary) throws -> Void)?
    #endif

    private var bytes: SharedMediaDestinationBytes {
        let request = handoff.request
        let expected = PhotoPreparationFile(assetID: request.assetID, generation: request.assetGeneration,
            token: request.intent(epoch: handoff.writerEpoch).fileToken, byteCount: request.byteCount,
            sha256: request.sha256, contentType: "")
        var result = SharedMediaDestinationBytes(access: access, expected: expected, device: handoff.device,
            inode: handoff.inode, finalIdentity: handoff.finalIdentity)
        #if DEBUG
        result.fault = fault
        #endif
        return result
    }

    func begin() throws -> SharedMediaInboxDestinationPartial {
        guard handoff.phase == "reserved", handoff.writerState == "open",
              handoff.writerEpoch == binding.epoch, handoff.inode == nil else { throw SharedMediaStorageFailure.conflict }
        return try .init(handoff: handoff, identity: bytes.begin(), binding: binding.bytes, epoch: binding.epoch)
    }

    func write(_ data: Data) throws -> SharedMediaInboxDestinationCompletion {
        guard handoff.phase == "writing", handoff.writerState == "open", handoff.writerEpoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
        let (file, identity) = try bytes.write(data)
        return .init(handoff: handoff, file: file, identity: identity, binding: binding.bytes, epoch: binding.epoch)
    }

    func recover() throws -> SharedMediaInboxDestinationCompletion? {
        guard !handoff.detached, handoff.phase != "sourceRetiring" else { throw SharedMediaStorageFailure.inUse }
        guard let (file, identity) = try bytes.recover() else { return nil }
        return .init(handoff: handoff, file: file, identity: identity, binding: binding.bytes, epoch: binding.epoch)
    }

    func closure() throws -> SharedMediaInboxDestinationClosure {
        try .init(handoff: handoff, occupied: bytes.occupancy(), binding: binding.bytes, epoch: binding.epoch)
    }

    func inspectRetirement() throws -> SharedMediaInboxDestinationInspection {
        guard handoff.phase == "detached", handoff.writerState == "closed" else { throw SharedMediaStorageFailure.inUse }
        return try .init(handoff: handoff, identity: bytes.inspectRetirement(), binding: binding.bytes, epoch: binding.epoch)
    }

    func release(_ intent: SharedMediaInboxDestinationRetirement) throws -> SharedMediaInboxDestinationRelease {
        guard intent.handoff == handoff, intent.binding == binding.bytes, intent.epoch == binding.epoch,
              handoff.phase == "detachedRetiring", handoff.writerState == "closed" else { throw SharedMediaStorageFailure.conflict }
        try bytes.release(intent.identity)
        return .init(retirement: intent)
    }
}

struct SharedMediaInboxDestinationPartial: Sendable {
    let handoff: SharedMediaInboxHandoff, identity: SharedMediaInboxFileIdentity
    let binding: Data, epoch: UUID
    fileprivate init(handoff: SharedMediaInboxHandoff, identity: SharedMediaInboxFileIdentity, binding: Data, epoch: UUID) {
        self.handoff = handoff; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaInboxDestinationCompletion: Sendable {
    let handoff: SharedMediaInboxHandoff, file: PhotoPreparationFile, identity: SharedMediaInboxFileIdentity
    let binding: Data, epoch: UUID
    fileprivate init(handoff: SharedMediaInboxHandoff, file: PhotoPreparationFile, identity: SharedMediaInboxFileIdentity, binding: Data, epoch: UUID) {
        self.handoff = handoff; self.file = file; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaInboxDestinationClosure: Sendable {
    let handoff: SharedMediaInboxHandoff
    let occupied: Int64
    let binding: Data, epoch: UUID
    fileprivate init(handoff: SharedMediaInboxHandoff, occupied: Int64, binding: Data, epoch: UUID) {
        self.handoff = handoff; self.occupied = occupied; self.binding = binding; self.epoch = epoch
    }
}

struct SharedMediaInboxDestinationInspection: Sendable {
    let handoff: SharedMediaInboxHandoff
    let identity: SharedMediaInboxDestinationRetirementIdentity
    let binding: Data, epoch: UUID
    fileprivate init(handoff: SharedMediaInboxHandoff, identity: SharedMediaInboxDestinationRetirementIdentity, binding: Data, epoch: UUID) {
        self.handoff = handoff; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaInboxDestinationRelease: Sendable {
    let retirement: SharedMediaInboxDestinationRetirement
    fileprivate init(retirement: SharedMediaInboxDestinationRetirement) { self.retirement = retirement }
}
