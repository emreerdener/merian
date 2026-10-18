import Foundation
import SwiftData

/// Typed lifecycle orchestration under the repository's existing account and
/// namespace fences. No raw admission, generic save or descriptor API escapes.
@MainActor
final class SharedMediaNativeLifecycleOperations {
    private let container: ModelContainer
    private let inventoryID: UUID
    private let authority: SharedMediaNativeMutationAuthority
    private let io: SharedMediaNativeOriginalIO
    private let availableBytes: () throws -> Int64
    private let boundary: (SharedMediaNativeLifecycleBoundary) throws -> Void
    init(container: ModelContainer, inventoryID: UUID, authority: SharedMediaNativeMutationAuthority,
         io: SharedMediaNativeOriginalIO, availableBytes: @escaping () throws -> Int64,
         boundary: @escaping (SharedMediaNativeLifecycleBoundary) throws -> Void) throws {
        try authority.validate()
        self.container = container; self.inventoryID = inventoryID; self.authority = authority
        self.io = io; self.availableBytes = availableBytes; self.boundary = boundary
    }
    private func sharing() throws -> SharedMediaNativeSharing {
        try boundary(.beforeReadback)
        return try .init(container: container, inventoryID: inventoryID, authority: authority)
    }
    private func removal() throws -> SharedMediaNativeRemoval {
        try boundary(.beforeReadback)
        return try .init(container: container, inventoryID: inventoryID, authority: authority)
    }
    func prepareShare(_ source: PhotoOriginalReference, packageID: UUID, draftGeneration: UUID) throws -> SharedMediaNativeShareRequest {
        try sharing().prepare(source, packageID: packageID, draftGeneration: draftGeneration)
    }
    func prepareRemoval(_ source: PhotoOriginalReference) throws -> SharedMediaNativeRemovalRequest { try removal().prepare(source) }
    func share(_ request: SharedMediaNativeShareRequest) throws -> PhotoOriginalReference {
        do { try sharing().apply(request, availableBytes: availableBytes(), beforeSave: { try self.boundary(.beforeSave) }, afterSave: { try self.boundary(.afterSave) }) }
        catch { let failure = error; do { return try sharing().result(request) } catch { throw failure } }
        return try sharing().result(request)
    }
    func remove(_ request: SharedMediaNativeRemovalRequest) async throws {
        let file = try removal().file(request)
        try authority.validate()
        let proof = request.liveCount == 1 ? try await io.inspect(file) : nil
        try authority.validate()
        do { try removal().apply(request, proof: proof, beforeSave: { try self.boundary(.beforeSave) }, afterSave: { try self.boundary(.afterSave) }) }
        catch { let failure = error; do { try removal().result(request) } catch { throw failure } }
        try removal().result(request)
    }
    func recoverRetirements() async throws {
        while let assetID = try removal().nextRetirementAsset() {
            let state = try removal().retirement(assetID: assetID)
            try authority.validate()
            let intent = SharedMediaNativeRetirement(state: state, binding: authority.binding.bytes, epoch: authority.binding.epoch)
            let proof = try await io.release(intent)
            try authority.validate()
            func release() throws -> SharedMediaNativeRelease {
                try boundary(.beforeReadback)
                return try .init(container: container, inventoryID: inventoryID, authority: authority)
            }
            do { try release().apply(proof, beforeSave: { try self.boundary(.beforeReleaseSave) }, afterSave: { try self.boundary(.afterReleaseSave) }) }
            catch { let failure = error; do { try release().result(state) } catch { throw failure } }
            try release().result(state)
        }
    }
    private func pending() throws -> SharedMediaNativePendingCleanup {
        try boundary(.beforeReadback)
        return try .init(container: container, inventoryID: inventoryID, authority: authority)
    }
    func abandon(_ request: SharedMediaAcquisitionIntent) async throws {
        let state = try pending().state(request)
        if state.closure != nil { return } // Resume only this exact saved abandonment.
        try authority.validate()
        let proof = try await io.inspectPending(request)
        try authority.validate()
        do { try pending().abandon(state, proof: proof, beforeSave: { try self.boundary(.beforeSave) }, afterSave: { try self.boundary(.afterSave) }) }
        catch { let failure = error; do { try pending().abandonedResult(state, closure: proof.closure) } catch { throw failure } }
        try pending().abandonedResult(state, closure: proof.closure)
    }
    func recoverPendingAbandonments() async throws {
        while let request = try pending().nextSavedAbandonment() {
            let state = try pending().state(request)
            try authority.validate()
            let disposal = SharedMediaNativePendingDisposal(state: state, binding: authority.binding.bytes, epoch: authority.binding.epoch)
            let proof = try await io.releasePending(disposal)
            try authority.validate()
            do { try pending().release(proof, beforeSave: { try self.boundary(.beforeReleaseSave) }, afterSave: { try self.boundary(.afterReleaseSave) }) }
            catch { let failure = error; do { try pending().releasedResult(state) } catch { throw failure } }
            try pending().releasedResult(state)
        }
    }
    #if DEBUG
    func setReleaseFault(_ fault: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)?) async throws {
        try authority.validate(); await io.setReleaseFault(fault); try authority.validate()
    }
    #endif
}

struct SharedMediaNativeRetirement: Sendable {
    let state: SharedMediaNativeRetirementState
    let binding: Data
    let epoch: UUID
    fileprivate init(state: SharedMediaNativeRetirementState, binding: Data, epoch: UUID) {
        self.state = state; self.binding = binding; self.epoch = epoch
    }
}

/// Fresh in-memory IO capability, minted only after exact saved-intent readback.
struct SharedMediaNativePendingDisposal: Sendable {
    let state: SharedMediaNativePendingState
    let binding: Data
    let epoch: UUID
    fileprivate init(state: SharedMediaNativePendingState, binding: Data, epoch: UUID) {
        self.state = state; self.binding = binding; self.epoch = epoch
    }
}
