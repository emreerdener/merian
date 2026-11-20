import Foundation
import SwiftData
import Testing
@testable import Merian

/// Raw future fields are not execution or cleanup authority.
@Suite("Allocation storage stays closed", .serialized)
@MainActor
struct SharedMediaNativeAllocationFoundationTests {
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    typealias Fixture = SharedMediaNativeReleaseLiveFixture
    typealias Intent = SharedMediaNativeReceivingIntent
    private var variants: [(Data?, String?)] {
        [(Data(), nil), (nil, ""), (Data([0, 1, 255]), String(repeating: "a", count: 64))]
    }

    @Test func allocationLiabilityBlocksStagedStartAndColdRecovery() async throws {
        let helper = SharedMediaNativeReleaseStartOwnerTests()
        let (store, owner, _, admission) = try await helper.fixture()
        let request = admission.request
        _ = try await owner.stageAppRelease(admission)
        for (data, digest) in variants {
            let context = store.context(), slot = try helper.record(store, context)
            let original = Row(slot)
            slot.allocationData = data; slot.allocationSHA256 = digest; try context.save()
            let blocked = Row(slot)
            #expect(throws: SharedMediaStorageFailure.closed) { _ = try helper.staged(store) }
            await #expect(throws: SharedMediaStorageFailure.closed) { _ = try await owner.startAppRelease(request) }
            #expect(try helper.row(store) == blocked)
            slot.allocationData = nil; slot.allocationSHA256 = nil; try context.save()
            #expect(try helper.row(store) == original)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        // Cold opening audits the persisted liability before granting dispatch.
        // The prior owner must release its store fence before testing that gate.
        for (data, digest) in variants {
            let context = store.context(), slot = try helper.record(store, context)
            let original = Row(slot)
            slot.allocationData = data; slot.allocationSHA256 = digest; try context.save()
            let blocked = Row(slot)
            let schema = Schema(versionedSchema: CurrentSchema.self)
            let url = try #require(store.container.configurations.first).url
            let reopened = try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            ])
            let cold = try SharedMediaNativeOriginalOwner.appDispatch(
                account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: store.ownerID, runtime: store.runtime), drain: .init())
            await #expect(throws: SharedMediaStorageFailure.closed) {
                _ = try await cold.openApp(container: reopened, parent: store.parent, inventoryID: store.inventoryID)
            }
            #expect(await cold.invalidateAndAwaitForAccountTransition())
            #expect(try helper.row(store) == blocked)
            slot.allocationData = nil; slot.allocationSHA256 = nil; try context.save()
            #expect(try helper.row(store) == original)
        }
    }

    @Test func preparedAndReceivedOwnersRejectSidecarsWithoutChangingSavedOperation() async throws {
        let (store, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(staged: true)
        let prepared = try Intent.Prepared(request), id = store.packageID, inventoryID = store.inventoryID
        for received in [false, true] {
            if received { _ = try await owner.receiveAppPrepared(prepared) }
            for (data, hash) in variants {
                let c = store.context()
                let slot = try Fixture.one(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
                let original = Row(slot)
                slot.allocationData = data; slot.allocationSHA256 = hash; try c.save()
                let blocked = Row(slot)
                #expect(blocked != original)
                #expect(throws: SharedMediaStorageFailure.closed) { _ = try SharedMediaNativeReceivingSlot.decode(blocked, profile: prepared.profile) }
                #expect(throws: SharedMediaStorageFailure.closed) { _ = try SharedMediaNativeReceivingIntentGraph.snapshots(c) }
                let inventory = try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
                #expect(throws: SharedMediaStorageFailure.closed) { _ = try SharedMediaNativeReceivingCleanGraph.pending(c, inventory: inventory) }
                #expect(throws: SharedMediaStorageFailure.closed) { _ = try SharedMediaNativeReceivingPhaseGraph.pending(c, inventory: inventory) }
                #expect(throws: SharedMediaStorageFailure.closed) {
                    _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory, ownerID: store.ownerID, format: .appV2)
                }
                if !received {
                    await #expect(throws: SharedMediaStorageFailure.closed) { _ = try await owner.abandonAppReceiving(prepared) }
                }
                if received {
                    #expect(throws: SharedMediaStorageFailure.closed) {
                        _ = try SharedMediaNativeReceivedReleaseSnapshot.read(packageID: id, inventoryID: inventoryID, releaseID: UUID(), context: c)
                    }
                }
                await #expect(throws: SharedMediaStorageFailure.closed) { _ = try await owner.receiveAppPrepared(prepared) }
                let fresh = store.context()
                let saved = try Fixture.one(fresh, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
                #expect(Row(saved) == blocked && !fresh.hasChanges && !c.hasChanges)
                slot.allocationData = nil; slot.allocationSHA256 = nil; try c.save()
                #expect(Row(slot) == original)
            }
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func releasingAndForeignOrphanSidecarsCloseWholeStoreAuditAndPreserveEvidence() async throws {
        let f = try await Fixture.make(count: 1), id = f.store.packageID, inventoryID = f.store.inventoryID
        func audit() async throws {
            let c = f.store.context()
            let inventory = try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            let expected = SharedMediaStorageSnapshot(generation: inventory.generation, revision: inventory.revision,
                phase: inventory.phaseRaw, cursor: inventory.cursor)
            _ = try await SharedMediaNativeScopedAudit(app: f.store.container, profile: f.prepared.profile,
                expected: expected, check: {}, betweenPages: { await Task.yield() }).run()
        }
        try await audit(); _ = try f.read()
        for foreign in [false, true] {
            for (data, hash) in variants {
                let c = f.store.context()
                let slot: SharedMediaReceivingIntentRecord
                if foreign {
                    slot = .init(packageID: UUID(), inventoryID: UUID(), inventoryGeneration: UUID(), ownerID: UUID(),
                        draftGeneration: UUID(), operationID: UUID(), preparedData: Data(), preparedSHA256: "")
                    c.insert(slot)
                } else {
                    slot = try Fixture.one(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
                }
                let original = Row(slot)
                slot.allocationData = data; slot.allocationSHA256 = hash; try c.save()
                let blocked = Row(slot)
                if !foreign {
                    #expect(throws: SharedMediaStorageFailure.closed) { _ = try f.read() }
                    #expect(throws: SharedMediaStorageFailure.closed) {
                        _ = try SharedMediaNativeReleaseMetadataSnapshot.read(packageID: id, inventoryID: inventoryID, context: f.store.context())
                    }
                }
                // An orphan is rejected at root membership before sidecar decoding.
                let auditFailure: SharedMediaStorageFailure = foreign ? .conflict : .closed
                await #expect(throws: auditFailure) { try await audit() }
                #expect(Row(slot) == blocked && !c.hasChanges)
                #expect(try SharedMediaStorageRepository.hasLiabilities(in: c))
                #expect(throws: SharedMediaStorageFailure.inUse) { try SharedMediaPurgeState.requireEmptyGraph(c) }
                if foreign { c.delete(slot) } else {
                    slot.allocationData = nil; slot.allocationSHA256 = nil
                    #expect(Row(slot) == original)
                }
                try c.save(); try await audit(); _ = try f.read()
            }
        }
    }
}
