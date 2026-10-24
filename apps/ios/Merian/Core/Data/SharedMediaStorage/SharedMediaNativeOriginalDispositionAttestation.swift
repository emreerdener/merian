import CryptoKit
import Foundation
import SwiftData

/// Versioned transaction attestation, not a physical-original proof. Reference
/// pages are hashed incrementally under the store lock; no unbounded array.
@MainActor
enum SharedMediaNativeOriginalDispositionAttestation {
    typealias Raw = SharedMediaNativeReleasePairRaw
    static func digest(before: SharedMediaNativeReceivingReleaseValues.Progress,
                       next: SharedMediaNativeReceivingReleaseState.Expected,
                       header: SharedMediaNativeAppEligibility.Header, context: ModelContext) throws -> String {
        guard !context.hasChanges, let target = before.plan.targets.first else { throw SharedMediaStorageFailure.conflict }
        var hash = SHA256()
        func append(_ bytes: Data) { hash.update(data: Data("\(bytes.count):".utf8)); hash.update(data: bytes) }
        func row<T: PersistentModel>(_ value: T, _ fields: Raw.Fields) throws {
            append(try Raw.value(value.persistentModelID)); append(try Raw.value(fields))
        }
        append(Data("shared-original-disposition-v1".utf8)); append(try before.encoded())
        append(try Raw.value(header)); append(try Raw.value(SharedMediaNativeAppMetadataFacts.successor(header)))
        append(try Raw.value(next.package)); append(try Raw.value(next.member))
        append(try Raw.value([next.slotRevision, next.minimumInventoryRevision, next.completedSteps]))
        append(Data("delete-selected-reference-and-edge;decrement-count-once;preserve-physical-origin".utf8))
        let r = try SharedMediaNativeAppOriginalRows(context, profile: before.plan.profile, source: target.original)
        try row(r.inventory, Raw.fields(r.inventory)); try row(r.package, Raw.fields(r.package))
        try row(r.member, Raw.fields(r.member)); try row(r.asset, Raw.fields(r.asset))
        try row(r.allocation, Raw.fields(r.allocation)); try row(r.count, Raw.fields(r.count))
        try row(r.lease, Raw.fields(r.lease)); try row(r.receipt, fields(r.receipt))
        guard let slot = try SharedMediaNativeReceivingPhaseGraph.row(before.plan.package.id, in: context) else {
            throw SharedMediaStorageFailure.stale
        }
        try row(slot, Raw.fields(slot))
        append(try Raw.value(referenceDigest(assetID: target.original.assetID, context: context)))
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func referenceDigest(assetID: UUID, excludingID: UUID? = nil, context: ModelContext) throws -> String {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        var hash = SHA256(), offset = 0
        var query = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == assetID }, sortBy: [SortDescriptor(\.id)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        while true {
            try Task.checkCancellation(); query.fetchOffset = offset
            let rows = try context.fetch(query)
            for ref in rows {
                if ref.id == excludingID { continue }
                let id = ref.id
                let edge = try SharedMediaNativePairPlanGraph.one(context,
                    FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id }))
                for bytes in [try Raw.value(ref.persistentModelID), try Raw.value(Raw.fields(ref)),
                              try Raw.value(edge.persistentModelID), try Raw.value(Raw.fields(edge))] {
                    hash.update(data: Data("\(bytes.count):".utf8)); hash.update(data: bytes)
                }
            }
            if rows.count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func fields(_ row: SharedMediaAcquisitionReceiptRecord) throws -> Raw.Fields {
        try ["id": Raw.value(row.id), "schemaVersion": Raw.value(row.schemaVersion),
             "inventoryID": Raw.value(row.inventoryID), "inventoryGeneration": Raw.value(row.inventoryGeneration),
             "ownerID": Raw.value(row.ownerID), "requestFingerprint": Raw.value(row.requestFingerprint),
             "phaseRaw": Raw.value(row.phaseRaw), "terminalOutcomeRaw": Raw.value(row.terminalOutcomeRaw),
             "revision": Raw.value(row.revision), "packageID": Raw.value(row.packageID),
             "assetID": Raw.value(row.assetID), "requestData": Raw.value(row.requestData), "resultData": Raw.value(row.resultData)]
    }
}
