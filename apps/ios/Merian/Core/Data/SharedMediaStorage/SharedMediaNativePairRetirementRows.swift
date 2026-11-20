import Foundation
import SwiftData

/// Private implementation leaf shared by the two fenced retirement owners.
/// No identity generation, authority, revisions, accounting, I/O or save occurs here.
/// Callers must supply their own audited predecessor and exact joint write seal.
@MainActor
enum SharedMediaNativePairRetirementRows {
    static func apply(context: ModelContext, package: PhotoPreparationRecord,
                      pair: SharedMediaDerivativePairRecord, before: SharedMediaNativePairFileState,
                      closure: SharedMediaNativePairClosure) throws {
        func one<T: PersistentModel>(_ q: FetchDescriptor<T>) throws -> T {
            try SharedMediaNativePairPlanGraph.one(context, q)
        }
        guard closure.pairID == pair.id, closure.packageID == package.id,
              closure.entries.map(\.work) == before.work,
              closure.beforeHash == SharedMediaNativePairClosure.digest(try SharedMediaNativeDraftEnvelope.bytes(before)) else {
            throw SharedMediaStorageFailure.conflict
        }
        let raw = try closure.encoded(), marker = try closure.siblingMarker()
        guard raw.utf8.count + marker.utf8.count <= (try SharedMediaNativePairClosure.maximumEncodingBytes(before)) else { throw SharedMediaStorageFailure.capacity }
        for entry in closure.entries {
            let (_, input) = try before.selected(entry.work.id), id = entry.work.id
            let work = try one(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id }))
            let assetID = input.assetID, leaseID = input.leaseID
            let token = try before.file(work.id).token
            if before.phase == "ready" {
                context.insert(PhotoPreparationLease(id: leaseID, packageID: package.id, assetID: assetID,
                    ownerID: package.ownerID, processEpoch: work.writerEpoch, purposeRaw: SharedMediaNativePairPlanGraph.contract,
                    partialFileToken: token + ".partial", finalFileToken: token, reservedByteCount: 0,
                    allocatedByteCount: input.byteCount, writerStateRaw: "closedNativePairRetirementV2", terminalProof: nil))
                context.insert(SharedMediaLeaseRecord(id: leaseID, allocationID: assetID, processEpoch: work.writerEpoch,
                    purposeRaw: SharedMediaNativePairPlanGraph.contract, stateRaw: "closed"))
            }
            let lease = try one(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == leaseID }))
            lease.writerStateRaw = "closedNativePairRetirementV2"; lease.terminalProof = work.id == pair.aiWorkID ? raw : marker
            let shared = try one(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID }))
            if shared.stateRaw != "closed" { shared.stateRaw = "closed" }
            try one(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID })).stateRaw = "nativePairRetiringV2"
            work.phaseRaw = "retiring"; work.writerStateRaw = "closed"; work.retirementID = closure.retirementID
            work.retirementPartialIdentity = entry.identity.partial; work.retirementFinalIdentity = entry.identity.final
            work.retirementParentIdentity = entry.identity.parent; work.retirementNamespaceIdentity = entry.identity.namespace
            if work.finalIdentity != nil {
                let referenceID = input.referenceID
                let reference = try one(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID }))
                let edge = try one(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID }))
                let counter = try one(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
                guard counter.liveCount == 1, counter.revision == 0, counter.retirementID == nil else { throw SharedMediaStorageFailure.inUse }
                reference.isLive = false; reference.revision = 1; edge.stateRaw = "retired"; edge.revision = 1
                counter.liveCount = 0; counter.revision = 1; counter.retirementID = closure.retirementID
                try one(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })).cleanupStateRaw = "retiring"
            }
        }
        pair.phaseRaw = "retiring"; pair.publishedRevision = nil
    }
}
