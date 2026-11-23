import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Whole-store capture artifact accounting", .serialized)
@MainActor
struct CaptureArtifactStoreAuditTests {
    typealias Store = SharedMediaCaptureArtifactLedgerTests.Store

    private func audit(_ store: Store, context: ModelContext? = nil,
                       checkpoint: () throws -> Void = {}) throws -> SharedMediaCaptureArtifactStoreAudit.Snapshot {
        try SharedMediaCaptureArtifactStoreAudit.verify(context: context ?? store.context,
            profile: store.request.profile, rootBindingSHA256: store.request.rootBindingSHA256, checkpoint: checkpoint)
    }

    @Test(arguments: [SharedMediaCaptureArtifactLedger.Phase.reserved, .writing, .ready])
    func accountsForSavedAndReservedBytesWithoutGrantingLegacyAccess(_ phase: SharedMediaCaptureArtifactLedger.Phase) throws {
        let store = try Store(phase: phase), result = try audit(store)
        #expect(result.artifacts == 1)
        let saved = try store.read()
        let identityBytes = Int64((saved.stage?.finalIdentity ?? saved.stage?.partialIdentity)?.utf8.count ?? 0)
        #expect(result.metadataBytes == saved.metadataBytes + identityBytes)
        let stageBytes = Int64(store.row.stageReceiptData.map { $0.count + 64 } ?? 0)
        #expect(result.futureMetadataReservationBytes == (phase == .ready ? 0 : 8_416 - stageBytes - identityBytes) + 2_112)
        #expect(result.materializedBytes == (phase == .ready ? 48 : 0))
        #expect(result.reservedBytes == (phase == .ready ? 0 : 48))
        let fresh = ModelContext(store.container); fresh.autosaveEnabled = false
        #expect(try audit(store, context: fresh) == result)
        #expect(throws: (any Error).self) { try SharedMediaStorageLookup.requireNoUnqualifiedCaptureArtifacts(fresh) }
    }

