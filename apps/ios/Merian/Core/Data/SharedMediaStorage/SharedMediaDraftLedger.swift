import Foundation
import SwiftData

/// Local assertions retained by the caller for exact freeze recovery. These
/// values grant no file, storage, admission or provider authority.
struct SharedMediaFreezeRequest: Sendable {
    let inventoryID: UUID
    let inventoryGeneration: UUID
    let snapshot: PhotoPreparationSnapshot
    let envelope: Data
    let files: [PhotoPreparationFile]
    let identities: [String]
}

struct SharedMediaMetadataRequest: Sendable {
    let packageID: UUID
    let ownerID: UUID
    let revision: Int64
    let previousEnvelope: Data
    let envelope: Data
    var growth: Int64 { max(0, Int64(envelope.count) - Int64(previousEnvelope.count)) }
}

/// Pure held-store operations. The inbox repository performs the single save;
/// the existing destination actor verifies bytes before a freeze is committed.
@MainActor
final class SharedMediaDraftLedger {
    private let joint: SharedMediaPhotoTransaction
    private let inventory: SharedMediaInventoryRecord
    private var context: ModelContext { joint.context }
    init(joint: SharedMediaPhotoTransaction, inventory: SharedMediaInventoryRecord) {
        self.joint = joint; self.inventory = inventory
    }

    func prepareMetadata(packageID: UUID, ownerID: UUID, revision: Int64,
                         contexts: [ObservationContext], presentation: [PhotoPreparationImagePresentation]?) throws -> SharedMediaMetadataRequest {
        let row = try package(packageID, owner: ownerID)
        try mutable(row, revision: revision)
        try readyForMutation(packageID)
        let prior = try PhotoPreparationPolicy.decodeDraft(row.supportingContextData)
        let photos = presentation ?? prior.presentation
        let originals = try references(packageID).filter { $0.isLive && $0.roleRaw == "original" }
        guard photos.allSatisfy({ photo in originals.contains { $0.id == photo.referenceID } }) else { throw PhotoPreparationFailure.staleGeneration }
        return .init(packageID: packageID, ownerID: ownerID, revision: revision,
                     previousEnvelope: row.supportingContextData,
                     envelope: try PhotoPreparationPolicy.encodeDraft(contexts: contexts, presentation: photos))
    }

    func saveMetadata(_ request: SharedMediaMetadataRequest) throws -> Int64 {
        let row = try package(request.packageID, owner: request.ownerID)
        try mutable(row, revision: request.revision)
        try readyForMutation(row.id)
        guard row.supportingContextData == request.previousEnvelope else { throw PhotoPreparationFailure.staleGeneration }
        _ = try PhotoPreparationPolicy.decodeDraft(request.envelope)
        row.supportingContextData = request.envelope
        row.revision = try SharedMediaStoragePolicy.add(row.revision, 1)
        return row.revision
    }

    func metadataResult(_ request: SharedMediaMetadataRequest) throws -> Int64 {
        let row = try package(request.packageID, owner: request.ownerID)
        guard row.phaseRaw == "draftOwned", row.revision == (try SharedMediaStoragePolicy.add(request.revision, 1)),
              row.supportingContextData == request.envelope else { throw PhotoPreparationFailure.staleGeneration }
        try readyForMutation(row.id)
        return row.revision
    }

    func prepareFreeze(_ snapshot: PhotoPreparationSnapshot, ownerID: UUID) throws -> SharedMediaFreezeRequest {
        guard let first = snapshot.originals.first else { throw PhotoPreparationFailure.invalidMedia }
        let row = try package(first.packageID, owner: ownerID)
        try mutable(row, revision: snapshot.expectedPackageRevision)
        let files = try freezeFiles(snapshot, ownerID: ownerID)
        return .init(inventoryID: inventory.id, inventoryGeneration: inventory.generation,
                     snapshot: snapshot, envelope: row.supportingContextData, files: files.0, identities: files.1)
    }

    func requireFreeze(_ request: SharedMediaFreezeRequest, ownerID: UUID, recovered: Bool) throws -> PhotoPreparationReceipt {
        guard request.inventoryID == inventory.id, request.inventoryGeneration == inventory.generation,
              let first = request.snapshot.originals.first else { throw PhotoPreparationFailure.staleGeneration }
        let row = try package(first.packageID, owner: ownerID)
        let next = try SharedMediaStoragePolicy.add(request.snapshot.expectedPackageRevision, 1)
        guard !row.retirementRequested, row.phaseRaw == (recovered ? "preparedHeld" : "draftOwned"),
              row.revision == (recovered ? next : request.snapshot.expectedPackageRevision),
              row.supportingContextData == request.envelope else { throw PhotoPreparationFailure.staleGeneration }
        let files = try freezeFiles(request.snapshot, ownerID: ownerID)
        guard files.0 == request.files, files.1 == request.identities else { throw PhotoPreparationFailure.staleGeneration }
        return .init(packageID: row.id, revision: next)
    }

    func freeze(_ request: SharedMediaFreezeRequest, ownerID: UUID) throws -> PhotoPreparationReceipt {
        let result = try requireFreeze(request, ownerID: ownerID, recovered: false)
        let row = try package(result.packageID, owner: ownerID)
        row.phaseRaw = "preparedHeld"; row.revision = result.revision
        return result
    }

