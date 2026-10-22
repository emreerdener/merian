import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Persisted native receiving metadata boundaries", .serialized)
@MainActor
struct SharedMediaNativeReceivingBoundaryTests {
    private let checks = SharedMediaNativeReceivingStagingTests()
    // Fixed legal one-original shapes measured with the production codec.
    // Both values must still be proved through the real persisted owner.
    @Test(arguments: [Int64(0), Int64(1)])
    func persistedMetadataBoundaryUsesActualDraftAndOwnerAdmission(_ excess: Int64) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: 1)
        let fixture = try SharedMediaNativeReceivingTestFixture.capture(h, request: request).freshP2()
        #expect(try fixture.metadata() == fixture.auditedMetadata)
        let target = PhotoPreparationPolicy.metadata + excess
        let contexts = boundaryContexts(excess: excess)
        _ = try PhotoPreparationPolicy.contexts(contexts)
        let projected = try projectedCharge(fixture.context(contexts, advancingPackage: true))
        try #require(projected == target, "Fixed boundary encoding drifted; do not search or substitute a nearby value")
        let edit = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: contexts)
        _ = try await owner.saveAppMetadata(edit)
        let current = try await owner.appReceivingRequest(packageID: h.packageID, pairIDs: checks.pairIDs(request),
            operationID: request.freeze.commit.operationID, queueID: UUID(uuidString: request.cohort.originQueueID)!,
            observationID: UUID(uuidString: request.cohort.observationID)!, bindingID: request.cohort.bindingID,
            generation: #require(request.cohort.inferenceGeneration), eventID: UUID(uuidString: request.eventID)!, timestamp: request.timestamp)
        // Recapture only actual persisted facts after the real metadata save.
        let persisted = try SharedMediaNativeReceivingTestFixture.capture(h, request: current).freshP2()
        #expect(try persisted.metadata() == persisted.auditedMetadata)
        let persistedCharge = try projectedCharge(persisted)
        try #require(persistedCharge == target)
        let before = try checks.facts(h), revision = try checks.inventory(h).revision
        if excess == 0 {
            let saved = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: checks.pairIDs(request))
            let c = h.context(), inventory = try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
                ownerID: h.ownerID, format: .appV2)
            #expect(budget.metadataByPackage[h.packageID] == PhotoPreparationPolicy.metadata)
            #expect(inventory.revision == revision + 1)
            #expect(try checks.facts(h).packages == before.packages)
            #expect(try SharedMediaNativeFrozenCohort.decode(saved.cohort.bytes).supportingBytes ==
                SharedMediaNativeFrozenSupporting(contexts: contexts, presentation: []).encoded())
            try owner.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
            #expect(try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft,
                pairIDs: checks.pairIDs(request)).encoded() == saved.encoded())
        } else {
            await #expect(throws: SharedMediaStorageFailure.capacity) {
                _ = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: checks.pairIDs(request))
            }
            #expect(try checks.facts(h) == before)
            #expect(try checks.inventory(h).revision == revision)
            #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaReceivingIntentRecord>()) == 0)
        }
        try checks.noReceivingRows(h)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func projectedCharge(_ fixture: SharedMediaNativeReceivingTestFixture) throws -> Int64 {
        let prepared = try SharedMediaNativeReceivingIntent.Prepared(fixture.request)
        let metadata = try fixture.metadata(), header = SharedMediaNativeReceivingTestFixture.maximumHeader(prepared)
        // Uncapped measurements only; the persisted owner still enforces the
        // production maximum across current, received and abandoned branches.
        return try max(metadata + Int64(prepared.encoded().count),
            SharedMediaNativeReceivingReservation.successor(prepared,
                header: header, currentMetadata: metadata, pairStates: fixture.states),
            SharedMediaNativeReceivingReservation.abandonedSuccessor(prepared,
                header: header, currentMetadata: metadata, pairStates: fixture.states))
    }

    private func boundaryContexts(excess: Int64) -> [ObservationContext] {
        // Four fields of 3,021 preserved control scalars plus 11/12 ASCII
        // characters measure 1,048,576 / 1,048,577 bytes respectively. These
        // fixed shapes replace the exhausted multi-thousand-probe search.
        // No synthetic liability, changed limit or extra metadata save is used.
        (0..<4).map { field in
            .init(freeText: String(repeating: "\u{0001}", count: 3_021) +
                (field == 3 ? String(repeating: "a", count: 11 + Int(excess)) : ""))
        }
    }
}

