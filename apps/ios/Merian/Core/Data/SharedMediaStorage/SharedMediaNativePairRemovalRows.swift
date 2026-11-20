import Foundation
import SwiftData

/// No-save row mechanics shared by the ordinary and held release writers.
/// Callers own complete predecessor/absence proofs, write seals and persistence.
@MainActor
enum SharedMediaNativePairRemovalRows {
    static func apply(context: ModelContext, package: PhotoPreparationRecord,
                      pair: SharedMediaDerivativePairRecord, before: SharedMediaNativePairFileState) throws {
        guard before.phase == "retiring", package.id == before.plan.packageID,
              pair.id == (try before.intent().pairID), pair.phaseRaw == "retiring" else {
            throw SharedMediaStorageFailure.stale
        }
        for prior in before.work {
            let (_, input) = try before.selected(prior.id)
            let id = input.id, assetID = input.assetID, referenceID = input.referenceID, leaseID = input.leaseID
            let work = try one(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id }))
            if work.finalIdentity != nil {
                context.delete(try one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })))
                context.delete(try one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID })))
                context.delete(try one(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID })))
                context.delete(try one(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID })))
                guard package.allocatedByteCount >= input.byteCount else { throw SharedMediaStorageFailure.conflict }
                package.allocatedByteCount -= input.byteCount
            }
            context.delete(try one(context, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == leaseID })))
            context.delete(try one(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID })))
            context.delete(try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID })))
            context.delete(work)
        }
        context.delete(pair)
    }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(context, query)
    }
}
