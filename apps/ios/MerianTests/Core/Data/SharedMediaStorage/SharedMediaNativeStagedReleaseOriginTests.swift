import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Staged release origin association", .serialized)
@MainActor
struct SharedMediaNativeStagedReleaseOriginTests {
    typealias Reader = SharedMediaNativeStagedReleaseOrigin
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Fixture = SharedMediaNativeReleaseLiveFixture

    @Test(arguments: [1, 2])
    func bindsSavedOriginAcrossStageDigitBoundaryAndKeepsOrdinaryReadersClosed(_ count: Int) async throws {
        let store = try await fixture(count)
        let c = store.context(), inventory = try loadInventory(store, c)
        let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(store.packageID, in: c))
        let before = Reader.Row(row)
        let value = try Reader.read(before, inventory: inventory, context: c)
        #expect(value.header.inventory.revision == (count == 1 ? 100 : 1000))
        #expect(value.request.stagePreHeader.inventory.revision + 1 == value.header.inventory.revision)
        #expect(value.row == before && !c.hasChanges)
        let consumer = try SharedMediaNativeReceivingPhaseGraph.receivedRows(value.transaction, context: c).consumer
        #expect(try SharedMediaNativeConsumerGraph.validateStagedReceived(consumer, origin: value, context: c) == value.transaction.cohort)
        #expect(throws: SharedMediaStorageFailure.closed) {
            _ = try SharedMediaNativeReceivingSlot.decode(before, profile: value.prepared.profile)
        }
        #expect(throws: SharedMediaStorageFailure.closed) {
            _ = try SharedMediaNativeConsumerGraph.validateScoped(consumer, context: c, format: .appV2)
        }
        #expect(throws: SharedMediaStorageFailure.closed) {
            _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
                ownerID: store.ownerID, format: .appV2)
        }
        inventory.revision += 17; try c.save()
        #expect(throws: SharedMediaStorageFailure.stale) { try value.requireCurrent(context: c) }
        let fresh = store.context()
        let again = try Reader.read(before, inventory: self.loadInventory(store, fresh), context: fresh)
        #expect(again.request == value.request && again.row == before)
        #expect(again.header.inventory.revision == value.header.inventory.revision + 17)
        #expect(!fresh.hasChanges)
        // Persisted columns cannot attest that staging occurred at this header.
        // Another canonical historical floor is structurally indistinguishable;
        // it still grants no ordinary accounting/acceptance/start authority.
        let alternateHeader = try SharedMediaNativeAppMetadataFacts.successor(value.request.stagePreHeader)
        let alternate = try SharedMediaNativeReleaseStartRequest(prepared: value.prepared, received: value.received,
            stagePreHeader: alternateHeader, releaseID: value.request.releaseID)
        let encoding = try alternate.encoding()
        let alternateRow = try #require(try SharedMediaNativeReceivingPhaseGraph.row(store.packageID, in: fresh))
        alternateRow.releaseStartData = encoding.data; alternateRow.releaseStartSHA256 = encoding.sha256
        try fresh.save()
        let alternative = try Reader.read(Reader.Row(alternateRow), inventory: self.loadInventory(store, fresh), context: fresh)
        #expect(alternative.request.stagePreHeader == alternateHeader)
        #expect(throws: SharedMediaStorageFailure.closed) {
            _ = try SharedMediaNativeReceivingSlot.decode(alternative.row, profile: alternative.prepared.profile)
        }
        #expect(!fresh.hasChanges)
    }

    @Test func rejectsPartialMalformedAndMisboundSidecarsWithoutMutation() async throws {
        let store = try await fixture(1), c = store.context(), inventory = try loadInventory(store, c)
        let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(store.packageID, in: c))
        let saved = Reader.Row(row), data = try #require(row.releaseStartData), digest = try #require(row.releaseStartSHA256)
        let request = try SharedMediaNativeReleaseStartRequest.decode(data, sha256: digest)
        for fault in ["noData", "noDigest", "digest", "malformed", "binding", "phase", "revision", "prepared", "result", "owner", "cursor"] {
            row.releaseStartData = data; row.releaseStartSHA256 = digest
            row.phaseRaw = saved.phase; row.revision = saved.revision; row.preparedData = saved.preparedData
            row.resultData = saved.resultData; row.ownerID = saved.ownerID; row.id = saved.id
            switch fault {
            case "noData": row.releaseStartData = nil
            case "noDigest": row.releaseStartSHA256 = nil
            case "digest": row.releaseStartSHA256 = String(repeating: "0", count: 64)
            case "malformed": row.releaseStartData = Data("{}".utf8); row.releaseStartSHA256 = SharedMediaAcquisitionEncoding.digest(row.releaseStartData!)
            case "binding":
                let changed: SharedMediaNativeReleaseStartRequest = try SharedMediaNativeReceivingTestFixture.copy(request, changes: ["bindingID": UUID().uuidString])
                let encoding = try changed.encoding(); row.releaseStartData = encoding.data; row.releaseStartSHA256 = encoding.sha256
            case "phase": row.phaseRaw = "prepared"
            case "revision": row.revision += 1
            case "prepared": row.preparedData = Data("{}".utf8)
            case "result": row.resultData = Data("{}".utf8)
            case "owner": row.ownerID = UUID()
            default: row.id = UUID() // Read-only cursor now deliberately disagrees with the row ID.
            }
            try c.save()
            let before = Reader.Row(row)
            #expect(throws: (any Error).self) { _ = try Reader.read(before, inventory: inventory, context: c) }
            #expect(Reader.Row(row) == before && !c.hasChanges)
        }
    }

    @Test func rejectsStaleSnapshotHeaderQuartetAndFrozenMembership() async throws {
        let store = try await fixture(1), c = store.context(), inventory = try loadInventory(store, c)
        let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(store.packageID, in: c))
        let saved = Reader.Row(row), value = try Reader.read(saved, inventory: inventory, context: c)
        let rows = try SharedMediaNativeReceivingPhaseGraph.receivedRows(value.transaction, context: c)
        let id = store.packageID, inventoryID = store.inventoryID
        let member = try Fixture.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        let bootstrap = try Fixture.one(c, FetchDescriptor<SharedMediaMembershipBootstrapRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let oldRevision = inventory.revision, oldBootstrap = bootstrap.revision
        let oldMember = member.membersData, oldConsumer = rows.consumer.cohortSHA256, oldEvent = rows.event.metadataJSON
        for fault in ["headerBeforeStage", "bootstrap", "member", "consumer", "event", "changedRow"] {
            inventory.revision = oldRevision; bootstrap.revision = oldBootstrap
            member.membersData = oldMember; rows.consumer.cohortSHA256 = oldConsumer; rows.event.metadataJSON = oldEvent
            row.releaseStartSHA256 = saved.releaseStartSHA256
            switch fault {
            case "headerBeforeStage": inventory.revision = value.request.stagePreHeader.inventory.revision
            case "bootstrap": bootstrap.revision += 1
            case "member": member.membersData = Data("[]".utf8)
            case "consumer": rows.consumer.cohortSHA256 = String(repeating: "0", count: 64)
            case "event": rows.event.metadataJSON = "{}"
            default: row.releaseStartSHA256 = String(repeating: "0", count: 64)
            }
            try c.save()
            let before = Reader.Row(row)
            #expect(throws: (any Error).self) { _ = try Reader.read(saved, inventory: inventory, context: c) }
            #expect(Reader.Row(row) == before && !c.hasChanges)
        }
    }

    private func loadInventory(_ store: Store, _ c: ModelContext) throws -> SharedMediaInventoryRecord {
        let id = store.inventoryID
        return try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
    }

    private func fixture(_ count: Int) async throws -> Store {
        let (store, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: count, staged: true)
        _ = try await owner.receiveAppPrepared(Intent.Prepared(request))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let c = store.context(), inventory = try loadInventory(store, c)
        inventory.revision = count == 1 ? 99 : 999; try c.save()
        let measurement = try SharedMediaNativeReceivedReleaseSnapshot.read(packageID: store.packageID,
            inventoryID: store.inventoryID, releaseID: UUID(), context: c)
        let stagedRequest = try SharedMediaNativeReleaseStartRequest(prepared: measurement.components.prepared,
            received: measurement.components.received, stagePreHeader: measurement.header,
            releaseID: measurement.components.progress.plan.releaseID)
        let encoding = try stagedRequest.encoding()
        let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(store.packageID, in: c))
        // Test-only saved shape. No production staging or save authority exists.
        row.releaseStartData = encoding.data; row.releaseStartSHA256 = encoding.sha256
        inventory.revision += 1; try c.save()
        return store
    }
}