extension SharedMediaNativeReceivingStagingTests {
    @Test func oversizedReceivingSuccessorPreservesTheRealPersistedDraft() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: 2)
        let contexts = (0..<4).map { _ in ObservationContext(freeText: String(repeating: "\"", count: 8_000)) }
        let edit = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: contexts)
        _ = try await owner.saveAppMetadata(edit)
        let before = try facts(h), revision = try inventory(h).revision
        await #expect(throws: SharedMediaStorageFailure.capacity) {
            _ = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: pairIDs(request))
        }
        #expect(try facts(h) == before)
        #expect(try inventory(h).revision == revision)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaReceivingIntentRecord>()) == 0)
        try noReceivingRows(h)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func cancellationWhileWaitingOnSavedIdentityCannotChangeTheSlot() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let ids = try pairIDs(request)
        let saved = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        let coordinator = ScanInferencePersistenceCoordinator.shared
        let held = await coordinator.acquireAll(scanIds: [saved.queueID.uuidString, saved.observationID.uuidString])
        let task = Task { try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids) }
        let first = held[0], deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await coordinator.hasWaitingWriter(scanId: first)), ContinuousClock.now < deadline { await Task.yield() }
        #expect(await coordinator.hasWaitingWriter(scanId: first))
        task.cancel(); await coordinator.releaseAll(scanIds: held)
        await #expect(throws: (any Error).self) { _ = try await task.value }
        let recovered = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        #expect(try recovered.encoded() == saved.encoded())
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        await #expect(throws: (any Error).self) {
            _ = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        }
    }

    @Test func preparedHeadroomIsChargedOnceAndImmediateBytesAreSeparate() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let ids = try pairIDs(request), c = h.context()
        let inventory = try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let before = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory, ownerID: h.ownerID, format: .appV2)
        let prepared = try SharedMediaNativeReceivingTestFixture.copy(SharedMediaNativeReceivingIntent.Prepared(request),
            changes: ["format": "nativeReceivingIntentV2", "version": 2, "intentRevision": 0])
        let states = try SharedMediaNativeReceivingIntentGraph.currentCohort(prepared, context: c, inventory: inventory)
        let projection = try SharedMediaNativeReceivingReservation.maximum(prepared,
            currentMetadata: #require(before.metadataByPackage[h.packageID]), pairStates: states)
        // IDs have fixed encoded widths. Allow 1 KiB for timestamp-digit changes
        // between the descriptive fixture and owner-minted staging identities.
        let allowance: Int64 = 1_024
        let immediate = Int64(try prepared.encoded().count)
        let available = minimumAvailable(before.totals) + projection.reserved + immediate + allowance
        #expect(projection.reserved > allowance)
        try owner.setMetadataFault(nil, availableBytes: available)
        let saved = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        let afterContext = h.context(), afterInventory = try #require(try afterContext.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let after = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: afterContext,
            inventory: afterInventory, ownerID: h.ownerID, format: .appV2)
        let actualProjection = try SharedMediaNativeReceivingReservation.maximum(saved,
            currentMetadata: #require(before.metadataByPackage[h.packageID]), pairStates: states)
        #expect(after.metadataByPackage[h.packageID] == actualProjection.charged)
        #expect(minimumAvailable(after.totals) - minimumAvailable(before.totals) == actualProjection.reserved)
        let threshold = minimumAvailable(after.totals) + Int64(try saved.encoded().count)
        #expect(throws: Never.self) { try after.totals.checkAvailable(threshold, additionalReservation: Int64(saved.encoded().count)) }
        #expect(throws: (any Error).self) { try after.totals.checkAvailable(threshold - 1, additionalReservation: Int64(saved.encoded().count)) }
        // This available space cannot satisfy the old duplicated-headroom formula.
        #expect(throws: (any Error).self) {
            try after.totals.checkAvailable(available,
                additionalReservation: Int64(saved.encoded().count) + actualProjection.reserved)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func malformedForeignAndPartialSlotsCannotDisappearFromAudit() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let saved = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: pairIDs(request))
        let bytes = try saved.encoded()
        for fault in ["owner", "inventory", "generation", "draft", "operation", "cursor", "phase", "revision",
                      "version", "digest", "bytes", "result", "resultDigest"] {
            let c = h.context(), row = try #require(try c.fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
            switch fault {
            case "owner": row.ownerID = UUID()
            case "inventory": row.inventoryID = UUID()
            case "generation": row.inventoryGeneration = UUID()
            case "draft": row.draftGeneration = UUID()
            case "operation": row.operationID = UUID()
            case "cursor": row.id = UUID() // A changed key leaves its private cursor inconsistent.
            case "phase": row.phaseRaw = "received"
            case "revision": row.revision = 1
            case "version": row.schemaVersion = 1
            case "digest": row.preparedSHA256 = String(repeating: "0", count: 64)
            case "bytes": row.preparedData = nil
            case "result": row.resultData = Data()
            default: row.resultSHA256 = String(repeating: "0", count: 64)
            }
            try c.save()
            await #expect(throws: (any Error).self) { _ = try await owner.inspectApp() }
            await #expect(throws: (any Error).self) { _ = try await owner.discoverAppReceivingIntent(packageID: h.packageID) }
            row.ownerID = saved.profile.ownerID; row.inventoryID = saved.profile.inventoryID
            row.inventoryGeneration = saved.profile.generation; row.draftGeneration = saved.package.generation
            row.operationID = saved.operationID; row.id = saved.package.id
            row.phaseRaw = "prepared"; row.revision = 0; row.schemaVersion = 2
            row.preparedData = bytes; row.preparedSHA256 = SharedMediaAcquisitionEncoding.digest(bytes)
            row.resultData = nil; row.resultSHA256 = nil
            try c.save()
            _ = try await owner.inspectApp()
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func queueHistoryAndEventAliasesBlockPreparedRecovery() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let saved = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: pairIDs(request))
        let queueID = saved.queueID.uuidString.uppercased(), observationID = saved.observationID.uuidString.uppercased()
        for fault in ["queue", "job", "event", "scan", "analysis"] {
            let c = h.context()
            switch fault {
            case "queue": c.insert(OfflineQueuedScan(id: queueID))
            case "job": c.insert(OfflineJobRecord(id: "scan-ingestion:" + queueID, kind: .scanIngestion))
            case "event": c.insert(OfflineQueueEvent(id: saved.eventID.uuidString.uppercased(), kind: .queued))
            case "scan": c.insert(LocalScanRecord(id: observationID, speciesId: "synthetic",
                scientificName: "Synthetic fixture", commonName: "Synthetic fixture"))
            default: c.insert(try LocalAnalysisRecord(analysisID: UUID(), observationID: observationID,
                ownerAccountID: h.ownerID, completedAt: Date(), resultSnapshotData: Data("{}".utf8)))
            }
            let inserted = c.insertedModelsArray
            try c.save()
            await #expect(throws: (any Error).self) { _ = try await owner.inspectApp() }
            for row in inserted { c.delete(row) }
            try c.save()
            _ = try await owner.inspectApp()
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["file", "package", "member", "inventory"])
    func finalSealChangesRejectStagingWithoutIntent(_ fault: String) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let ids = try pairIDs(request)
        var reached = false
        try owner.setMetadataFault { point in
            guard point == .beforeSave else { return }; reached = true
            if fault == "file" {
                let cohort = try SharedMediaNativeFrozenCohort.decode(request.freeze.commit.cohort.bytes)
                let original = try SharedMediaNativeDerivativeIntent.decode(#require(cohort.entries.first).intent.bytes).preparation.original
                let path = h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(original.token)
                let bytes = try Data(contentsOf: path)
                try FileManager.default.removeItem(at: path); try bytes.write(to: path)
            } else {
                let c = h.context()
                if fault == "package" { try h.package(in: c).revision += 1 }
                else if fault == "member" { try #require(try c.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first).revision += 1 }
                else { try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first).revision += 1 }
                try c.save()
            }
        }
        await #expect(throws: (any Error).self) {
            _ = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        }
        #expect(reached)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaReceivingIntentRecord>()) == 0)
        #expect(try h.package().supportingContextData == request.package.envelope)
        try noReceivingRows(h)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func minimumAvailable(_ totals: SharedMediaStoragePolicy.Totals) -> Int64 {
        var lower: Int64 = 0, upper: Int64 = 4 * 1_024 * 1_024 * 1_024
        while lower < upper {
            let mid = lower + (upper - lower) / 2
            if (try? totals.checkAvailable(mid)) != nil { upper = mid } else { lower = mid + 1 }
        }
        return lower
    }
}