    @Test(arguments: ["artifact", "allocation", "reference", "lease", "mislabelledReference", "mislabelledLease", "foreignArtifact", "rootBinding"])
    func rejectsUnanchoredOrForeignLiabilities(_ mutation: String) throws {
        let store = try Store(phase: .ready)
        switch mutation {
        case "artifact": store.context.delete(store.row)
        case "allocation": store.context.insert(SharedMediaAllocationRecord(id: UUID(), inventoryID: UUID(), accountID: UUID(),
            packageID: UUID(), namespaceRaw: SharedMediaCaptureRootJournal.namespace, fileToken: UUID().uuidString.lowercased(),
            poolRaw: "durable", stateRaw: "ready", materializedBytes: 48, reservedBytes: 0, physicalIdentity: nil))
        case "reference", "mislabelledReference": store.context.insert(SharedMediaReferenceRecord(id: UUID(),
            allocationID: UUID(), accountID: UUID(), ownerID: UUID().uuidString.lowercased(),
            roleRaw: mutation == "reference" ? SharedMediaCaptureRootJournal.namespace : "other", stateRaw: "held", revision: 0))
        case "lease", "mislabelledLease": store.context.insert(SharedMediaLeaseRecord(id: UUID(), allocationID: UUID(),
            processEpoch: UUID(), purposeRaw: mutation == "lease" ? SharedMediaCaptureArtifactLedger.leasePurpose : "other", stateRaw: "open"))
        case "foreignArtifact": store.row.inventoryID = UUID()
        case "rootBinding":
            #expect(throws: (any Error).self) {
                _ = try SharedMediaCaptureArtifactStoreAudit.verify(context: store.context,
                    profile: store.request.profile, rootBindingSHA256: String(repeating: "f", count: 64))
            }
            return
        default: Issue.record("Unknown mutation")
        }
        try store.context.save()
        #expect(throws: (any Error).self) { _ = try audit(store) }
    }

    @Test(arguments: ["dirtyCurrent", "dirtyMain", "savedRevision", "bootstrapRevision"])
    func aChangingStoreExpiresTheRead(_ mutation: String) throws {
        let store = try Store()
        var checkpoints = 0
        #expect(throws: (any Error).self) {
            _ = try audit(store) {
                checkpoints += 1
                guard checkpoints == 2 else { return }
                switch mutation {
                case "dirtyCurrent": store.inventory.revision += 1
                case "dirtyMain":
                    let rows = try store.container.mainContext.fetch(FetchDescriptor<SharedMediaInventoryRecord>())
                    rows.first?.revision += 1
                case "savedRevision": store.inventory.revision += 1; try store.context.save()
                case "bootstrapRevision":
                    let rows = try store.context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>())
                    rows.first?.revision += 1; try store.context.save()
                default: Issue.record("Unknown mutation")
                }
            }
        }
    }

    @Test(arguments: ["asset", "counter", "receiptAsset", "receiptLease", "leaseAsset", "leaseID", "referenceAsset", "referenceID", "workAsset", "workLease", "workReference"])
    func captureOwnershipCannotAlsoBePhotoOwnership(_ alias: String) throws {
        let store = try Store(), request = store.request
        let asset = request.allocationID, lease = request.leaseID, reference = request.referenceID
        switch alias {
        case "asset": store.context.insert(PhotoPreparationAsset(id: asset, ownerID: request.profile.ownerID,
            generation: UUID(), fileToken: "photo", contentType: "image/jpeg", byteCount: 48,
            sha256: request.sha256, acquisitionKindRaw: "import", cleanupStateRaw: "ready"))
        case "counter": store.context.insert(SharedMediaAssetReferenceCountRecord(assetID: asset,
            assetGeneration: UUID(), inventoryID: request.profile.inventoryID, inventoryGeneration: request.profile.generation,
            ownerID: request.profile.ownerID, liveCount: 1))
        case "receiptAsset", "receiptLease": store.context.insert(SharedMediaAcquisitionReceiptRecord(
            operationID: alias == "receiptLease" ? lease : UUID(), inventoryID: request.profile.inventoryID,
            inventoryGeneration: request.profile.generation, ownerID: request.profile.ownerID,
            requestFingerprint: request.sha256, packageID: UUID(), assetID: alias == "receiptAsset" ? asset : UUID(), requestData: Data()))
        case "leaseAsset", "leaseID": store.context.insert(PhotoPreparationLease(id: alias == "leaseID" ? lease : UUID(),
            packageID: UUID(), assetID: alias == "leaseAsset" ? asset : UUID(), ownerID: request.profile.ownerID,
            processEpoch: UUID(), purposeRaw: "p1AcquireV1", partialFileToken: "photo.partial", finalFileToken: "photo",
            reservedByteCount: 48, allocatedByteCount: 0, writerStateRaw: "reserved", terminalProof: nil))
        case "referenceAsset", "referenceID": store.context.insert(PhotoPreparationReference(
            id: alias == "referenceID" ? reference : UUID(), packageID: UUID(), assetID: alias == "referenceAsset" ? asset : UUID(),
            ownerID: request.profile.ownerID, roleRaw: "original", ordinal: 0, revision: 0, isLive: true))
        case "workAsset", "workLease", "workReference": store.context.insert(SharedMediaDerivativeWorkRecord(id: UUID(),
            pairID: UUID(), roleRaw: "inference", assetID: alias == "workAsset" ? asset : UUID(), assetGeneration: UUID(),
            referenceID: alias == "workReference" ? reference : UUID(), leaseID: alias == "workLease" ? lease : UUID(),
            writerEpoch: UUID(), byteCount: 48, sha256: request.sha256, contentType: "image/jpeg"))
        default: Issue.record("Unknown alias")
        }
        try store.context.save()
        #expect(throws: (any Error).self) { _ = try audit(store) }
    }
}