    func catalog(ownerID: UUID) throws -> [PhotoPreparationDraft] {
        let photos = SharedMediaPhotoLedger(joint: joint, inventoryID: inventory.id, includesInbox: true)
        let originals = try photos.inventory().originals
        return try fetch(PhotoPreparationRecord.self, 4).filter { $0.ownerID == ownerID }.map { row in
            let envelope = try PhotoPreparationPolicy.decodeDraft(row.supportingContextData)
            let order = try references(row.id).filter { $0.isLive && $0.roleRaw == "original" }.sorted { $0.ordinal < $1.ordinal }
            let handles = try order.map { edge in
                guard let value = originals.first(where: { $0.referenceID == edge.id }) else { throw PhotoPreparationFailure.inconsistentOwnership }; return value
            }
            return .init(packageID: row.id, draftGeneration: row.draftGeneration, revision: row.revision, phase: row.phaseRaw,
                         originals: handles, contexts: envelope.contexts, needsAttention: row.phaseRaw == "needsAttention",
                         presentation: envelope.presentation, retainedSourceIdentities: [])
        }
    }

    private func freezeFiles(_ snapshot: PhotoPreparationSnapshot, ownerID: UUID) throws -> ([PhotoPreparationFile], [String]) {
        guard let first = snapshot.originals.first, snapshot.originals.count <= 2,
              snapshot.originals.allSatisfy({ $0.ownerID == ownerID && $0.packageID == first.packageID }),
              Set(snapshot.originals.map(\.referenceID)).count == snapshot.originals.count else { throw PhotoPreparationFailure.invalidMedia }
        let row = try package(first.packageID, owner: ownerID)
        try readyForMutation(row.id)
        guard try PhotoPreparationPolicy.decodeDraft(row.supportingContextData).contexts == snapshot.supportingContexts else { throw PhotoPreparationFailure.staleGeneration }
        let photos = SharedMediaPhotoLedger(joint: joint, inventoryID: inventory.id, includesInbox: true)
        for original in snapshot.originals { _ = try photos.resolve(original) }
        let refs = try references(row.id).filter(\.isLive)
        let originals = refs.filter { $0.roleRaw == "original" }.sorted { $0.ordinal < $1.ordinal }
        guard originals.map(\.id) == snapshot.originals.map(\.referenceID) else { throw PhotoPreparationFailure.staleGeneration }
        let pairs = try fetch(SharedMediaDerivativePairRecord.self, 9).filter { $0.packageID == row.id }
        guard pairs.count == originals.count, originals.allSatisfy({ original in pairs.contains { $0.originalReferenceID == original.id && $0.phaseRaw == "ready" } }) else { throw PhotoPreparationFailure.missingMedia }
        var ordered: [PhotoPreparationReference] = []
        for role in ["original", "aiInput", "display"] {
            let edges = refs.filter { $0.roleRaw == role }.sorted { $0.ordinal < $1.ordinal }
            guard edges.map(\.ordinal) == originals.map(\.ordinal) else { throw PhotoPreparationFailure.missingMedia }
            ordered += edges
        }
        let all = try photos.inventory()
        var files: [PhotoPreparationFile] = [], identities: [String] = []
        for edge in ordered {
            guard let file = all.files.first(where: { $0.assetID == edge.assetID }),
                  let identity = all.identities[file.assetID], !all.retiringIDs.contains(file.assetID) else { throw PhotoPreparationFailure.missingMedia }
            files.append(file); identities.append(identity)
        }
        return (files, identities)
    }

    private func mutable(_ row: PhotoPreparationRecord, revision: Int64) throws {
        guard row.phaseRaw == "draftOwned", !row.retirementRequested else { throw PhotoPreparationFailure.immutablePackage }
        guard row.revision == revision else { throw PhotoPreparationFailure.staleGeneration }
    }
    private func readyForMutation(_ packageID: UUID) throws {
        guard try fetch(PhotoPreparationLease.self, 96).allSatisfy({ $0.packageID != packageID }),
              try fetch(SharedMediaInboxHandoffRecord.self, 8).allSatisfy({ $0.packageID != packageID }),
              try fetch(SharedMediaDerivativePairRecord.self, 9).allSatisfy({ $0.packageID != packageID || $0.phaseRaw == "ready" }) else { throw PhotoPreparationFailure.cleanupPending }
    }
    private func references(_ packageID: UUID) throws -> [PhotoPreparationReference] {
        try fetch(PhotoPreparationReference.self, 128).filter { $0.packageID == packageID }
    }
    private func package(_ id: UUID, owner: UUID) throws -> PhotoPreparationRecord {
        guard let row = try fetch(PhotoPreparationRecord.self, 4).first(where: { $0.id == id && $0.ownerID == owner }) else { throw PhotoPreparationFailure.staleGeneration }; return row
    }
    private func fetch<T: PersistentModel>(_ type: T.Type, _ maximum: Int) throws -> [T] {
        var query = FetchDescriptor<T>(); query.fetchLimit = maximum + 1
        let rows = try context.fetch(query)
        guard rows.count <= maximum else { throw SharedMediaStorageFailure.conflict }; return rows
    }
}
