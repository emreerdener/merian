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
    func prepare(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws -> SharedMediaNativePreparedOutputs {
        let attempt = try reserve(original: original, recipe: recipe)
        try authority.validate(); try Task.checkCancellation()
        try mutation(original.packageID).result(attempt)
        let output = try await io.preparePhoto(attempt, focusFactory: focusFactory)
        try authority.validate(); try Task.checkCancellation()
        try mutation(original.packageID).result(attempt)
        try output.intent.preparation.requireMatch(attempt)
        return output
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
