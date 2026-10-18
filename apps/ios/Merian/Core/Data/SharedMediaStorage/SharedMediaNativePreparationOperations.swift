import Foundation
import SwiftData

/// Only the native fenced repository supplies this authority. The concrete
/// memory-only processor retains that owner; no arbitrary callback, filesystem
/// write, cleanup or legacy construction is exposed.
@MainActor
final class SharedMediaNativePreparationOperations {
    private let container: ModelContainer
    private let inventoryID: UUID
    private let authority: SharedMediaNativeMutationAuthority
    private let focusFactory: ImageFocusWorkFactory
    private let io: SharedMediaNativeOriginalIO
    private let availableBytes: () throws -> Int64
    private let boundary: (SharedMediaNativePreparationBoundary) throws -> Void
    init(container: ModelContainer, inventoryID: UUID, authority: SharedMediaNativeMutationAuthority, io: SharedMediaNativeOriginalIO, focusFactory: ImageFocusWorkFactory,
         availableBytes: @escaping () throws -> Int64, boundary: @escaping (SharedMediaNativePreparationBoundary) throws -> Void) throws {
        try authority.validate()
        self.container = container; self.inventoryID = inventoryID; self.authority = authority; self.io = io
        self.focusFactory = focusFactory
        self.availableBytes = availableBytes; self.boundary = boundary
    }
    private func mutation(_ packageID: UUID) throws -> SharedMediaNativePreparationMutation {
        try boundary(.beforeReadback)
        return try .init(container: container, inventoryID: inventoryID, packageID: packageID, authority: authority)
    }
    func reserve(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) throws -> SharedMediaNativePreparationAttempt {
        let request = try mutation(original.packageID).request(original: original, recipe: recipe)
        do {
            try mutation(original.packageID).reserve(request, availableBytes: availableBytes(),
                beforeSave: { try self.boundary(.beforeSave) }, afterSave: { try self.boundary(.afterSave) })
        } catch {
            let failure = error
            do { try mutation(original.packageID).result(request) } catch { throw failure }
        }
        try mutation(original.packageID).result(request)
        return request
    }
    func active(packageID: UUID) throws -> SharedMediaNativePreparationAttempt? { try mutation(packageID).activeAttempt() }
    /// A fresh reservation is mandatory. Saved attempts never dispatch again.
    /// Output remains in memory and the reservation remains held for the native
    /// pair owner; this operation is not publication or submission.
    func prepare(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe, savePlan: Bool = false) async throws -> SharedMediaNativePreparedOutputs {
        let attempt = try reserve(original: original, recipe: recipe)
        try authority.validate(); try Task.checkCancellation()
        try mutation(original.packageID).result(attempt)
        let output = try await io.preparePhoto(attempt, focusFactory: focusFactory)
        try authority.validate(); try Task.checkCancellation()
        try mutation(original.packageID).result(attempt)
        try output.intent.preparation.requireMatch(attempt)
        if savePlan {
            _ = try pairMutation(original.packageID).plan(output, availableBytes: availableBytes(),
                beforeSave: { try self.boundary(.beforePairSave) }, afterSave: { try self.boundary(.afterPairSave) })
        }
        return output
    }
    private func filesMutation(_ packageID: UUID) throws -> SharedMediaNativePairFileMutation {
        try boundary(.beforeReadback)
        return try .init(container: container, inventoryID: inventoryID, packageID: packageID, authority: authority)
    }
    func fileState(packageID: UUID) throws -> SharedMediaNativePairFileState { try filesMutation(packageID).state() }
    func prepareFiles(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws -> SharedMediaNativePairFileState {
        let output = try await prepare(original: original, recipe: recipe, savePlan: true), id = original.packageID
        let saved = try filesMutation(id).state()
        var current = try filesMutation(id).reserve(saved, availableBytes: availableBytes(),
            beforeSave: { try self.boundary(.beforeFileReserve) }, afterSave: { try self.boundary(.afterFileReserve) })
        for (input, data) in [(output.intent.ai, output.ai), (output.intent.display, output.display)] {
            try authority.validate(); try Task.checkCancellation()
            let partial = try await io.beginPair(current, workID: input.id)
            try authority.validate()
            current = try filesMutation(id).partial(partial,
                beforeSave: { try self.boundary(.beforeFileIdentity) }, afterSave: { try self.boundary(.afterFileIdentity) })
            let completed = try await io.writePair(data, state: current, workID: input.id)
            try authority.validate()
            current = try filesMutation(id).complete(completed,
                beforeSave: { try self.boundary(.beforeFileCompletion) }, afterSave: { try self.boundary(.afterFileCompletion) })
        }
        return try await publishFiles(current)
    }
    private func publishFiles(_ state: SharedMediaNativePairFileState) async throws -> SharedMediaNativePairFileState {
        let original = try state.intent().preparation.original
        let observed = try await io.inspect(original.file)
        try authority.validate()
        guard observed.identity == original.descriptor else { throw SharedMediaStorageFailure.conflict }
        var proofs: [SharedMediaNativePairCompletion] = []
        for work in state.work {
            guard let proof = try await io.recoverPair(state, workID: work.id) else { throw SharedMediaStorageFailure.conflict }
            proofs.append(proof); try authority.validate()
        }
        if state.phase == "ready" { return state }
        return try filesMutation(state.plan.packageID).publish(state, proofs: proofs,
            beforeSave: { try self.boundary(.beforeFilePublish) }, afterSave: { try self.boundary(.afterFilePublish) })
    }
    /// Saved processing is never dispatched again. Recovery only validates or
    /// finishes the already-saved bytes; incomplete writes require retirement.
    func recoverFiles(packageID: UUID) async throws -> SharedMediaNativePairFileState {
        var state = try filesMutation(packageID).state()
        guard ["writing", "ready"].contains(state.phase) else { throw SharedMediaStorageFailure.closed }
        for work in state.work {
            guard ["writing", "completed"].contains(work.phase) else { return state }
            guard let proof = try await io.recoverPair(state, workID: work.id) else { return state }
            try authority.validate()
            state = try filesMutation(packageID).complete(proof,
                beforeSave: { try self.boundary(.beforeFileCompletion) }, afterSave: { try self.boundary(.afterFileCompletion) })
        }
        return try await publishFiles(state)
    }
    func retireFiles(_ expected: SharedMediaNativePairFileState) async throws {
        let packageID = expected.plan.packageID
        guard try filesMutation(packageID).state() == expected else { throw SharedMediaStorageFailure.stale }
        var state = expected
        if state.phase != "retiring" {
            var proofs: [SharedMediaNativePairInspection] = []
            for work in state.work {
                proofs.append(try await io.inspectPair(state, workID: work.id)); try authority.validate()
            }
            state = try filesMutation(packageID).retire(state, proofs: proofs,
                beforeSave: { try self.boundary(.beforeFileRetire) }, afterSave: { try self.boundary(.afterFileRetire) })
        }
        let disposal = try filesMutation(packageID).disposal(state)
        var absence: [SharedMediaNativePairAbsence] = []
        for work in state.work {
            absence.append(try await io.releasePair(disposal, workID: work.id)); try authority.validate()
        }
        try filesMutation(packageID).release(absence,
            beforeSave: { try self.boundary(.beforeFileRelease) }, afterSave: { try self.boundary(.afterFileRelease) })
    }
    #if DEBUG
    func setPairFileFault(_ fault: (@Sendable (SharedMediaInboxHandoffBoundary) throws -> Void)?) async {
        await io.setPairFault(fault)
    }
    #endif

    private func pairMutation(_ packageID: UUID) throws -> SharedMediaNativePairPlanMutation {
        try boundary(.beforeReadback)
        return try .init(container: container, inventoryID: inventoryID, packageID: packageID, authority: authority)
    }
    func plan(packageID: UUID) throws -> SharedMediaNativePairPlan? { try pairMutation(packageID).saved() }
    func abandonPlan(_ plan: SharedMediaNativePairPlan) throws {
        try pairMutation(plan.packageID).abandon(plan,
            beforeSave: { try self.boundary(.beforePairSave) }, afterSave: { try self.boundary(.afterPairSave) })
    }
    func abandon(_ request: SharedMediaNativePreparationAttempt) throws {
        // This operation runs only after the registered owner's previous task
        // terminated. A reserved attempt currently dispatches no external work.
        do {
            try mutation(request.original.reference.packageID).abandon(request,
                beforeSave: { try self.boundary(.beforeSave) }, afterSave: { try self.boundary(.afterSave) })
        } catch {
            let failure = error
            do { try mutation(request.original.reference.packageID).abandonedResult(request) } catch { throw failure }
        }
        try mutation(request.original.reference.packageID).abandonedResult(request)
    }
}
