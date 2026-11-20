import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native original reference accounting", .serialized)
@MainActor
struct SharedMediaNativeOriginalAccountingTests {
    @Test func includesRetainedReferencesAcrossMultiplePagesAndMissingOriginPackage() throws {
        let h = try Harness()
        for index in 0..<260 { _ = try h.reference(tier: index < 4 ? "pending" : "retained") }
        try h.context.save()
        let snapshot = try h.audit()
        #expect(snapshot.liveCount == 260 && snapshot.retirement == nil)
        #expect(try h.context.fetchCount(FetchDescriptor<PhotoPreparationRecord>()) == 260)
        #expect(!h.context.hasChanges)
        // No source hold belongs to this original. Unknown edge roles must not
        // disappear from the reverse-direction audit, even when not live.
        h.context.insert(SharedMediaReferenceRecord(id: UUID(), allocationID: h.asset.id,
            accountID: nil, ownerID: "synthetic", roleRaw: "sourceHold", stateRaw: "held", revision: 0))
        try h.context.save()
        #expect(throws: SharedMediaStorageFailure.conflict) { try h.audit() }
    }

    @Test func equalLiveCountsDoNotHideSwappedOrOrphanEdges() throws {
        let h = try Harness(), ref = try h.reference()
        try h.context.save()
        let edge = try #require(h.context.fetch(FetchDescriptor<SharedMediaReferenceRecord>()).first)
        h.context.delete(edge)
        h.context.insert(SharedMediaReferenceRecord(id: UUID(), allocationID: h.asset.id,
            accountID: h.owner, ownerID: ref.id.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace,
            stateRaw: "live", revision: 0))
        try h.context.save()
        #expect(try h.context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>()) == 1)
        #expect(throws: SharedMediaStorageFailure.conflict) { try h.audit() }
    }

    @Test(arguments: ["missingCounter", "count", "counterOwner", "counterGeneration", "inventoryGeneration",
        "allocationOwner", "allocationInventory", "leaseUnknown", "extraLease", "wrongRole", "edgeOwner",
        "edgeRevision", "packageOwner", "unknownTier", "missingPackage", "liveWithRetirement", "zeroReady"])
    func corruptionBlocksWithoutRepair(_ kind: String) throws {
        let h = try Harness(), ref = try h.reference()
        let edge = try #require(h.context.fetch(FetchDescriptor<SharedMediaReferenceRecord>()).first)
        let package = try #require(h.context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first)
        switch kind {
        case "missingCounter": h.context.delete(h.counter)
        case "count": h.counter.liveCount = 2
        case "counterOwner": h.counter.ownerID = UUID()
        case "counterGeneration": h.counter.assetGeneration = UUID()
        case "inventoryGeneration": h.counter.inventoryGeneration = UUID()
        case "allocationOwner": h.allocation.accountID = UUID()
        case "allocationInventory": h.allocation.inventoryID = UUID()
        case "leaseUnknown": h.lease.stateRaw = "unknown"
        case "extraLease": h.context.insert(SharedMediaLeaseRecord(id: UUID(), allocationID: h.asset.id,
            processEpoch: UUID(), purposeRaw: "p1AcquireV1", stateRaw: "closed"))
        case "wrongRole": ref.roleRaw = "aiInput"
        case "edgeOwner": edge.accountID = UUID()
        case "edgeRevision": edge.revision = 9
        case "packageOwner": package.ownerID = UUID()
        case "unknownTier": package.accountingTierRaw = "other"
        case "missingPackage": h.context.delete(package)
        case "liveWithRetirement": h.counter.retirementID = UUID()
        case "zeroReady": h.counter.liveCount = 0
        default: Issue.record("Unknown corruption case")
        }
        try h.context.save()
        #expect(throws: SharedMediaStorageFailure.conflict) { try h.audit() }
        #expect(!h.context.hasChanges)
        if kind == "missingCounter" {
            #expect(try h.context.fetchCount(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()) == 0)
        }
    }

    @Test func rejectsUnsavedProjectionThenAuditsSavedFacts() throws {
        let h = try Harness(); _ = try h.reference()
        #expect(throws: SharedMediaStorageFailure.conflict) { try h.audit() }
        try h.context.save()
        let before = try h.audit()
        h.counter.revision += 1
        #expect(throws: SharedMediaStorageFailure.conflict) { try h.audit() }
        h.context.rollback()
        #expect(try h.audit() == before)
    }

