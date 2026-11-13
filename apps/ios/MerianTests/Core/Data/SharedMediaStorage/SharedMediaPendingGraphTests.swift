import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Pending media graph discovery", .serialized)
@MainActor
struct SharedMediaPendingGraphTests {
    enum Fault: Error { case injected }

    @Test func discoversSavedMutablePhasesThroughRealHandoffAndReplacement() async throws {
        let h = try Harness(), owner = try h.owner(), data = PhotoPreparationTestHarness.image()
        var phases = Set<String>(), failures: [String] = []
        // Observe committed boundaries only, using another fresh context. The
        // production qualification owner still owns every transition and save.
        owner.setHandoffFault { point in
            guard String(describing: point).hasPrefix("after") else { return }
            do {
                let graph = try h.completeQualificationProjection()
                phases.formUnion(graph.handoffs.map { "handoff:" + $0.phaseRaw })
                phases.formUnion(graph.pairs.map { "pair:" + $0.phaseRaw })
            } catch { failures.append(String(describing: point) + ":" + String(describing: error)) }
        }
        let source = try await owner.stage { data }
        #expect(try h.completeQualificationProjection().sources.count == 1)
        let request = try owner.prepareHandoff(source, account: h.account, packageID: UUID(), draftGeneration: UUID())
        let original = try await owner.handoff(request, account: h.account)
        try await owner.retireHandoffSource(request, account: h.account)
        let first = try await owner.prepareDerivatives(original, ai: data, display: data, account: h.account)
        _ = try await owner.replaceDerivatives(first, ai: data, display: data, account: h.account)
        let next = try await owner.prepareDerivatives(original, ai: data, display: data, account: h.account)
        _ = try await owner.replaceDerivatives(next, ai: data, display: data, account: h.account)
        try await owner.discardDerivatives(next, account: h.account)
        #expect(failures.isEmpty)
        #expect(phases.isSuperset(of: ["handoff:reserved", "handoff:writing", "handoff:completed", "pair:planned", "pair:writing", "pair:ready", "pair:retiring"]))
        let graph = try h.completeQualificationProjection()
        #expect(graph.assets.count == 1 && graph.work.isEmpty && graph.sources.isEmpty && graph.pairs.isEmpty)
    }

    @Test func detachedPartialSurvivesSourceDeletionAndColdOwnerReopen() async throws {
        let h = try Harness()
        var owner: SharedMediaInboxOwner? = try h.owner()
        var bytes = PhotoPreparationTestHarness.image(); bytes.append(Data(count: 131_072 - bytes.count))
        let source = try await owner!.stage { [bytes] in bytes }
        let request = try owner!.prepareHandoff(source, account: h.account, packageID: UUID(), draftGeneration: UUID())
        await owner!.setHandoffFileFault { if $0 == .duringWrite { throw Fault.injected } }
        await #expect(throws: (any Error).self) { _ = try await owner!.handoff(request, account: h.account) }
        _ = try h.completeQualificationProjection()
        owner = nil
        let reopened = try h.owner()
        try await reopened.abandonHandoff(request)
        let detached = try h.completeQualificationProjection()
        #expect(try detached.membership(packageID: request.packageID).ids(.source).isEmpty)
        try await reopened.discard(source)
        let afterSourceDeletion = try h.completeQualificationProjection()
        #expect(afterSourceDeletion.sources.isEmpty && afterSourceDeletion.handoffs.count == 1)
        #expect(afterSourceDeletion.allocations.count == 1 && afterSourceDeletion.work.count == 1)
        try await reopened.discardDetachedHandoff(request, account: h.account)
        #expect(try h.completeQualificationProjection().allocations.isEmpty)
    }

