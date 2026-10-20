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

    func inspectPlannedAbsent() throws -> SharedMediaNativePlannedAbsence {
        let (work, _) = try state.selected(workID)
        guard state.phase == "planned", state.publishedRevision == nil,
              work.phase == "planned", work.writerState == "absent",
              work.device == nil, work.inode == nil, work.finalIdentity == nil,
              work.retirementID == nil, work.retirementPartial == nil, work.retirementFinal == nil,
              work.retirementParent == nil, work.retirementNamespace == nil, work.closure == nil else {
            throw SharedMediaStorageFailure.conflict
        }
        return try .init(state: state, workID: workID, identity: bytes().inspectPlannedAbsent(), binding: binding.bytes, epoch: binding.epoch)
    }

    func begin() throws -> SharedMediaNativePairPartial {
        let (work, _) = try state.selected(workID)
        guard state.phase == "writing", work.phase == "reserved", work.writerState == "open",
              work.writerEpoch == binding.epoch, work.device == nil, work.inode == nil,
              work.finalIdentity == nil, work.retirementID == nil, work.closure == nil else {
            throw SharedMediaStorageFailure.conflict
        }
        let identity = try bytes().begin(), location = try bytes().inspectReservedEmpty()
        guard location.partial == identity.exact, location.final == "absent" else { throw SharedMediaStorageFailure.conflict }
        return .init(state: state, workID: workID, identity: identity, location: location, binding: binding.bytes, epoch: binding.epoch)
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

    func inspectCompleted() throws -> SharedMediaNativePairCompletion {
        let (work, _) = try state.selected(workID)
        guard ["writing", "ready"].contains(state.phase), work.phase == "completed",
              work.writerState == "closed", work.finalIdentity != nil, work.retirementID == nil,
              work.closure == nil else { throw SharedMediaStorageFailure.conflict }
        let (file, identity) = try bytes().inspectCompleted()
        return .init(state: state, workID: workID, file: file, identity: identity, binding: binding.bytes, epoch: binding.epoch)
    }
    func requireCurrentCompletion(_ proof: SharedMediaNativePairCompletion) throws {
        guard proof.state == state, proof.workID == workID, proof.binding == binding.bytes, proof.epoch == binding.epoch,
              proof.file == (try state.file(workID)) else { throw SharedMediaStorageFailure.stale }
        try bytes().requireCompletedIdentity(proof.identity)
    }
    func requireCurrentPartial(_ proof: SharedMediaNativePairPartial) throws {
        guard proof.state == state, proof.workID == workID, proof.binding == binding.bytes, proof.epoch == binding.epoch,
              proof.identity.bytes == 0, proof.location.partial == proof.identity.exact,
              try bytes().inspectReservedEmpty() == proof.location else { throw SharedMediaStorageFailure.stale }
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
    let location: SharedMediaInboxDestinationRetirementIdentity
    let binding: Data, epoch: UUID
    fileprivate init(state: SharedMediaNativePairFileState, workID: UUID, identity: SharedMediaInboxFileIdentity, location: SharedMediaInboxDestinationRetirementIdentity, binding: Data, epoch: UUID) {
        self.state = state; self.workID = workID; self.identity = identity; self.location = location; self.binding = binding; self.epoch = epoch
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

/// Read-only absence, bound to the held namespace. It grants no unlink authority.
struct SharedMediaNativePlannedAbsence: Sendable {
    let state: SharedMediaNativePairFileState, workID: UUID
    let identity: SharedMediaInboxDestinationRetirementIdentity
    let binding: Data, epoch: UUID
    fileprivate init(state: SharedMediaNativePairFileState, workID: UUID, identity: SharedMediaInboxDestinationRetirementIdentity, binding: Data, epoch: UUID) {
        self.state = state; self.workID = workID; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}

extension PhotoPreparationLockedFiles {
    func requireCurrentPairCompletion(_ proof: SharedMediaNativePairCompletion, binding: SharedMediaNativeBinding) throws {
        try withNativePairDestination(proof.state, workID: proof.workID, binding: binding, create: false) { try $0.requireCurrentCompletion(proof) }
    }

    func requireCurrentPairPartial(_ proof: SharedMediaNativePairPartial, binding: SharedMediaNativeBinding) throws {
        try withNativePairDestination(proof.state, workID: proof.workID, binding: binding, create: false) { try $0.requireCurrentPartial(proof) }
    }

    func requireCurrentPlannedAbsence(_ proof: SharedMediaNativePlannedAbsence, binding: SharedMediaNativeBinding) throws {
        guard proof.binding == binding.bytes, proof.epoch == binding.epoch else { throw SharedMediaStorageFailure.stale }
        try withNativePairDestination(proof.state, workID: proof.workID, binding: binding, create: false) {
            guard try $0.inspectPlannedAbsent().identity == proof.identity else { throw SharedMediaStorageFailure.stale }
        }
    }
}
