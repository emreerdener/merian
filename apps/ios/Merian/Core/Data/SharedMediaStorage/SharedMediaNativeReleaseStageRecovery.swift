import Foundation
import SwiftData

/// Pure saved-outcome matching shared by ordinary recovery and sealed-owner drain.
/// The caller supplies read-only physical/profile/epoch fences and canonical locks.
@MainActor
enum SharedMediaNativeReleaseStageRecovery {
    typealias Saved = SharedMediaNativeAppReleaseStageOperations.Saved
    static func read(_ request: SharedMediaNativeReleaseStartRequest, container: ModelContainer,
                     exactSuccessor: Bool = false,
                     header: () throws -> SharedMediaNativeAppEligibility.Header) throws -> Saved {
        try request.validate()
        let before = try header(), c = ModelContext(container)
        c.autosaveEnabled = false
        let id = request.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(c,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        let successor = try request.postStageHeader
        guard !exactSuccessor || before == successor,
              let witness = try SharedMediaNativeReceivingCleanGraph.pending(c, inventory: inventory)[request.packageID] else {
            throw SharedMediaStorageFailure.closed
        }
        let result: Saved
        switch witness {
        case .staged(let value):
            guard value.origin.request == request, value.origin.row.releaseStartData == (try request.encoded()),
                  value.origin.row.releaseStartSHA256 == SharedMediaAcquisitionEncoding.digest(try request.encoded()) else {
                throw SharedMediaStorageFailure.closed
            }
            result = .staged(value.origin.request)
        case .releasing(let value):
            let release = value.release, plan = release.progress.plan
            try request.requireMatch(prepared: release.origin.prepared, received: release.origin.received)
            let minimum = try request.postStageHeader, actual = plan.preHeader
            guard plan.releaseID == request.releaseID, actual.inventory.generation == minimum.inventory.generation,
                  actual.inventory.revision >= minimum.inventory.revision, actual.inventory.phase == minimum.inventory.phase,
                  actual.inventory.cursor == minimum.inventory.cursor, actual.bootstrapID == minimum.bootstrapID,
                  actual.bootstrapGeneration == minimum.bootstrapGeneration, actual.bootstrapContract == minimum.bootstrapContract,
                  actual.bootstrapRevision == minimum.bootstrapRevision else { throw SharedMediaStorageFailure.closed }
            // Progress retains the immutable association, not historical stagePreHeader bytes.
            result = .releasing(release.progress)
        case .allocating, .generic: throw SharedMediaStorageFailure.closed
        }
        guard try header() == before else { throw SharedMediaStorageFailure.stale }
        return result
    }
}
