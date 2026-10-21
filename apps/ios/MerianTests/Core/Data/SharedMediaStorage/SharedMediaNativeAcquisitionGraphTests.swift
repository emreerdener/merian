import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native acquisition graph and metadata", .serialized)
@MainActor
struct SharedMediaNativeAcquisitionGraphTests {
    @Test(arguments: [false, true]) func reservedAndHeldJoinEveryImmutableFact(_ held: Bool) throws {
        let h = try Harness(); try h.reserve(held: held); try h.save()
        try h.audit()
        let budget = try SharedMediaNativeAcquisitionBudget.evaluate(context: h.context, inventory: h.inventory)
        #expect(budget.metadataByPackage[h.request.packageID]! > Int64(SharedMediaAcquisitionResult.reservedEncodingBytes))
        #expect(!h.context.hasChanges)
    }

    @Test(arguments: ["epoch", "workOwner", "maximum", "partial", "source", "proof", "workID", "leaseID", "leasePurpose", "state", "generation", "inventory", "packagePhase", "packageBytes", "receiptMissing", "membershipMissing"])
    func corruptPendingGraphIsNotRepaired(_ kind: String) throws {
        let h = try Harness(); try h.reserve(); try h.save()
        let work = try #require(h.context.fetch(FetchDescriptor<PhotoPreparationLease>()).first)
        let lease = try #require(h.context.fetch(FetchDescriptor<SharedMediaLeaseRecord>()).first)
        let allocation = try #require(h.context.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first)
        let receipt = try #require(h.context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first)
        switch kind {
        case "epoch": work.processEpoch = UUID()
        case "workOwner": work.ownerID = UUID()
        case "maximum": allocation.reservedBytes += 1
        case "partial": work.partialFileToken += ".partial"
        case "source": work.sourceIdentity = "unexpected"
        case "proof": work.terminalProof = "unexpected"
        case "workID": work.id = UUID()
        case "leaseID": lease.id = UUID()
        case "leasePurpose": lease.purposeRaw = "other"
        case "state": lease.stateRaw = "closed"
        case "generation": h.package.draftGeneration = UUID()
        case "inventory": allocation.inventoryID = UUID()
        case "packagePhase": h.package.phaseRaw = "draftOwned"
        case "packageBytes": h.package.allocatedByteCount = 1
        case "receiptMissing": h.context.delete(receipt)
        default: break
        }
        try h.context.save()
        if kind == "membershipMissing" {
            for row in try h.context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()) { h.context.delete(row) }
            try h.context.save()
        }
        #expect(throws: (any Error).self) { try h.audit() }
        #expect(!h.context.hasChanges)
    }

    @Test(arguments: ["allocation", "asset", "counter", "work", "lease", "reference", "edge", "package", "duplicateReceipt"])
    func reverseAuditFindsOrphans(_ kind: String) throws {
        let h = try Harness(); try h.complete(); try h.save()
        try h.audit()
        let id = UUID(), r = h.request
        switch kind {
        case "allocation": h.context.insert(SharedMediaAllocationRecord(id: id, inventoryID: r.inventoryID,
            accountID: r.ownerID, packageID: r.packageID, namespaceRaw: SharedMediaPhotoLedger.namespace,
            fileToken: "orphan", poolRaw: "durable", stateRaw: "p1Reserved", materializedBytes: 0, reservedBytes: 1, physicalIdentity: nil))
        case "asset": h.context.insert(PhotoPreparationAsset(id: id, ownerID: r.ownerID, generation: UUID(),
            fileToken: "orphan", contentType: "public.jpeg", byteCount: 1, sha256: String(repeating: "a", count: 64), acquisitionKindRaw: "picker", cleanupStateRaw: "ready"))
        case "counter": h.context.insert(SharedMediaAssetReferenceCountRecord(assetID: id, assetGeneration: UUID(),
            inventoryID: r.inventoryID, inventoryGeneration: r.inventoryGeneration, ownerID: r.ownerID, liveCount: 1))
        case "work": h.context.insert(PhotoPreparationLease(id: id, packageID: r.packageID, assetID: id,
            ownerID: r.ownerID, processEpoch: UUID(), purposeRaw: "acquire", partialFileToken: "orphan.partial",
            finalFileToken: "orphan", reservedByteCount: 1, allocatedByteCount: 0, writerStateRaw: "open", terminalProof: nil))
        case "lease": h.context.insert(SharedMediaLeaseRecord(id: id, allocationID: id, processEpoch: UUID(), purposeRaw: "p1AcquireV1", stateRaw: "closed"))
        case "reference": h.context.insert(PhotoPreparationReference(id: id, packageID: r.packageID, assetID: id,
            ownerID: r.ownerID, roleRaw: "original", ordinal: 1, revision: 0, isLive: true))
        case "edge": h.context.insert(SharedMediaReferenceRecord(id: id, allocationID: id, accountID: r.ownerID,
            ownerID: id.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
        case "package": h.context.insert(try h.newPackage(id: id))
        default:
            let duplicate = try h.row(); duplicate.id = id; h.context.insert(duplicate)
        }
        try h.context.save()
        #expect(throws: (any Error).self) { try h.audit() }
        #expect(!h.context.hasChanges)
    }

    @Test func completedHistoricalReceiptSurvivesSharingAndOriginDeletion() throws {
        let h = try Harness(); try h.complete(); try h.save(); try h.audit()
        let row = try #require(h.context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first)
        let bytes = row.resultData
        let destination = try h.newPackage(id: UUID()); destination.accountingTierRaw = "retained"
        destination.allocatedByteCount = 17; h.context.insert(destination)
        let ref = try #require(h.context.fetch(FetchDescriptor<PhotoPreparationReference>()).first)
        let sharedID = UUID(), edge = try #require(h.context.fetch(FetchDescriptor<SharedMediaReferenceRecord>()).first)
        h.context.delete(ref); h.context.delete(edge)
        h.context.insert(PhotoPreparationReference(id: sharedID, packageID: destination.id, assetID: h.request.assetID,
            ownerID: h.request.ownerID, roleRaw: "original", ordinal: 0, revision: 0, isLive: true))
        h.context.insert(SharedMediaReferenceRecord(id: sharedID, allocationID: h.request.assetID,
            accountID: h.request.ownerID, ownerID: sharedID.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace,
            stateRaw: "live", revision: 0))
        h.context.delete(h.package)
        for member in try h.context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()) { h.context.delete(member) }
        h.inventory.revision += 5; try h.context.save()
        try h.audit()
        #expect(row.resultData == bytes)
        #expect(try SharedMediaNativeAcquisitionBudget.evaluate(context: h.context, inventory: h.inventory).metadataByPackage.isEmpty)
        #expect(!h.context.hasChanges)
    }

    @Test(arguments: ["descriptor", "type", "kind", "generation", "epoch", "bytes", "digest", "futureResult", "originalOrdinal", "originalPackage", "originGeneration", "originRevision", "membershipRevision"])
    func completionMustMatchCurrentPhysicalGraph(_ kind: String) throws {
        let h = try Harness(); try h.complete(); try h.save()
        let asset = try #require(h.context.fetch(FetchDescriptor<PhotoPreparationAsset>()).first)
        let allocation = try #require(h.context.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first)
        let lease = try #require(h.context.fetch(FetchDescriptor<SharedMediaLeaseRecord>()).first)
        switch kind {
        case "descriptor": allocation.physicalIdentity = "1:9:17:0:0:0:0"
        case "type": asset.contentType = "public.png"
        case "kind": asset.acquisitionKindRaw = "camera"
        case "generation": asset.generation = UUID()
        case "epoch": lease.processEpoch = UUID()
        case "bytes": asset.byteCount = 18; allocation.materializedBytes = 18
        case "originalOrdinal": try #require(h.context.fetch(FetchDescriptor<PhotoPreparationReference>()).first).ordinal = 1
        case "originalPackage":
            let destination = try h.newPackage(id: UUID()); destination.accountingTierRaw = "retained"; destination.allocatedByteCount = 17
            h.context.insert(destination)
            try #require(h.context.fetch(FetchDescriptor<PhotoPreparationReference>()).first).packageID = destination.id
        case "originGeneration": h.package.draftGeneration = UUID()
        case "originRevision": h.package.revision = 0
        case "membershipRevision": try #require(h.context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first).revision = 0
        case "digest": asset.sha256 = String(repeating: "b", count: 64)
        default: h.inventory.revision = 1
        }
        try h.context.save()
        #expect(throws: (any Error).self) { try h.audit() }
    }

    @Test func terminalReceiptCannotHideRemainingGraph() throws {
        let h = try Harness(); try h.complete(); try h.save()
        let row = try #require(h.context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first)
        row.phaseRaw = "terminal"; row.revision = 2; row.requestData = nil; row.resultData = nil
        row.packageID = nil; row.assetID = nil; row.terminalOutcomeRaw = "released"
        try h.context.save()
        #expect(throws: (any Error).self) { try h.audit() }
    }

    @Test func projectedMembershipIncludesMixedCompletionAndCombinedBudgetRejectsOverflow() throws {
        let h = try Harness(); try h.reserve()
        let r = h.request
        let second = SharedMediaAcquisitionIntent(operationID: UUID(), inventoryID: r.inventoryID,
            inventoryGeneration: r.inventoryGeneration, ownerID: r.ownerID, expectedInventoryRevision: 1,
            packageID: r.packageID, draftGeneration: r.draftGeneration, packageExpectation: .revision(0),
            assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), ordinal: 1, kind: .camera,
            writerEpoch: UUID(), maximumBytes: 32)
        try h.reserve(second); h.inventory.revision = 2; h.package.revision = 1; try h.save()
        try h.audit()
        let member = try SharedMediaPendingGraph.derive(in: h.context, inventory: h.inventory).membership(packageID: r.packageID)
        let projection = try SharedMediaNativeAcquisitionBudget.maximumMembershipBytes(member, pending: [r, second])
        #expect(projection > Int64(try member.encoded().count))
        let budget = try SharedMediaNativeAcquisitionBudget.evaluate(context: h.context, inventory: h.inventory)
        let expected = try PhotoPreparationPolicy.add([Int64(h.package.supportingContextData.count), projection,
            SharedMediaAcquisitionReceipt.metadataCharge(request: r, result: nil),
            SharedMediaAcquisitionReceipt.metadataCharge(request: second, result: nil)])
        #expect(budget.metadataByPackage[r.packageID] == expected)
        // Historical V1 permits JSON whitespace. Keep the envelope valid while
        // making its exact retained bytes consume the full metadata allowance.
        // The aggregate must still reserve membership and receipt space.
        h.package.supportingContextData.append(Data(repeating: 0x20,
            count: Int(PhotoPreparationPolicy.metadata) - h.package.supportingContextData.count))
        #expect(try PhotoPreparationPolicy.decodeDraft(h.package.supportingContextData).version == 1)
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try SharedMediaNativeAcquisitionBudget.evaluate(context: h.context, inventory: h.inventory)
        }
    }

    @Test(arguments: [false, true]) func exactGraphSurvivesDiskReopen(_ completed: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-graph-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("ledger.store")
        let id: UUID
        do {
            let h = try Harness(url: url)
            if completed { try h.complete() } else { try h.reserve(held: true) }
            try h.save(); try h.audit(); id = h.inventory.id
        }
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(container); context.autosaveEnabled = false
        try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: id)
        #expect(!context.hasChanges)
    }

    @Test func receiptPagingReachesCorruptionBeyondFirstPage() throws {
        let h = try Harness(); try h.complete(); try h.save()
        for _ in 0..<130 {
            let r = h.request
            let request = SharedMediaAcquisitionIntent(operationID: UUID(), inventoryID: r.inventoryID,
                inventoryGeneration: r.inventoryGeneration, ownerID: r.ownerID, expectedInventoryRevision: 0,
                packageID: UUID(), draftGeneration: UUID(), packageExpectation: .absent,
                assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), ordinal: 0,
                kind: .picker, writerEpoch: UUID(), maximumBytes: 32)
            let row = try h.row(request)
            row.phaseRaw = "terminal"; row.revision = 2; row.terminalOutcomeRaw = "released"
            row.requestData = nil; row.resultData = nil; row.packageID = nil; row.assetID = nil
            h.context.insert(row)
        }
        try h.context.save(); try h.audit()
        // UUID sort uses this same Foundation ordering in the paged fetch.
        let ordered = try h.context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(sortBy: [SortDescriptor(\.id)]))
        let last = try #require(ordered.last)
        last.schemaVersion = 2; try h.context.save()
        #expect(throws: (any Error).self) { try h.audit() }
    }

    @Test(arguments: ["mode", "phase", "cursor"]) func nonNativeInventoryCannotQualify(_ change: String) throws {
        let h = try Harness(); try h.complete(); try h.save()
        switch change {
        case "mode": h.inventory.modeRaw = "p1Qualification"
        case "phase": h.inventory.phaseRaw = "purging"
        default: h.inventory.cursor = UUID().uuidString.lowercased()
        }
        try h.context.save()
        #expect(throws: SharedMediaStorageFailure.conflict) { try h.audit() }
        let row = try #require(h.context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first)
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try SharedMediaNativeAcquisitionGraph.receipt(row, inventory: h.inventory, context: h.context)
        }
    }

    @Test func dirtyContextCannotProduceSavedAudit() throws {
        let h = try Harness(); try h.reserve()
        #expect(throws: SharedMediaStorageFailure.conflict) { try h.audit() }
        try h.save(); try h.audit()
    }

    @Test(arguments: ["deleted-1", "deleted-2", "retained-1", "retained-2", "pending-1", "pending-2", "retainedOnly"])
    func sharedReceiptChargesPhysicalPendingStorageExactlyOnce(_ scenario: String) throws {
        let retainedOnly = scenario == "retainedOnly"
        let origin = retainedOnly ? "deleted" : String(scenario.split(separator: "-")[0])
        let destinations = scenario.hasSuffix("2") ? 2 : 1
        let h = try sharedFixture(origin: origin, destinations: destinations, retainedOnly: retainedOnly)
        try h.audit()
        let receipt = try #require(h.context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first)
        guard case .completed(let request, let result) = try SharedMediaAcquisitionReceipt.read(receipt) else {
            Issue.record("Expected retained completed acquisition"); return
        }
        let bytes = try SharedMediaAcquisitionReceipt.metadataCharge(request: request, result: result)
        let before = receipt.resultData
        let budget = try SharedMediaNativeAcquisitionBudget.evaluate(context: h.context, inventory: h.inventory)
        let packages = try h.context.fetch(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.accountingTierRaw == "pending" }))
        #expect(packages.count == (retainedOnly ? 0 : destinations + (origin == "pending" ? 1 : 0)))
        for package in packages {
            let id = package.id
            let member = try #require(h.context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })).first)
            let ownBytes = Int64(package.supportingContextData.count + member.membersData.count)
            #expect(budget.metadataByPackage[id] == ownBytes + (id == request.packageID ? bytes : 0))
        }
        let metadata = try PhotoPreparationPolicy.add(Array(budget.metadataByPackage.values))
        let occupied = retainedOnly ? 0 : try PhotoPreparationPolicy.add([17, metadata, origin == "pending" ? 0 : bytes])
        // Probe the existing durable cap directly; checkAvailable alone sees
        // reservations, not this materialized-byte accounting correction.
        var exact = budget.totals
        try exact.includePhotoPhysical(materialized: PhotoPreparationPolicy.durable - occupied, reserved: 0)
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try exact.includePhotoPhysical(materialized: 1, reserved: 0)
        }
        #expect(receipt.resultData == before && !h.context.hasChanges)
    }

    @Test(arguments: ["duplicate", "missing", "phase", "asset", "origin", "inventory", "generation", "owner"])
    func externalReceiptCorruptionDoesNotBecomeFreeCapacity(_ fault: String) throws {
        let h = try sharedFixture(origin: "deleted", destinations: 1)
        try h.audit()
        let row = try #require(h.context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first)
        switch fault {
        case "duplicate":
            let other = try h.row(); other.id = UUID(); other.phaseRaw = row.phaseRaw
            other.revision = row.revision; other.resultData = row.resultData; h.context.insert(other)
        case "missing": h.context.delete(row)
        case "phase": row.phaseRaw = "held"; row.resultData = nil
        case "asset": row.assetID = UUID()
        case "origin": row.packageID = UUID()
        case "inventory": row.inventoryID = UUID()
        case "generation": row.inventoryGeneration = UUID()
        default: row.ownerID = UUID()
        }
        try h.context.save()
        #expect(throws: (any Error).self) { try h.audit() }
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: h.context, inventory: h.inventory)
        }
        #expect(!h.context.hasChanges)
    }

    private func sharedFixture(origin: String, destinations: Int, retainedOnly: Bool = false) throws -> Harness {
        let h = try Harness(); try h.complete(); try h.save()
        let r = h.request
        for _ in 0..<destinations {
            let package = try h.newPackage(id: UUID()), referenceID = UUID()
            package.accountingTierRaw = retainedOnly ? "retained" : "pending"
            package.allocatedByteCount = 17; h.context.insert(package)
            h.context.insert(PhotoPreparationReference(id: referenceID, packageID: package.id, assetID: r.assetID,
                ownerID: r.ownerID, roleRaw: "original", ordinal: 0, revision: 0, isLive: true))
            h.context.insert(SharedMediaReferenceRecord(id: referenceID, allocationID: r.assetID, accountID: r.ownerID,
                ownerID: referenceID.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
        }
        if origin != "pending" {
            let id = r.packageID
            for member in try h.context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })) {
                h.context.delete(member)
            }
            if origin == "retained" { h.package.accountingTierRaw = "retained" }
            else {
                let id = r.referenceID
                h.context.delete(try #require(h.context.fetch(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id })).first))
                h.context.delete(try #require(h.context.fetch(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id })).first))
                h.context.delete(h.package)
            }
        }
        let count = try #require(h.context.fetch(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()).first)
        count.liveCount = Int64(destinations + (origin == "deleted" ? 0 : 1)); count.revision += 1
        h.inventory.revision += 5; try h.save()
        return h
    }

    @MainActor private struct Harness {
        let container: ModelContainer, context: ModelContext
        let inventory: SharedMediaInventoryRecord
        let request: SharedMediaAcquisitionIntent
        let package: PhotoPreparationRecord
        init(url: URL? = nil) throws {
            let schema = Schema(versionedSchema: CurrentSchema.self)
            let configuration = url.map { ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none) }
                ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try ModelContainer(for: schema, configurations: [configuration])
            context = ModelContext(container); context.autosaveEnabled = false
            inventory = .init(id: UUID(), rootIdentity: "synthetic", storeIdentity: "synthetic", generation: UUID(),
                revision: 1, modeRaw: "nativeQualificationV1", phaseRaw: "readyNativeAccountingV1", cursor: "")
            request = .init(operationID: UUID(), inventoryID: inventory.id, inventoryGeneration: inventory.generation,
                ownerID: UUID(), expectedInventoryRevision: 0, packageID: UUID(), draftGeneration: UUID(),
                packageExpectation: .absent, assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(),
                ordinal: 0, kind: .picker, writerEpoch: UUID(), maximumBytes: 32)
            package = .init(id: request.packageID, ownerID: request.ownerID, contractVersion: PhotoPreparationPolicy.contract,
                draftID: request.packageID, draftGeneration: request.draftGeneration, revision: 0, phaseRaw: "acquiring",
                supportingContextData: try PhotoPreparationPolicy.encodeDraft(contexts: []), allocatedByteCount: 0, retirementRequested: false)
            context.insert(inventory); context.insert(package)
            context.insert(SharedMediaMembershipBootstrapRecord(inventoryID: inventory.id, inventoryGeneration: inventory.generation))
        }
        func row(_ value: SharedMediaAcquisitionIntent? = nil) throws -> SharedMediaAcquisitionReceiptRecord {
            let r = value ?? request
            return try .init(operationID: r.operationID, inventoryID: r.inventoryID, inventoryGeneration: r.inventoryGeneration,
                ownerID: r.ownerID, requestFingerprint: r.fingerprint(), packageID: r.packageID, assetID: r.assetID, requestData: r.encoded())
        }
        func reserve(_ value: SharedMediaAcquisitionIntent? = nil, held: Bool = false) throws {
            let r = value ?? request, receipt = try row(r)
            if held { receipt.phaseRaw = "held"; receipt.revision = 1; package.revision = 1; package.phaseRaw = "needsAttention"; inventory.revision = 2 }
            context.insert(receipt)
            context.insert(SharedMediaAllocationRecord(id: r.assetID, inventoryID: r.inventoryID, accountID: r.ownerID,
                packageID: r.packageID, namespaceRaw: SharedMediaPhotoLedger.namespace, fileToken: r.finalToken,
                poolRaw: "durable", stateRaw: held ? "p1Held" : "p1Reserved", materializedBytes: 0, reservedBytes: r.maximumBytes, physicalIdentity: nil))
            context.insert(SharedMediaLeaseRecord(id: r.operationID, allocationID: r.assetID, processEpoch: r.writerEpoch,
                purposeRaw: "p1AcquireV1", stateRaw: held ? "unknown" : "open"))
            context.insert(PhotoPreparationLease(id: r.operationID, packageID: r.packageID, assetID: r.assetID, ownerID: r.ownerID,
                processEpoch: r.writerEpoch, purposeRaw: "acquire", partialFileToken: r.partialToken, finalFileToken: r.finalToken,
                reservedByteCount: r.maximumBytes, allocatedByteCount: 0, writerStateRaw: held ? "unknown" : "open", terminalProof: nil))
        }
        func complete() throws {
            let r = request, receipt = try row()
            let result = try SharedMediaAcquisitionResult(request: r, inventoryRevision: 2, packageRevision: 1, membershipRevision: 1,
                byteCount: 17, sha256: String(repeating: "a", count: 64), contentType: "public.jpeg",
                descriptor: .init(version: 1, file: "1:2:17:0:0:0:0", parent: "1:3", namespace: "1:4"))
            receipt.phaseRaw = "completed"; receipt.revision = 1; receipt.resultData = try result.encoded(request: r); context.insert(receipt)
            package.phaseRaw = "draftOwned"; package.revision = 1; package.allocatedByteCount = 17; inventory.revision = 2
            context.insert(PhotoPreparationAsset(id: r.assetID, ownerID: r.ownerID, generation: r.assetGeneration, fileToken: r.finalToken,
                contentType: result.contentType, byteCount: 17, sha256: result.sha256, acquisitionKindRaw: r.kind.rawValue, cleanupStateRaw: "ready"))
            context.insert(SharedMediaAllocationRecord(id: r.assetID, inventoryID: r.inventoryID, accountID: r.ownerID, packageID: r.packageID,
                namespaceRaw: SharedMediaPhotoLedger.namespace, fileToken: r.finalToken, poolRaw: "durable", stateRaw: "p1Materialized",
                materializedBytes: 17, reservedBytes: 0, physicalIdentity: result.descriptor.file))
            context.insert(SharedMediaLeaseRecord(id: r.operationID, allocationID: r.assetID, processEpoch: r.writerEpoch, purposeRaw: "p1AcquireV1", stateRaw: "closed"))
            context.insert(SharedMediaAssetReferenceCountRecord(assetID: r.assetID, assetGeneration: r.assetGeneration,
                inventoryID: r.inventoryID, inventoryGeneration: r.inventoryGeneration, ownerID: r.ownerID, liveCount: 1))
            context.insert(PhotoPreparationReference(id: r.referenceID, packageID: r.packageID, assetID: r.assetID, ownerID: r.ownerID,
                roleRaw: "original", ordinal: 0, revision: 0, isLive: true))
            context.insert(SharedMediaReferenceRecord(id: r.referenceID, allocationID: r.assetID, accountID: r.ownerID,
                ownerID: r.referenceID.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
        }
        func newPackage(id: UUID) throws -> PhotoPreparationRecord {
            try .init(id: id, ownerID: request.ownerID, contractVersion: PhotoPreparationPolicy.contract, draftID: id,
                draftGeneration: UUID(), revision: 0, phaseRaw: "draftOwned", supportingContextData: PhotoPreparationPolicy.encodeDraft(contexts: []),
                allocatedByteCount: 0, retirementRequested: false)
        }
        func save() throws {
            let graph = try SharedMediaPendingGraph.derive(in: context, inventory: inventory)
            for row in graph.packages {
                let id = row.id
                let old = try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })).first
                let bytes = try graph.membership(packageID: id).encoded()
                if let old { old.membersData = bytes }
                else {
                    let member = SharedMediaPendingMembershipRecord(packageID: id, inventoryID: inventory.id,
                        inventoryGeneration: inventory.generation, ownerID: row.ownerID, draftGeneration: row.draftGeneration, membersData: bytes)
                    member.revision = row.phaseRaw == "draftOwned" ? 1 : 0
                    context.insert(member)
                }
            }
            try context.save()
        }
        func audit() throws { try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventory.id) }
    }
}
