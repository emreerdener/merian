import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Inactive P2 receiving, abandonment and restaging owners", .serialized)
@MainActor
struct SharedMediaNativeReceivingPhaseOwnerTests {
    typealias Intent = SharedMediaNativeReceivingIntent
    private let checks = SharedMediaNativeReceivingStagingTests()

    @Test func successfulReceiveAcknowledgesPersistedRowsWithoutAnotherSave() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let p = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft,
            pairIDs: checks.pairIDs(request))
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        let received = try await owner.receiveAppPrepared(p)
        #expect(saves == 1)
        let row = try #require(try h.context().fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
        guard case .received(_, _, let transaction) = try SharedMediaNativeReceivingSlot.decode(.init(row), profile: p.profile) else {
            Issue.record("Expected acknowledged persisted outcome"); return
        }
        #expect(received == transaction.cohort)
        _ = try #require(try SharedMediaNativeReceivingRows.read(transaction, in: h.context(), absent: false))
        #expect(try await owner.receiveAppPrepared(p) == received)
        #expect(saves == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func receivedOutcomeSurvivesLostAcknowledgementColdReopenAndMissingOriginal() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let p = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: checks.pairIDs(request))
        #expect(p.version == 2 && p.intentRevision == 0 && p.restagedFromSHA256 == nil)
        var saves = 0, saved = false
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1 }
            if $0 == .afterSave { saved = true }
            if $0 == .beforeReadback && saved { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPrepared(p) }
        #expect(saves == 1)
        let row = try #require(try h.context().fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
        guard case .received(_, _, let transaction) = try SharedMediaNativeReceivingSlot.decode(.init(row), profile: p.profile) else {
            Issue.record("Expected saved received outcome"); return
        }
        #expect(try row.preparedData == p.encoded())
        let c = h.context(), rows = try #require(try SharedMediaNativeReceivingRows.read(transaction, in: c, absent: false))
        #expect(rows.queue.mediaAuthorityRaw == "sharedDirectNativeReceivingV2")
        #expect(rows.queue.queueNeedsAttention && rows.job.statusRaw == OfflineJobStatus.needsAttention.rawValue)
        #expect(rows.job.metadataJSON == transaction.metadata && rows.event.metadataJSON == transaction.metadata)
        #expect(transaction.metadata.contains("native_receiving_v2") && !transaction.metadata.contains("native_receiving_v1"))
        #expect(!SharedMediaLegacyQueueAccess.permitsMetadata(rows.job.metadataJSON))
        #expect(throws: (any Error).self) {
            _ = try SharedMediaConsumerAuthority.classify(raw: rows.queue.mediaAuthorityRaw, consumerID: rows.queue.sharedMediaConsumerID, record: .queue)
        }
        let cohort = try SharedMediaNativeFrozenCohort.decode(p.cohort.bytes)
        let original = try SharedMediaNativeDerivativeIntent.decode(#require(cohort.entries.first).intent.bytes).preparation.original
        try FileManager.default.removeItem(at: h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(original.token))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await checks.reopen(h)
        try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        #expect(try await cold.receiveAppPrepared(p) == transaction.cohort)
        #expect(try await cold.receiveAppPrepared(p) == transaction.cohort)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func abandonmentPreservesDraftThenExplicitRestageRecoversOneSavedSuccessor() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let ids = try checks.pairIDs(request)
        let p = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        let a = try await owner.abandonAppReceiving(p)
        #expect(try h.package().supportingContextData == p.package.envelope)
        try checks.noReceivingRows(h)
        #expect(try await owner.abandonAppReceiving(p) == a)
        let edit = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: [.init(freeText: "explicit replacement supporting description")])
        _ = try await owner.saveAppMetadata(edit)
        await #expect(throws: (any Error).self) { _ = try await owner.abandonAppReceiving(p) }
        var saved = false, saves = 0
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1 }
            if $0 == .afterSave { saved = true }
            if $0 == .beforeReadback && saved { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) {
            _ = try await owner.restageAppReceiving(a, draftGeneration: h.draft, pairIDs: ids)
        }
        #expect(saves == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await checks.reopen(h)
        try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        let replacement = try await cold.restageAppReceiving(a, draftGeneration: h.draft, pairIDs: ids)
        #expect(replacement.intentRevision == a.revision + 1)
        #expect(replacement.restagedFromSHA256 == (try SharedMediaAcquisitionEncoding.digest(a.encoded())))
        #expect(replacement.operationID != p.operationID && replacement.queueID != p.queueID)
        let repeated = try await cold.restageAppReceiving(a, draftGeneration: h.draft, pairIDs: ids)
        #expect(try replacement.encoded() == repeated.encoded())
        let wrong = try SharedMediaNativeReceivingTestFixture.copy(a, changes: ["preparedSHA256": String(repeating: "b", count: 64)])
        await #expect(throws: (any Error).self) { _ = try await cold.restageAppReceiving(wrong, draftGeneration: h.draft, pairIDs: ids) }
        try checks.noReceivingRows(h)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func legacyPreparedCanOnlyRecoverOrAbandonBeforeFreshP2Restage() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let old = try Intent.Prepared(request), bytes = try old.encoded(), c = h.context()
        c.insert(SharedMediaReceivingIntentRecord(packageID: h.packageID, inventoryID: old.profile.inventoryID,
            inventoryGeneration: old.profile.generation, ownerID: h.ownerID, draftGeneration: h.draft,
            operationID: old.operationID, preparedData: bytes, preparedSHA256: SharedMediaAcquisitionEncoding.digest(bytes)))
        try c.save()
        #expect(try await owner.discoverAppReceivingIntent(packageID: h.packageID)?.encoded() == bytes)
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPrepared(old) }
        let a = try await owner.abandonAppReceiving(old)
        #expect(a.version == 1)
        let p = try await owner.restageAppReceiving(a, draftGeneration: h.draft, pairIDs: checks.pairIDs(request))
        #expect(p.version == 2 && p.restagedFromSHA256 != nil)
        _ = try await owner.receiveAppPrepared(p)
        await #expect(throws: (any Error).self) {
            _ = try await owner.restageAppReceiving(a, draftGeneration: h.draft, pairIDs: checks.pairIDs(request))
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}

