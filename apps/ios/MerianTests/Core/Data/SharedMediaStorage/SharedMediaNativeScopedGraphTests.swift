import Foundation
import SwiftData
import Testing
@testable import Merian

/// Synthetic profile relabeling is confined to test data. Runtime inspection
/// never converts qualification stores or creates native membership.
@Suite("Scoped native graph joins", .serialized)
@MainActor
struct SharedMediaNativeScopedGraphTests {
    typealias Harness = SharedMediaNativePreparationTests.Harness

    @Test func fourPendingSharesCountOncePhysicallyAndRejectFifthAnchor() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        for _ in 0..<3 { _ = try await owner.share(owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID())) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let scope = try profile(h), before = try await audit(h, scope)
        #expect(before.pendingPackages == 4 && before.allocations == 1 && before.receipts == 1)
        let context = ModelContext(h.container); context.autosaveEnabled = false
        context.insert(SharedMediaPendingMembershipRecord(packageID: UUID(), inventoryID: h.inventoryID,
            inventoryGeneration: scope.generation, ownerID: h.ownerID, draftGeneration: UUID(),
            membersData: try SharedMediaMembership(groups: []).encoded()))
        try context.save()
        await #expect(throws: (any Error).self) { _ = try await audit(h, scope) }
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaPendingMembershipRecord>()) == 5)
    }

    @Test(arguments: ["generation", "owner", "draft", "missingPackage", "missingMember", "members", "allocation", "counter", "receipt", "edge", "reverseOwner"])
    func anchoredCorruptionFailsWithoutRepair(_ fault: String) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let scope = try profile(h); _ = try await audit(h, scope)
        let context = ModelContext(h.container); context.autosaveEnabled = false
        let member = try #require(try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first)
        switch fault {
        case "generation": member.inventoryGeneration = UUID()
        case "owner": member.ownerID = UUID()
        case "draft": member.draftGeneration = UUID()
        case "missingPackage": context.delete(try #require(try context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first))
        case "missingMember": context.delete(member)
        case "members": member.membersData = try SharedMediaMembership(groups: []).encoded()
        case "allocation": context.delete(try #require(try context.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first))
        case "counter":
            let row = try #require(try context.fetch(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()).first)
            row.inventoryGeneration = UUID()
        case "receipt":
            let row = try #require(try context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first)
            row.inventoryGeneration = UUID()
        case "edge": context.delete(try #require(try context.fetch(FetchDescriptor<SharedMediaReferenceRecord>()).first))
        default:
            // Even matching reference counters cannot authorize an ordinary,
            // unanchored package to consume an inventory-owned original.
            let id = UUID(), refID = UUID()
            context.insert(PhotoPreparationRecord(id: id, ownerID: h.ownerID, contractVersion: PhotoPreparationPolicy.contract,
                draftID: id, draftGeneration: UUID(), revision: 0, phaseRaw: "draftOwned",
                supportingContextData: Data(), allocatedByteCount: Int64(h.bytes.count), retirementRequested: false))
            context.insert(PhotoPreparationReference(id: refID, packageID: id, assetID: original.assetID,
                ownerID: h.ownerID, roleRaw: "original", ordinal: 0, revision: 0, isLive: true))
            context.insert(SharedMediaReferenceRecord(id: refID, allocationID: original.assetID, accountID: h.ownerID,
                ownerID: refID.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
            let counter = try #require(try context.fetch(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()).first)
            counter.liveCount += 1; counter.revision += 1
        }
        try context.save()
        await #expect(throws: (any Error).self) { _ = try await audit(h, scope) }
        #expect(!context.hasChanges)
    }

    @Test func pendingAndRetainedConsumersPreserveBytesAndRejectRetainedMembership() async throws {
        let fixtures = SharedMediaNativeConsumerGraphTests()
        let (h, id) = try await fixtures.fixture(count: 2), scope = try profile(h)
        let pending = try await audit(h, scope)
        #expect(pending.pendingPackages == 1 && pending.consumers == 1 && pending.allocations == 6)
        let context = ModelContext(h.container)
        let member = try #require(try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first)
        let memberBytes = member.membersData
        let before = try #require(try SharedMediaConsumerLookup.one(context, id: id)).cohortData
        try fixtures.promote(h, id)
        let retained = try await audit(h, scope)
        #expect(retained.pendingPackages == 0 && retained.consumers == 1 && retained.allocations == 6)
        let fresh = ModelContext(h.container); fresh.autosaveEnabled = false
        #expect(try #require(try SharedMediaConsumerLookup.one(fresh, id: id)).cohortData == before)
        fresh.insert(SharedMediaPendingMembershipRecord(packageID: h.packageID, inventoryID: h.inventoryID,
            inventoryGeneration: scope.generation, ownerID: h.ownerID, draftGeneration: h.draft, membersData: memberBytes))
        try fresh.save()
        await #expect(throws: (any Error).self) { _ = try await audit(h, scope) }
    }

    @Test func readOnlyInspectionDoesNotAssertPhysicalAvailabilityOrRepeatLoader() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let scope = try profile(h), before = try await audit(h, scope)
        try FileManager.default.removeItem(at: h.file(original))
        #expect(try await audit(h, scope) == before)
        #expect(!FileManager.default.fileExists(atPath: h.file(original).path))
    }

    private func profile(_ h: Harness) throws -> SharedMediaNativeScopeIdentity {
        let context = ModelContext(h.container); context.autosaveEnabled = false
        let row = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        row.modeRaw = SharedMediaNativeScopedEligibility.mode; row.phaseRaw = SharedMediaNativeScopedEligibility.phase
        try context.save()
        return .init(inventoryID: row.id, generation: row.generation, ownerID: h.ownerID,
            storeIdentity: row.storeIdentity, rootBinding: row.rootIdentity)
    }
    private func audit(_ h: Harness, _ scope: SharedMediaNativeScopeIdentity) async throws -> SharedMediaNativeScopedSnapshot {
        let context = ModelContext(h.container)
        let row = try SharedMediaNativeScopedEligibility.header(context: context, scope: scope)
        let expected = SharedMediaStorageSnapshot(generation: row.generation, revision: row.revision,
            phase: row.phaseRaw, cursor: row.cursor)
        return try await SharedMediaNativeScopedAudit(container: h.container, scope: scope, expected: expected,
            check: {}, betweenPages: { await Task.yield() }).run()
    }
}
