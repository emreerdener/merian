import CryptoKit
import Foundation

/// Typed derivative lifecycle adapter. It never borrows original-source holds.
struct SharedMediaDerivativeWorkFiles {
    let access: SharedMediaInboxDestinationAccess
    let state: SharedMediaDerivativeWork
    let binding: SharedMediaPhotoBinding
    var fault: ((SharedMediaInboxHandoffBoundary) throws -> Void)?

    private var bytes: SharedMediaDestinationBytes {
        .init(access: access, expected: state.file, device: state.device, inode: state.inode,
              finalIdentity: state.finalIdentity, fault: fault)
    }

    static func prepare(_ data: Data, role: PhotoPreparationRole) throws -> SharedMediaDerivativeInput {
        guard role != .original else { throw SharedMediaStorageFailure.invalid }
        let type = try PhotoPreparationLockedFiles.validateImage(data, maximumBytes: PhotoPreparationPolicy.limit(for: role))
        return .init(id: UUID(), role: role.rawValue, assetID: UUID(), assetGeneration: UUID(),
                     referenceID: UUID(), leaseID: UUID(), byteCount: Int64(data.count),
                     sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), contentType: type)
    }

    static func validate(_ data: Data, input: SharedMediaDerivativeInput) throws {
        try input.validate()
        guard Int64(data.count) == input.byteCount,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == input.sha256,
              try PhotoPreparationLockedFiles.validateImage(data, maximumBytes: input.byteCount) == input.contentType else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    func begin() throws -> SharedMediaDerivativePartial {
        guard state.phase == "reserved", state.writerState == "open",
              state.writerEpoch == binding.epoch, state.inode == nil, state.retirementID == nil else { throw SharedMediaStorageFailure.conflict }
        return try .init(work: state, identity: bytes.begin(), binding: binding.bytes, epoch: binding.epoch)
    }

    func write(_ data: Data) throws -> SharedMediaDerivativeCompletion {
        guard state.phase == "writing", state.writerState == "open",
              state.writerEpoch == binding.epoch, state.retirementID == nil else { throw SharedMediaStorageFailure.conflict }
        let (file, identity) = try bytes.write(data)
        return .init(work: state, file: file, identity: identity, binding: binding.bytes, epoch: binding.epoch)
    }

    func recover() throws -> SharedMediaDerivativeCompletion? {
        guard ["reserved", "writing", "completed"].contains(state.phase), state.retirementID == nil else { throw SharedMediaStorageFailure.inUse }
        guard let (file, identity) = try bytes.recover() else { return nil }
        return .init(work: state, file: file, identity: identity, binding: binding.bytes, epoch: binding.epoch)
    }

    /// Caller awaits actual writer drain under the same exclusive owner lifetime.
    func closure() throws -> SharedMediaDerivativeClosure {
        guard state.phase != "retiring", state.retirementID == nil else { throw SharedMediaStorageFailure.inUse }
        return try .init(work: state, occupied: bytes.occupancy(), binding: binding.bytes, epoch: binding.epoch)
    }

    func inspectRetirement() throws -> SharedMediaDerivativeInspection {
        guard ["absent", "closed"].contains(state.writerState), state.retirementID == nil else { throw SharedMediaStorageFailure.inUse }
        return try .init(work: state, identity: bytes.inspectRetirement(), binding: binding.bytes, epoch: binding.epoch)
    }

    func release(_ intent: SharedMediaDerivativeRetirement) throws -> SharedMediaDerivativeRelease {
        guard intent.work == state, state.phase == "retiring", state.retirementID != nil,
              ["absent", "closed"].contains(state.writerState),
              intent.binding == binding.bytes, intent.epoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
        try bytes.release(intent.identity)
        return .init(retirement: intent)
    }
}

struct SharedMediaDerivativePartial: Sendable {
    let work: SharedMediaDerivativeWork
    let identity: SharedMediaInboxFileIdentity
    let binding: Data
    let epoch: UUID
    fileprivate init(work: SharedMediaDerivativeWork, identity: SharedMediaInboxFileIdentity, binding: Data, epoch: UUID) {
        self.work = work; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaDerivativeCompletion: Sendable {
    let work: SharedMediaDerivativeWork
    let file: PhotoPreparationFile
    let identity: SharedMediaInboxFileIdentity
    let binding: Data
    let epoch: UUID
    fileprivate init(work: SharedMediaDerivativeWork, file: PhotoPreparationFile, identity: SharedMediaInboxFileIdentity, binding: Data, epoch: UUID) {
        self.work = work; self.file = file; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaDerivativeClosure: Sendable {
    let work: SharedMediaDerivativeWork
    let occupied: Int64
    let binding: Data
    let epoch: UUID
    fileprivate init(work: SharedMediaDerivativeWork, occupied: Int64, binding: Data, epoch: UUID) {
        self.work = work; self.occupied = occupied; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaDerivativeInspection: Sendable {
    let work: SharedMediaDerivativeWork
    let identity: SharedMediaInboxDestinationRetirementIdentity
    let binding: Data
    let epoch: UUID
    fileprivate init(work: SharedMediaDerivativeWork, identity: SharedMediaInboxDestinationRetirementIdentity, binding: Data, epoch: UUID) {
        self.work = work; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaDerivativeRelease: Sendable {
    let retirement: SharedMediaDerivativeRetirement
    fileprivate init(retirement: SharedMediaDerivativeRetirement) { self.retirement = retirement }
}