extension SharedMediaNativeReceivingPhaseOwnerTests {
    @Test(arguments: ["consumer", "queue", "job", "event", "slot", "marker", "result"])
    func damagedReceivedSetCannotRecoverOrSaveAgain(_ fault: String) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let p = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: checks.pairIDs(request))
        _ = try await owner.receiveAppPrepared(p)
        let c = h.context(), slot = try #require(try c.fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
        guard case .received(_, _, let transaction) = try SharedMediaNativeReceivingSlot.decode(.init(slot), profile: p.profile) else {
            Issue.record("Missing received slot"); return
        }
        let rows = try #require(try SharedMediaNativeReceivingRows.read(transaction, in: c, absent: false))
        switch fault {
        case "consumer": c.delete(rows.consumer)
        case "queue": c.delete(rows.queue)
        case "job": c.delete(rows.job)
        case "event": c.delete(rows.event)
        case "slot": c.delete(slot)
        case "marker": rows.consumer.contractVersion = SharedMediaNativeConsumerCohort.Format.receiving.rawValue
        default: slot.resultSHA256 = String(repeating: "f", count: 64)
        }
        try c.save()
        let envelope = try h.package().supportingContextData
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPrepared(p) }
        #expect(saves == 0)
        #expect(try h.package().supportingContextData == envelope)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func cancellationOfPreparedOwnerWaitPreservesExactDraft(_ abandon: Bool) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let p = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: checks.pairIDs(request))
        let before = try checks.facts(h), coordinator = ScanInferencePersistenceCoordinator.shared
        let held = await coordinator.acquireAll(scanIds: [p.queueID.uuidString, p.observationID.uuidString])
        let task = Task {
            if abandon { _ = try await owner.abandonAppReceiving(p) }
            else { _ = try await owner.receiveAppPrepared(p) }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await coordinator.hasWaitingWriter(scanId: held[0])), ContinuousClock.now < deadline { await Task.yield() }
        #expect(await coordinator.hasWaitingWriter(scanId: held[0]))
        task.cancel(); await coordinator.releaseAll(scanIds: held)
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(try checks.facts(h) == before)
        try checks.noReceivingRows(h)
        _ = try await owner.abandonAppReceiving(p)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["original", "slot", "package", "inventory"])
    func finalPreparedReceiveSealRejectsConcurrentSubstitution(_ fault: String) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let p = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: checks.pairIDs(request))
        var reached = false
        try owner.setMetadataFault {
            guard $0 == .beforeSave else { return }; reached = true
            if fault == "original" {
                let cohort = try SharedMediaNativeFrozenCohort.decode(p.cohort.bytes)
                let original = try SharedMediaNativeDerivativeIntent.decode(#require(cohort.entries.first).intent.bytes).preparation.original
                let path = h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(original.token)
                let bytes = try Data(contentsOf: path)
                try FileManager.default.removeItem(at: path); try bytes.write(to: path)
            } else {
                let c = h.context()
                if fault == "slot" { try #require(try c.fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first).revision += 1 }
                else if fault == "package" { try h.package(in: c).revision += 1 }
                else { try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first).revision += 1 }
                try c.save()
            }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPrepared(p) }
        #expect(reached)
        try checks.noReceivingRows(h)
        #expect(try h.package().supportingContextData == p.package.envelope)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}

extension SharedMediaNativeReceivingPhaseOwnerTests {
    @Test func historicalP2WithoutRestageProvenanceCannotMasqueradeAsReceived() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let old = try Intent.Prepared(request)
        let p = try SharedMediaNativeReceivingTestFixture.copy(old,
            changes: ["format": "nativeReceivingIntentV2", "version": 2, "intentRevision": 3])
        let transaction = try p.descriptorForTransaction(header: request.header)
        // Build a self-consistent but never owner-admitted received set. Codec
        // compatibility alone must not make this active or recoverable.
        try SharedMediaNativeAppReceivingTests().seedLegacyReceived(h, .init(transaction))
        let c = h.context(), bytes = try p.encoded()
        let row = SharedMediaReceivingIntentRecord(packageID: h.packageID, inventoryID: p.profile.inventoryID,
            inventoryGeneration: p.profile.generation, ownerID: h.ownerID, draftGeneration: h.draft,
            operationID: p.operationID, preparedData: bytes, preparedSHA256: SharedMediaAcquisitionEncoding.digest(bytes))
        row.schemaVersion = 2; row.revision = 4; row.phaseRaw = "received"
        let result = try Intent.Received(prepared: p, request: transaction).encoded(prepared: p)
        row.resultData = result; row.resultSHA256 = SharedMediaAcquisitionEncoding.digest(result)
        c.insert(row); try c.save()
        let consumer = try #require(try c.fetch(FetchDescriptor<SharedMediaConsumerRecord>()).first)
        #expect(throws: (any Error).self) { _ = try SharedMediaNativeConsumerGraph.validateScoped(consumer, context: c, format: .appV2) }
        await #expect(throws: (any Error).self) { _ = try await owner.inspectApp() }
        await #expect(throws: (any Error).self) { _ = try await owner.discoverAppReceivingSlot(packageID: h.packageID) }
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPrepared(p) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}

extension SharedMediaNativeReceivingPhaseOwnerTests {
    @Test func abandonedSourceCanBeSharedWhileRemovalRetainsTerminalAndSharedBytes() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let p = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: checks.pairIDs(request))
        _ = try await owner.abandonAppReceiving(p)
        let cohort = try SharedMediaNativeFrozenCohort.decode(p.cohort.bytes)
        let original = try SharedMediaNativeDerivativeIntent.decode(#require(cohort.entries.first).intent.bytes).preparation.original
        let path = h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(original.token)
        let bytes = try Data(contentsOf: path)
        let before = try #require(try h.context().fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
        let slot = SharedMediaNativeReceivingIntentGraph.Row(before)
        let share = try await owner.prepareAppOriginalShare(original.reference, packageID: UUID(), draftGeneration: UUID())
        let destination = try await owner.shareAppOriginal(share)
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAppOriginalRemoval(original.reference) }
        let removal = try await owner.prepareAppOriginalRemoval(destination)
        try await owner.removeAppOriginal(removal)
        try await owner.recoverAppOriginalRetirements()
        #expect(try Data(contentsOf: path) == bytes)
        let after = try #require(try h.context().fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
        #expect(SharedMediaNativeReceivingIntentGraph.Row(after) == slot)
        #expect(try h.package().supportingContextData == p.package.envelope)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}
