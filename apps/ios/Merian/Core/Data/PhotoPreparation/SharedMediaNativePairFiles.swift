import Foundation

/// Native lifecycle checks around the shared descriptor-relative byte mechanics.
/// The enclosing locked namespace supplies a nonescaping file capability.
struct SharedMediaNativePairFiles {
    let access: SharedMediaInboxDestinationAccess
    let state: SharedMediaNativePairFileState
    let workID: UUID
    let binding: SharedMediaNativeBinding
    var fault: ((SharedMediaInboxHandoffBoundary) throws -> Void)?

    private func bytes() throws -> SharedMediaDestinationBytes {
        let (work, _) = try state.selected(workID)
        return try .init(access: access, expected: state.file(workID), device: work.device,
            inode: work.inode, finalIdentity: work.finalIdentity, fault: fault)
    }

    func begin() throws -> SharedMediaNativePairPartial {
        let (work, _) = try state.selected(workID)
        guard state.phase == "writing", work.phase == "reserved", work.writerState == "open",
              work.writerEpoch == binding.epoch, work.device == nil, work.inode == nil,
              work.finalIdentity == nil, work.retirementID == nil, work.closure == nil else {
            throw SharedMediaStorageFailure.conflict
        }
        return try .init(state: state, workID: workID, identity: bytes().begin(), binding: binding.bytes, epoch: binding.epoch)
    }

    func write(_ data: Data) throws -> SharedMediaNativePairCompletion {
        let (work, input) = try state.selected(workID)
        guard state.phase == "writing", work.phase == "writing", work.writerState == "open",
              work.writerEpoch == binding.epoch, work.device != nil, work.inode != nil,
              work.finalIdentity == nil, work.retirementID == nil, work.closure == nil else {
            throw SharedMediaStorageFailure.conflict
        }
        try SharedMediaDerivativeWorkFiles.validate(data, input: input)
        let (file, identity) = try bytes().write(data)
        return .init(state: state, workID: workID, file: file, identity: identity, binding: binding.bytes, epoch: binding.epoch)
    }

    /// Explicit recovery can finish the same saved bytes in a new process epoch.
    /// It cannot create an empty partial, write new bytes or run preparation.
    func recover() throws -> SharedMediaNativePairCompletion? {
        let (work, _) = try state.selected(workID)
        guard ["writing", "ready"].contains(state.phase), ["writing", "completed"].contains(work.phase),
              work.device != nil, work.inode != nil, work.retirementID == nil, work.closure == nil else {
            throw SharedMediaStorageFailure.conflict
        }
        guard let (file, identity) = try bytes().recover() else { return nil }
        return .init(state: state, workID: workID, file: file, identity: identity, binding: binding.bytes, epoch: binding.epoch)
    }

    /// Inspection grants no unlink permission. An unbound reserved name may
    /// contain only an empty regular single-link partial, or no file at all.
    func inspect() throws -> SharedMediaNativePairInspection {
        let (work, _) = try state.selected(workID)
        guard work.retirementID == nil, work.closure == nil else { throw SharedMediaStorageFailure.conflict }
        let identity: SharedMediaInboxDestinationRetirementIdentity
        if work.phase == "reserved", work.device == nil, work.inode == nil {
            identity = try bytes().inspectReservedEmpty()
        } else {
            guard ["writing", "completed"].contains(work.phase), work.device != nil, work.inode != nil else {
                throw SharedMediaStorageFailure.conflict
            }
            identity = try bytes().inspectRetirement()
        }
        return .init(state: state, workID: workID, identity: identity, binding: binding.bytes, epoch: binding.epoch)
    }
    func verify() throws {
        let (work, _) = try state.selected(workID)
        if state.phase == "planned" { return }
        if state.phase == "ready" { try bytes().verifyFinal(); return }
        if state.phase == "retiring" {
            let found = try work.device == nil ? bytes().inspectReservedEmpty() : bytes().inspectRetirement()
            guard found.parent == work.retirementParent, found.namespace == work.retirementNamespace,
                  found.partial == "absent" || found.partial == work.retirementPartial,
                  found.final == "absent" || found.final == work.retirementFinal else { throw SharedMediaStorageFailure.conflict }
        } else { _ = try inspect() }
    }

    func release(_ disposal: SharedMediaNativePairDisposal) throws -> SharedMediaNativePairAbsence {
        let (work, _) = try state.selected(workID)
        guard disposal.state == state, disposal.binding == binding.bytes, disposal.epoch == binding.epoch,
              state.phase == "retiring", work.phase == "retiring", work.writerState == "closed", work.retirementID != nil,
              let partial = work.retirementPartial, let final = work.retirementFinal,
              let parent = work.retirementParent, let namespace = work.retirementNamespace else { throw SharedMediaStorageFailure.closed }
        try bytes().release(.init(partial: partial, final: final, parent: parent, namespace: namespace))
        return .init(state: state, workID: workID, binding: binding.bytes, epoch: binding.epoch)
    }

}

struct SharedMediaNativePairPartial: Sendable {
    let state: SharedMediaNativePairFileState, workID: UUID
    let identity: SharedMediaInboxFileIdentity
    let binding: Data, epoch: UUID
    fileprivate init(state: SharedMediaNativePairFileState, workID: UUID, identity: SharedMediaInboxFileIdentity, binding: Data, epoch: UUID) {
        self.state = state; self.workID = workID; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaNativePairCompletion: Sendable {
    let state: SharedMediaNativePairFileState, workID: UUID
    let file: PhotoPreparationFile, identity: SharedMediaInboxFileIdentity
    let binding: Data, epoch: UUID
    fileprivate init(state: SharedMediaNativePairFileState, workID: UUID, file: PhotoPreparationFile, identity: SharedMediaInboxFileIdentity, binding: Data, epoch: UUID) {
        self.state = state; self.workID = workID; self.file = file; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaNativePairInspection: Sendable {
    let state: SharedMediaNativePairFileState, workID: UUID
    let identity: SharedMediaInboxDestinationRetirementIdentity
    let binding: Data, epoch: UUID
    fileprivate init(state: SharedMediaNativePairFileState, workID: UUID, identity: SharedMediaInboxDestinationRetirementIdentity, binding: Data, epoch: UUID) {
        self.state = state; self.workID = workID; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}

struct SharedMediaNativePairAbsence: Sendable {
    let state: SharedMediaNativePairFileState, workID: UUID
    let binding: Data, epoch: UUID
    fileprivate init(state: SharedMediaNativePairFileState, workID: UUID, binding: Data, epoch: UUID) {
        self.state = state; self.workID = workID; self.binding = binding; self.epoch = epoch
    }
}
