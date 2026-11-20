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

    @Test func v2PendingAndRetainedFactsExcludeOrdinaryDraftsAndPreserveV1Strictness() async throws {
        let fixtures = SharedMediaNativeConsumerGraphTests(), (h, id) = try await fixtures.fixture(count: 2)
        let app = try appProfile(h)
        let context = ModelContext(h.container); context.autosaveEnabled = false
        let ordinary = UUID()
        context.insert(PhotoPreparationRecord(id: ordinary, ownerID: h.ownerID, contractVersion: PhotoPreparationPolicy.contract,
            draftID: ordinary, draftGeneration: UUID(), revision: 0, phaseRaw: "preparing",
            supportingContextData: Data("not-native-metadata".utf8), allocatedByteCount: 0, retirementRequested: false))
        try context.save()
        let before = try #require(try SharedMediaConsumerLookup.one(context, id: id)).cohortData
        let pending = try await appAudit(h, app)
        #expect(pending.pendingPackages == 1 && pending.consumers == 1 && pending.allocations == 6)
        let row = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        #expect(throws: (any Error).self) { try SharedMediaNativeScopedEligibility.requireProfile(row) }
        try fixtures.promote(h, id)
        let retained = try await appAudit(h, app)
        #expect(retained.pendingPackages == 0 && retained.consumers == 1 && retained.allocations == 6)
        #expect(try #require(try SharedMediaConsumerLookup.one(ModelContext(h.container), id: id)).cohortData == before)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationRecord>()) == 2)
    }

    @Test(arguments: ["owner", "generation", "binding", "bootstrap", "member", "counter"])
    func v2ScopedCorruptionFailsWithoutRepair(_ fault: String) async throws {
        let h = try Harness(), owner = try await h.open(); _ = try await h.acquire(owner)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let app = try appProfile(h); _ = try await appAudit(h, app)
        let context = ModelContext(h.container); context.autosaveEnabled = false
        let row = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        switch fault {
        case "owner":
            let other = SharedMediaNativeAppProfile(ownerID: UUID(), inventoryID: row.id, generation: row.generation,
                storeIdentity: row.storeIdentity, physicalBinding: app.physicalBinding, receiptDigest: app.receiptDigest)
            row.rootIdentity = try other.rootIdentity
        case "generation": row.generation = UUID()
        case "binding": row.rootIdentity += " " // Noncanonical bytes remain invalid.
        case "bootstrap": try #require(try context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first).contractVersion = 1
        case "member": try #require(try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first).ownerID = UUID()
        default: try #require(try context.fetch(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()).first).liveCount += 1
        }
        try context.save()
        await #expect(throws: (any Error).self) { _ = try await appAudit(h, app) }
        #expect(!context.hasChanges)
    }

    @Test func v2ActivePreparationIgnoresOrdinaryWorkButRejectsItsOwnUnreadyAsset() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
            cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)
        let attempt = try await owner.reservePreparation(original: original, recipe: recipe)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let app = try appProfile(h), nativeBytes = try Data(contentsOf: h.file(original))
        let context = ModelContext(h.container); context.autosaveEnabled = false
        let ordinary = UUID(), assetID = UUID(), opaque = Data("ordinary-opaque-preparing-state".utf8)
        context.insert(PhotoPreparationRecord(id: ordinary, ownerID: h.ownerID, contractVersion: PhotoPreparationPolicy.contract,
            draftID: ordinary, draftGeneration: UUID(), revision: 0, phaseRaw: "preparing",
            supportingContextData: opaque, allocatedByteCount: 1, retirementRequested: false))
        context.insert(PhotoPreparationAsset(id: assetID, ownerID: h.ownerID, generation: UUID(),
            fileToken: "ordinary", contentType: "image/jpeg", byteCount: 1, sha256: String(repeating: "f", count: 64),
            acquisitionKindRaw: "picker", cleanupStateRaw: "retiring"))
        context.insert(PhotoPreparationLease(id: UUID(), packageID: ordinary, assetID: assetID, ownerID: h.ownerID,
            processEpoch: UUID(), purposeRaw: "acquire", partialFileToken: "ordinary.partial", finalFileToken: "ordinary",
            reservedByteCount: 1, allocatedByteCount: 0, writerStateRaw: "unknown", terminalProof: nil))
        try context.save()
        let result = try await appAudit(h, app)
        #expect(result.pendingPackages == 1 && result.allocations == 1)
        let nativeID = h.packageID
        let native = try #require(try context.fetch(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == nativeID })).first)
        let attemptBytes = try attempt.encoded()
        #expect(try SharedMediaNativeDraftEnvelope.decode(native.supportingContextData).attempt?.bytes == attemptBytes)
        let nativeAssetID = original.assetID
        let asset = try #require(try context.fetch(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == nativeAssetID })).first)
        asset.cleanupStateRaw = "retiring"; try context.save()
        await #expect(throws: (any Error).self) { _ = try await appAudit(h, app) }
        #expect(try Data(contentsOf: h.file(original)) == nativeBytes)
        #expect(try context.fetch(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == ordinary })).first?.supportingContextData == opaque)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 1)
    }

    private func appProfile(_ h: Harness) throws -> SharedMediaNativeAppProfile {
        // Synthetic persisted facts only. This cannot pass the filesystem opener.
        let context = ModelContext(h.container); context.autosaveEnabled = false
        let row = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let profile = SharedMediaNativeAppProfile(ownerID: h.ownerID, inventoryID: row.id, generation: row.generation,
            storeIdentity: row.storeIdentity, physicalBinding: String(repeating: "a", count: 64), receiptDigest: String(repeating: "b", count: 64))
        row.modeRaw = SharedMediaNativeAppProfile.mode; row.phaseRaw = SharedMediaNativeAppProfile.phase
        row.rootIdentity = try profile.rootIdentity
        try #require(try context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first).contractVersion = 2
        try context.save(); return profile
    }
    private func appAudit(_ h: Harness, _ profile: SharedMediaNativeAppProfile) async throws -> SharedMediaNativeScopedSnapshot {
        let context = ModelContext(h.container)
        let row = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let expected = SharedMediaStorageSnapshot(generation: row.generation, revision: row.revision, phase: row.phaseRaw, cursor: row.cursor)
        return try await SharedMediaNativeScopedAudit(app: h.container, profile: profile, expected: expected,
            check: {}, betweenPages: { await Task.yield() }).run()
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
