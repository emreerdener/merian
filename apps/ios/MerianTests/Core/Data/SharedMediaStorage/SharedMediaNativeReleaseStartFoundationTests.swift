import Foundation
import SwiftData
import Testing
@testable import Merian

/// Raw future fields are not execution or cleanup authority.
@Suite("Release-start storage stays closed", .serialized)
@MainActor
struct SharedMediaNativeReleaseStartFoundationTests {
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    typealias Fixture = SharedMediaNativeReleaseLiveFixture
    typealias Intent = SharedMediaNativeReceivingIntent
    private var variants: [(Data?, String?)] {
        [(Data(), nil), (nil, ""), (Data([0, 1, 255]), String(repeating: "a", count: 64))]
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
                slot.releaseStartData = data; slot.releaseStartSHA256 = hash; try c.save()
                let blocked = Row(slot)
                #expect(blocked != original)
                #expect(throws: SharedMediaStorageFailure.closed) { _ = try SharedMediaNativeReceivingSlot.decode(blocked, profile: prepared.profile) }
                #expect(throws: SharedMediaStorageFailure.closed) { _ = try SharedMediaNativeReceivingIntentGraph.snapshots(c) }
                let inventory = try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
                // A complete pair on a received row reaches the typed request
                // digest check; incomplete pairs and prepared rows close earlier.
                let routedFailure: SharedMediaStorageFailure = received && data != nil && hash != nil ? .conflict : .closed
                #expect(throws: routedFailure) { _ = try SharedMediaNativeReceivingCleanGraph.pending(c, inventory: inventory) }
                #expect(throws: SharedMediaStorageFailure.closed) { _ = try SharedMediaNativeReceivingPhaseGraph.pending(c, inventory: inventory) }
                #expect(throws: routedFailure) {
                    _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory, ownerID: store.ownerID, format: .appV2)
                }
                if received {
                    #expect(throws: SharedMediaStorageFailure.closed) {
                        _ = try SharedMediaNativeReceivedReleaseSnapshot.read(packageID: id, inventoryID: inventoryID, releaseID: UUID(), context: c)
                    }
                }
                await #expect(throws: routedFailure) { _ = try await owner.receiveAppPrepared(prepared) }
                let fresh = store.context()
                let saved = try Fixture.one(fresh, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
                #expect(Row(saved) == blocked && !fresh.hasChanges && !c.hasChanges)
                slot.releaseStartData = nil; slot.releaseStartSHA256 = nil; try c.save()
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
                slot.releaseStartData = data; slot.releaseStartSHA256 = hash; try c.save()
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
                    slot.releaseStartData = nil; slot.releaseStartSHA256 = nil
                    #expect(Row(slot) == original)
                }
                try c.save(); try await audit(); _ = try f.read()
            }
        }
    }
}