    @Test func membershipsRequireExactSavedSetAndInventoryWithoutRepair() throws {
        let h = try MemoryHarness(), p = try h.package()
        let graph = try SharedMediaPendingGraph.derive(in: h.context, inventory: h.inventory)
        #expect(throws: SharedMediaStorageFailure.conflict) { try graph.validateMembership(in: h.context, inventory: h.inventory) }
        h.context.insert(SharedMediaMembershipBootstrapRecord(inventoryID: h.inventory.id, inventoryGeneration: h.inventory.generation))
        let member = SharedMediaPendingMembershipRecord(packageID: p.id, inventoryID: h.inventory.id,
            inventoryGeneration: h.inventory.generation, ownerID: p.ownerID, draftGeneration: p.draftGeneration,
            membersData: try graph.membership(packageID: p.id).encoded())
        h.context.insert(member); try h.context.save()
        try graph.validateMembership(in: h.context, inventory: h.inventory)
        let valid = member.membersData
        member.membersData = try SharedMediaMembership(groups: [.init(kind: .asset, ids: [UUID()])]).encoded()
        #expect(throws: SharedMediaStorageFailure.conflict) { try graph.validateMembership(in: h.context, inventory: h.inventory) }
        #expect(member.membersData != valid) // Rejection did not silently rebuild it.
        member.membersData = valid
        member.ownerID = UUID()
        #expect(throws: SharedMediaStorageFailure.conflict) { try graph.validateMembership(in: h.context, inventory: h.inventory) }
        member.ownerID = p.ownerID
        let extra = try h.package()
        let expanded = try SharedMediaPendingGraph.derive(in: h.context, inventory: h.inventory)
        #expect(throws: SharedMediaStorageFailure.conflict) { try expanded.validateMembership(in: h.context, inventory: h.inventory) }
        h.context.delete(extra)
        h.inventory.generation = UUID()
        #expect(throws: SharedMediaStorageFailure.conflict) { try graph.validateMembership(in: h.context, inventory: h.inventory) }
    }

