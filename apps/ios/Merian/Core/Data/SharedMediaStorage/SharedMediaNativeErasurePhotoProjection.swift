import Foundation
import SwiftData

/// Descriptive projection of photo rows already covered by the complete
/// initial semantic audit and immutable erasure graph. This does not perform
/// normal ready admission or issue a file mutation capability. The enclosing
/// owner must compare the full raw graph before and after this traversal.
@MainActor
enum SharedMediaNativeErasurePhotoProjection {
    typealias Request = SharedMediaNativeErasurePhotoRead.Request

    static func visit(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                      checkpoint: () throws -> Void, inspect: (Request) throws -> Void) async throws {
        try checkpoint()
        let context = ModelContext(container); context.autosaveEnabled = false
        guard !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let before = try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: checkpoint)
        try await visit(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(sortBy: [SortDescriptor(\.id)]), checkpoint: checkpoint) { row in
            guard row.ownerID == profile.ownerID, row.inventoryID == profile.inventoryID,
                  row.inventoryGeneration == profile.generation else { throw SharedMediaStorageFailure.conflict }
            switch try SharedMediaAcquisitionReceipt.read(row) {
            case .released: break // No source identity remains; never infer a path.
            case .reserved(let request), .held(let request):
                let id = request.assetID
                let work = try one(context, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.assetID == id }))
                let closure = try work.terminalProof.map { try SharedMediaNativePendingClosure.decode($0, request: request) }
                try inspect(closure.map { .pending(request, $0) } ?? .interrupted(request))
            case .completed(let request, let result):
                let id = request.assetID
                let allocation = try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id }))
                let asset = try one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == id }))
                let retiring = allocation.stateRaw == SharedMediaNativeRetirementIdentity.allocationState
                let descriptor: SharedMediaPhotoRetirementIdentity
                if retiring {
                    guard let raw = allocation.physicalIdentity else { throw SharedMediaStorageFailure.conflict }
                    let identity = try SharedMediaNativeRetirementIdentity.decode(raw)
                    guard identity.assetID == id, identity.assetGeneration == request.assetGeneration,
                          identity.ownerID == profile.ownerID, identity.inventoryID == profile.inventoryID,
                          identity.inventoryGeneration == profile.generation else { throw SharedMediaStorageFailure.conflict }
                    descriptor = identity.proof
                } else {
                    guard allocation.stateRaw == "p1Materialized", allocation.physicalIdentity == result.descriptor.file else {
                        throw SharedMediaStorageFailure.conflict
                    }
                    descriptor = result.descriptor
                }
                guard asset.fileToken == request.finalToken, allocation.fileToken == request.finalToken,
                      asset.generation == request.assetGeneration, asset.byteCount == result.byteCount,
                      asset.sha256 == result.sha256, asset.contentType == result.contentType else { throw SharedMediaStorageFailure.conflict }
                try inspect(.original(.init(assetID: id, generation: asset.generation, token: asset.fileToken,
                    byteCount: asset.byteCount, sha256: asset.sha256, contentType: asset.contentType), descriptor, retiring: retiring))
            }
        }
        try await visit(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(sortBy: [SortDescriptor(\.id)]), checkpoint: checkpoint) { work in
            let pairID = work.pairID
            let pair = try one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
            guard pair.ownerID == profile.ownerID, pair.inventoryID == profile.inventoryID,
                  pair.inventoryGeneration == profile.generation, pair.contractVersion == SharedMediaNativePairPlanGraph.contract,
                  work.id == pair.aiWorkID || work.id == pair.displayWorkID else { throw SharedMediaStorageFailure.conflict }
            let assetID = work.assetID, leaseID = work.leaseID
            guard try context.fetchCount(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID })) == 0 else {
                throw SharedMediaStorageFailure.conflict
            }
            var query = FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == leaseID }); query.fetchLimit = 2
            let leases = try context.fetch(query)
            guard leases.count <= 1 else { throw SharedMediaStorageFailure.conflict }
            let value = SharedMediaNativePairFileState.Work(id: work.id, writerEpoch: work.writerEpoch,
                phase: work.phaseRaw, writerState: work.writerStateRaw, device: work.partialDevice, inode: work.partialInode,
                finalIdentity: work.finalIdentity, retirementID: work.retirementID,
                retirementPartial: work.retirementPartialIdentity, retirementFinal: work.retirementFinalIdentity,
                retirementParent: work.retirementParentIdentity, retirementNamespace: work.retirementNamespaceIdentity,
                closure: leases.first?.terminalProof)
            let token = [pair.ownerID, pair.packageID, assetID].map { $0.uuidString.lowercased() }.joined(separator: "/")
            try inspect(.derivative(.init(assetID: assetID, generation: work.assetGeneration, token: token,
                byteCount: work.byteCount, sha256: work.sha256, contentType: work.contentType), value))
        }
        try checkpoint()
        guard try SharedMediaNativeErasureGraph.snapshot(ModelContext(container), checkpoint: checkpoint) == before else {
            throw SharedMediaStorageFailure.stale
        }
    }

    private static func visit<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>,
                                                  checkpoint: () throws -> Void, body: (T) throws -> Void) async throws {
        var query = descriptor, offset = 0
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        while true {
            try checkpoint(); try Task.checkCancellation(); query.fetchOffset = offset
            let rows = try context.fetch(query)
            for row in rows { try checkpoint(); try body(row) }
            if rows.count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
            await Task.yield(); try checkpoint()
        }
    }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let value = rows.first else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}