    @Test func nativeRetirementBindsExactZeroCounterAndRejectsV1OrResurrection() throws {
        let h = try Harness(), ref = try h.reference()
        let edge = try #require(h.context.fetch(FetchDescriptor<SharedMediaReferenceRecord>()).first)
        ref.isLive = false; ref.revision = 1; edge.stateRaw = "retired"; edge.revision = 1
        h.counter.liveCount = 0; h.counter.revision = 1; h.counter.retirementID = UUID()
        h.asset.cleanupStateRaw = "retiring"
        h.allocation.stateRaw = SharedMediaNativeRetirementIdentity.allocationState
        let envelope = try SharedMediaNativeRetirementIdentity(retirementID: h.counter.retirementID!,
            assetID: h.asset.id, assetGeneration: h.asset.generation, inventoryID: h.inventory.id,
            inventoryGeneration: h.inventory.generation, ownerID: h.owner,
            proof: .init(version: 1, file: "1:2:17:3:4:5:6", parent: "1:7", namespace: "1:8"))
        h.allocation.physicalIdentity = try envelope.encoded(); try h.context.save()
        let saved = try h.audit()
        #expect(saved.retirement == envelope && saved.liveCount == 0)
        h.counter.revision = 0; try h.context.save()
        #expect(throws: SharedMediaStorageFailure.conflict) { try h.audit() }
        h.counter.revision = 1
        let wrongSize = try SharedMediaNativeRetirementIdentity(retirementID: envelope.retirementID,
            assetID: h.asset.id, assetGeneration: h.asset.generation, inventoryID: h.inventory.id,
            inventoryGeneration: h.inventory.generation, ownerID: h.owner,
            proof: .init(version: 1, file: "1:2:18:3:4:5:6", parent: "1:7", namespace: "1:8"))
        h.allocation.physicalIdentity = try wrongSize.encoded(); try h.context.save()
        #expect(throws: SharedMediaStorageFailure.conflict) { try h.audit() }
        h.allocation.physicalIdentity = try envelope.encoded()
        h.counter.retirementID = UUID(); try h.context.save()
        #expect(throws: SharedMediaStorageFailure.conflict) { try h.audit() }
        h.counter.retirementID = envelope.retirementID
        h.allocation.physicalIdentity = try envelope.proof.encoded(); try h.context.save()
        #expect(throws: (any Error).self) { try h.audit() }
        h.allocation.physicalIdentity = try envelope.encoded()
        ref.isLive = true; edge.stateRaw = "live"; h.counter.liveCount = 1; try h.context.save()
        #expect(throws: SharedMediaStorageFailure.conflict) { try h.audit() }
    }

    @Test func savedAuditSurvivesPersistentContainerReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-count-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("ledger.store")
        let snapshot: SharedMediaNativeOriginalAccounting.Snapshot
        do {
            let h = try Harness(url: url); _ = try h.reference(tier: "retained"); try h.context.save()
            snapshot = try h.audit()
        }
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(reopened); context.autosaveEnabled = false
        #expect(try SharedMediaNativeOriginalAccounting.audit(assetID: snapshot.assetID,
            inventoryID: snapshot.inventoryID, context: context) == snapshot)
    }

    /// Synthetic graph fixtures exercise accounting only, not file authority,
    /// consumer/cohort completeness or a production native store constructor.
    @MainActor private struct Harness {
        let container: ModelContainer, context: ModelContext
        let owner = UUID()
        let inventory: SharedMediaInventoryRecord
        let asset: PhotoPreparationAsset
        let allocation: SharedMediaAllocationRecord
        let counter: SharedMediaAssetReferenceCountRecord
        let lease: SharedMediaLeaseRecord
        init(url: URL? = nil) throws {
            let schema = Schema(versionedSchema: CurrentSchema.self)
            let config = url.map { ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none) }
                ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try ModelContainer(for: schema, configurations: [config])
            context = ModelContext(container); context.autosaveEnabled = false
            inventory = SharedMediaInventoryRecord(id: UUID(), rootIdentity: "synthetic", storeIdentity: "synthetic",
                generation: UUID(), revision: 0, modeRaw: "synthetic", phaseRaw: "synthetic", cursor: "")
            let assetID = UUID(), origin = UUID()
            let token = owner.uuidString.lowercased() + "/" + origin.uuidString.lowercased() + "/" + assetID.uuidString.lowercased()
            asset = PhotoPreparationAsset(id: assetID, ownerID: owner, generation: UUID(), fileToken: token,
                contentType: "image/jpeg", byteCount: 17, sha256: String(repeating: "a", count: 64),
                acquisitionKindRaw: "synthetic", cleanupStateRaw: "ready")
            allocation = SharedMediaAllocationRecord(id: assetID, inventoryID: inventory.id, accountID: owner,
                packageID: origin, namespaceRaw: SharedMediaPhotoLedger.namespace, fileToken: token,
                poolRaw: "durable", stateRaw: "p1Materialized", materializedBytes: 17, reservedBytes: 0,
                physicalIdentity: "1:2:17:3:4:5:6")
            counter = SharedMediaAssetReferenceCountRecord(assetID: assetID, assetGeneration: asset.generation,
                inventoryID: inventory.id, inventoryGeneration: inventory.generation, ownerID: owner, liveCount: 0)
            lease = SharedMediaLeaseRecord(id: UUID(), allocationID: assetID, processEpoch: UUID(),
                purposeRaw: "p1AcquireV1", stateRaw: "closed")
            context.insert(inventory); context.insert(asset); context.insert(allocation); context.insert(counter); context.insert(lease)
        }
        func reference(tier: String = "pending") throws -> PhotoPreparationReference {
            let packageID = UUID(), id = UUID()
            let package = PhotoPreparationRecord(id: packageID, ownerID: owner, contractVersion: PhotoPreparationPolicy.contract,
                draftID: packageID, draftGeneration: UUID(), revision: 0, phaseRaw: "draftOwned",
                supportingContextData: try PhotoPreparationPolicy.encodeDraft(contexts: []), allocatedByteCount: 17, retirementRequested: false)
            package.accountingTierRaw = tier; context.insert(package)
            let ref = PhotoPreparationReference(id: id, packageID: packageID, assetID: asset.id, ownerID: owner,
                roleRaw: "original", ordinal: 0, revision: 0, isLive: true)
            context.insert(ref)
            context.insert(SharedMediaReferenceRecord(id: id, allocationID: asset.id, accountID: owner,
                ownerID: id.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
            counter.liveCount += 1; return ref
        }
        func audit() throws -> SharedMediaNativeOriginalAccounting.Snapshot {
            try SharedMediaNativeOriginalAccounting.audit(assetID: asset.id, inventoryID: inventory.id, context: context)
        }
    }
}