    @Test func logicalSharingDoesNotRequirePhysicalOriginPackageToSurvive() throws {
        let h = try MemoryHarness(), origin = UUID(), assetID = UUID()
        let owner = UUID(), token = "synthetic-physical-origin"
        h.context.insert(PhotoPreparationAsset(id: assetID, ownerID: owner, generation: UUID(), fileToken: token,
            contentType: "image/jpeg", byteCount: 17, sha256: String(repeating: "a", count: 64), acquisitionKindRaw: "synthetic", cleanupStateRaw: "ready"))
        h.context.insert(SharedMediaAllocationRecord(id: assetID, inventoryID: h.inventory.id, accountID: owner,
            packageID: origin, namespaceRaw: SharedMediaPhotoLedger.namespace, fileToken: token, poolRaw: "durable",
            stateRaw: "p1Materialized", materializedBytes: 17, reservedBytes: 0, physicalIdentity: "synthetic-inode"))
        h.context.insert(SharedMediaLeaseRecord(id: UUID(), allocationID: assetID, processEpoch: UUID(), purposeRaw: "p1AcquireV1", stateRaw: "closed"))
        for _ in 0..<4 {
            let package = try h.package(owner: owner), id = UUID()
            h.context.insert(PhotoPreparationReference(id: id, packageID: package.id, assetID: assetID, ownerID: owner,
                roleRaw: "original", ordinal: 0, revision: 0, isLive: true))
            h.context.insert(SharedMediaReferenceRecord(id: id, allocationID: assetID, accountID: owner,
                ownerID: id.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
        }
        // These unrelated rows exercise query scope only, not retained-cohort validity.
        for _ in 0..<160 { _ = try h.package(tier: "retained") }
        try h.context.save()
        let graph = try SharedMediaPendingGraph.derive(in: h.context, inventory: h.inventory)
        #expect(graph.packages.count == 4 && graph.assets.count == 1 && graph.references.count == 4)
        #expect(graph.allocations.first?.packageID == origin)
        #expect(!graph.packages.contains { $0.id == origin })
        let extra = try h.package()
        #expect(throws: SharedMediaStorageFailure.capacity) { try SharedMediaPendingGraph.derive(in: h.context, inventory: h.inventory) }
        h.context.delete(extra)
        let allocation = try #require(graph.allocations.first)
        allocation.inventoryID = UUID()
        #expect(throws: SharedMediaStorageFailure.conflict) { try SharedMediaPendingGraph.derive(in: h.context, inventory: h.inventory) }
    }

    @Test func combinedMetadataBudgetIncludesMembership() throws {
        let h = try MemoryHarness(), p = try h.package()
        let graph = try SharedMediaPendingGraph.derive(in: h.context, inventory: h.inventory)
        h.context.insert(SharedMediaMembershipBootstrapRecord(inventoryID: h.inventory.id, inventoryGeneration: h.inventory.generation))
        h.context.insert(SharedMediaPendingMembershipRecord(packageID: p.id, inventoryID: h.inventory.id,
            inventoryGeneration: h.inventory.generation, ownerID: p.ownerID, draftGeneration: p.draftGeneration,
            membersData: try graph.membership(packageID: p.id).encoded()))
        p.supportingContextData = Data(count: Int(PhotoPreparationPolicy.metadata))
        #expect(throws: SharedMediaStorageFailure.capacity) { try graph.validateMembership(in: h.context, inventory: h.inventory) }
    }

    @MainActor private struct MemoryHarness {
        let container: ModelContainer, context: ModelContext
        let inventory = SharedMediaInventoryRecord(id: UUID(), rootIdentity: "synthetic", storeIdentity: "synthetic",
            generation: UUID(), revision: 0, modeRaw: "synthetic", phaseRaw: "synthetic", cursor: "")
        init() throws {
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            context = ModelContext(container); context.autosaveEnabled = false; context.insert(inventory)
        }
        func package(owner: UUID = UUID(), tier: String = "pending") throws -> PhotoPreparationRecord {
            let id = UUID()
            let p = PhotoPreparationRecord(id: id, ownerID: owner, contractVersion: PhotoPreparationPolicy.contract,
                draftID: id, draftGeneration: UUID(), revision: 0, phaseRaw: "draftOwned",
                supportingContextData: try PhotoPreparationPolicy.encodeDraft(contexts: []), allocatedByteCount: 0, retirementRequested: false)
            p.accountingTierRaw = tier; context.insert(p); return p
        }
    }

    @MainActor private struct Harness {
        let base: URL, authority: URL, inbox: URL, photo: URL, container: ModelContainer
        let inventoryID = UUID(), accountID = UUID(), runtime = AuthRuntimeState()
        var account: PhotoOriginalPreparationOwner.AccountAccess { PhotoOriginalPreparationOwner.syntheticAccount(ownerID: accountID, runtime: runtime) }
        init() throws {
            base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("pending-graph-" + UUID().uuidString)
            authority = base.appendingPathComponent("authority"); inbox = base.appendingPathComponent("inbox"); photo = base.appendingPathComponent("photo")
            let db = base.appendingPathComponent("database")
            for root in [authority, inbox, photo, db] { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: db.appendingPathComponent("ledger.store"), cloudKitDatabase: .none)])
        }
        func owner() throws -> SharedMediaInboxOwner { try .init(container: container, authorityRoot: authority, inboxRoot: inbox, photoRoot: photo, inventoryID: inventoryID) }
        func completeQualificationProjection() throws -> SharedMediaPendingGraph {
            let context = ModelContext(container); context.autosaveEnabled = false
            let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            let graph = try SharedMediaPendingGraph.derive(in: context, inventory: inventory)
            // These fixtures have no retained consumers, so logical projection
            // must find every row, including unpublished and retiring work.
            #expect(Set(graph.allocations.map(\.id)) == Set(try context.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).map(\.id)))
            #expect(Set(graph.edges.map(\.id)) == Set(try context.fetch(FetchDescriptor<SharedMediaReferenceRecord>()).map(\.id)))
            #expect(Set(graph.leases.map(\.id)) == Set(try context.fetch(FetchDescriptor<SharedMediaLeaseRecord>()).map(\.id)))
            #expect(Set(graph.assets.map(\.id)) == Set(try context.fetch(FetchDescriptor<PhotoPreparationAsset>()).map(\.id)))
            #expect(Set(graph.work.map(\.id)) == Set(try context.fetch(FetchDescriptor<PhotoPreparationLease>()).map(\.id)))
            #expect(Set(graph.derivatives.map(\.id)) == Set(try context.fetch(FetchDescriptor<SharedMediaDerivativeWorkRecord>()).map(\.id)))
            return graph
        }
    }
}
