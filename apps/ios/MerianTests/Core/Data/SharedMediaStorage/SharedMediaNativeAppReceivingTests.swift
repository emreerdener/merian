import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Atomic inactive native photo receiving", .serialized)
@MainActor
struct SharedMediaNativeAppReceivingTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    @Test(arguments: [false, true])
    func emptyProfileReachesHeldReceivingAndColdDiscovery(_ withText: Bool) async throws {
        // Store.init creates only the disk-backed container and control parent.
        // Do not call Store.open: that helper inserts synthetic existing drafts.
        let h = try Store(), account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime)
        let initial = h.context()
        #expect(try initial.fetchCount(FetchDescriptor<PhotoPreparationRecord>()) == 0)
        #expect(try initial.fetchCount(FetchDescriptor<SharedMediaPendingMembershipRecord>()) == 0)
        #expect(try initial.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 0)
        let bootstrapDrain = SharedMediaNativeOriginalDrain()
        let bootstrap = try SharedMediaNativeOriginalOwner.appInitialization(account: account, drain: bootstrapDrain)
        _ = try await bootstrap.initializeApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID)
        try #require(await bootstrapDrain.shutdown())
        let drain = SharedMediaNativeOriginalDrain()
        let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: account, drain: drain)
        let empty = try await owner.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID)
        #expect(empty.pendingPackages == 0 && empty.consumers == 0 && empty.receipts == 0 && empty.allocations == 0)

        let bytes = PhotoPreparationTestHarness.image()
        var pairs: [UUID] = [], originalFiles: [URL] = []
        for ordinal in 0..<2 {
            let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft,
                ordinal: Int64(ordinal), kind: .picker)
            let acquired = try await owner.acquireAppOriginal(request) { bytes }
            let original = PhotoOriginalReference(ownerID: h.ownerID, packageID: h.packageID,
                referenceID: request.referenceID, assetID: request.assetID, assetGeneration: request.assetGeneration,
                draftGeneration: h.draft, referenceRevision: acquired.referenceRevision)
            originalFiles.append(h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(request.finalToken))
            let ready = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe)
            pairs.append(try ready.intent().pairID)
        }
        let contexts: [ObservationContext] = withText ? [.init(freeText: "  Exact supporting text\nwith spacing.  ")] : []
        let metadata = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: contexts)
        _ = try await owner.saveAppMetadata(metadata)
        try SharedMediaNativeReceivingStagingTests().noReceivingRows(h)
        let prepared = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: pairs)
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        #expect(try frozen.entries.map { try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes).pairID } == pairs)
        let supporting: SharedMediaNativeFrozenSupporting = try SharedMediaAcquisitionEncoding.decode(
            frozen.supportingBytes, maximum: Int(PhotoPreparationPolicy.metadata))
        #expect(supporting.contexts.map(\.freeText) == contexts.map(\.freeText))
        let cohort = try await owner.receiveAppPrepared(prepared)
        let before = try await owner.inspectApp()
        #expect(before.pendingPackages == 1 && before.consumers == 1 && before.receipts == 2)
        let saved = try #require(try await owner.discoverAppReceivingSlot(packageID: h.packageID))
        let envelope = try h.package().supportingContextData
        for file in originalFiles { #expect(try Data(contentsOf: file) == bytes) }
        let rows = h.context()
        #expect(try rows.fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.queueNeedsAttention) == [true])
        #expect(try rows.fetch(FetchDescriptor<OfflineJobRecord>()).map(\.status) == [.needsAttention])
        try #require(await drain.shutdown())

        // This helper constructs a distinct ModelContainer against the same store.
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        let coldSlot = try #require(try await cold.discoverAppReceivingSlot(packageID: h.packageID))
        guard case .received(let recovered, _, let transaction) = try SharedMediaNativeReceivingSlot.decode(coldSlot, profile: prepared.profile) else {
            Issue.record("Expected the exact received slot after cold reopen")
            _ = await cold.invalidateAndAwaitForAccountTransition()
            return
        }
        #expect(coldSlot == saved)
        #expect(transaction.cohort == cohort)
        // A genuinely fresh presentation discovers identity without retaining
        // the original selection, snapshot or submission-session handles.
        let recovery = CaptureNativeRecoveryModel(ownerID: h.ownerID,
            isCurrent: { true }, discover: { try await cold.discoverAppReceivedCandidates() })
        try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        await recovery.open()
        guard case .unselected(let candidates) = recovery.state else {
            Issue.record("Expected local received identity after restart")
            _ = await cold.invalidateAndAwaitForAccountTransition(); return
        }
        let candidate = try #require(candidates.first)
        #expect(candidates.count == 1 && candidate.packageID == saved.id)
        #expect(candidate.operationID == saved.operationID && candidate.draftGeneration == saved.draftGeneration)
        #expect(candidate.preparedSHA256 == saved.preparedSHA256 && candidate.receivedSHA256 == saved.resultSHA256)
        await recovery.select(candidate)
        #expect(recovery.state == .holding(candidate))
        await recovery.refresh()
        #expect(recovery.state == .holding(candidate))
        recovery.close()
        #expect(recovery.state == .closed)
        #expect(try await cold.discoverAppReceivingSlot(packageID: h.packageID) == saved)
        // A received slot must never be presented as fresh prepared work.
        await #expect(throws: (any Error).self) { _ = try await cold.discoverAppReceivingIntent(packageID: h.packageID) }
        #expect(try recovered.encoded() == prepared.encoded())
        try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        #expect(try await cold.receiveAppPrepared(recovered) == cohort)
        #expect(try await cold.discoverAppReceivingSlot(packageID: h.packageID) == saved)
        #expect(try await cold.inspectApp() == before)
        #expect(try h.package().supportingContextData == envelope)
        for file in originalFiles { #expect(try Data(contentsOf: file) == bytes) }
        try #require(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [1, 2])
    func completeSetAndColdExactRecoveryNeverSaveTwice(_ count: Int) async throws {
        let (h, owner, r) = try await fixture(count: count, staged: true)
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        #expect(try await owner.receiveAppPhotos(r) == r.cohort)
        #expect(try await owner.receiveAppPhotos(r) == r.cohort)
        #expect(saves == 1)
        try verify(h, r)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        #expect(try await cold.receiveAppPhotos(r) == r.cohort)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func laterUnrelatedAcquisitionDoesNotInvalidateExactRecovery() async throws {
        let (h, owner, r) = try await fixture(staged: true)
        _ = try await owner.receiveAppPhotos(r)
        let other = UUID(), draft = UUID()
        let acquisition = try await owner.prepareAppOriginal(packageID: other, draftGeneration: draft, ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireAppOriginal(acquisition) { bytes }
        let before = try h.package(other).supportingContextData
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        #expect(try await cold.receiveAppPhotos(r) == r.cohort)
        #expect(try h.package(other).supportingContextData == before)
        try verify(h, r)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["before", "after", "readback"])
    func acknowledgementFaultNeverCreatesHalfASetOrRepeatsSave(_ fault: String) async throws {
        let (h, owner, r) = try await fixture(staged: true)
        var saves = 0, saved = false
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1; if fault == "before" { throw SharedMediaStorageFailure.unavailable } }
            if $0 == .afterSave { saved = true; if fault == "after" { throw SharedMediaStorageFailure.unavailable } }
            if $0 == .beforeReadback && saved && fault == "readback" { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "after" { #expect(try await owner.receiveAppPhotos(r) == r.cohort) }
        else { await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPhotos(r) } }
        #expect(saves == 1)
        if fault == "before" { try unchanged(h, r) } else { try verify(h, r) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        if fault != "before" {
            let cold = try await reopen(h)
            try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
            #expect(try await cold.receiveAppPhotos(r) == r.cohort)
            #expect(await cold.invalidateAndAwaitForAccountTransition())
        }
    }

    @Test(arguments: ["consumer", "queue", "job", "event", "queueMetadata", "jobMetadata", "eventMetadata", "consumerIdentity"])
    func partialOrChangedSavedSetCannotRecoverOrRemint(_ fault: String) async throws {
        let (h, owner, r) = try await fixture(staged: true)
        _ = try await owner.receiveAppPhotos(r)
        let c = h.context(), rows = try #require(try SharedMediaNativeReceivingRows.read(r, in: c, absent: false))
        switch fault {
        case "consumer": c.delete(rows.consumer)
        case "queue": c.delete(rows.queue)
        case "job": c.delete(rows.job)
        case "event": c.delete(rows.event)
        case "queueMetadata": rows.queue.fieldNotes = "unexpected"
        case "jobMetadata": rows.job.metadataJSON = "{}"
        case "eventMetadata": rows.event.metadataJSON = "{}"
        default: rows.consumer.observationID = UUID().uuidString.lowercased()
        }
        try c.save()
        var saves = 0; try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPhotos(r) }
        #expect(saves == 0)
        #expect(try h.package().supportingContextData == r.frozenPackage().envelope)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["queue", "observation", "job", "event"])
    func freshAliasesAndReverseJoinsBlockInsertion(_ fault: String) async throws {
        let (h, owner, r) = try await fixture(staged: true)
        let c = h.context()
        switch fault {
        case "queue": c.insert(OfflineQueuedScan(id: r.cohort.originQueueID.uppercased()))
        case "observation": c.insert(OfflineQueuedScan(id: r.cohort.observationID.uppercased()))
        case "job": c.insert(OfflineJobRecord(id: "scan-ingestion:" + r.cohort.originQueueID.uppercased(), kind: .scanIngestion))
        default: c.insert(OfflineQueueEvent(id: r.eventID.uppercased(), kind: .queued))
        }
        try c.save()
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPhotos(r) }
        #expect(try h.package().supportingContextData == r.package.envelope)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaConsumerRecord>()) == 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["original", "output", "member", "package", "inventory", "reference", "edge", "counter"])
    func finalSealsRejectChangedFilesAndDurableFacts(_ fault: String) async throws {
        let (h, owner, r) = try await fixture(staged: true)
        var reached = false
        try owner.setMetadataFault { point in
            guard point == .beforeSave else { return }; reached = true
            if fault == "original" || fault == "output" {
                let cohort = try SharedMediaNativeFrozenCohort.decode(r.freeze.commit.cohort.bytes)
                let intent = try SharedMediaNativeDerivativeIntent.decode(#require(cohort.entries.first).intent.bytes)
                let assetID = intent.ai.assetID
                let output = try #require(try h.context().fetch(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })).first)
                let token = fault == "original" ? intent.preparation.original.token : output.fileToken
                let path = h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(token)
                let bytes = try Data(contentsOf: path); try FileManager.default.removeItem(at: path); try bytes.write(to: path)
            } else {
                let c = h.context()
                if fault == "package" { try h.package(in: c).revision += 1 }
                else if fault == "inventory" { try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first).revision += 1 }
                else if fault == "member" { try #require(try c.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first).revision += 1 }
                else {
                    let cohort = try SharedMediaNativeFrozenCohort.decode(r.freeze.commit.cohort.bytes)
                    let original = try SharedMediaNativeDerivativeIntent.decode(#require(cohort.entries.first).intent.bytes).preparation.original
                    let assetID = original.reference.assetID, referenceID = original.reference.referenceID
                    if fault == "counter" { try #require(try c.fetch(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID })).first).liveCount += 1 }
                    else if fault == "edge" { try #require(try c.fetch(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID })).first).revision += 1 }
                    else { try #require(try c.fetch(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID })).first).revision += 1 }
                }
                try c.save()
            }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPhotos(r) }
        #expect(reached); try unchanged(h, r, revision: fault == "package" ? 1 : 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func existingReceivingAndOrdinaryRowsArePreserved() async throws {
        let (h, owner, r) = try await fixture(receiving: true, staged: true)
        let before = try h.context().fetch(FetchDescriptor<SharedMediaConsumerRecord>()).map { SharedMediaNativeAppMetadataFacts.Consumer($0) }
        let ordinaryID = UUID().uuidString, c = h.context()
        c.insert(OfflineQueuedScan(id: ordinaryID, fieldNotes: "keep ordinary draft")); try c.save()
        _ = try await owner.receiveAppPhotos(r)
        let after = try h.context().fetch(FetchDescriptor<SharedMediaConsumerRecord>()).filter { $0.id != r.cohort.bindingID }.map { SharedMediaNativeAppMetadataFacts.Consumer($0) }
        #expect(after == before)
        #expect(try h.context().fetch(FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == ordinaryID })).first?.fieldNotes == "keep ordinary draft")
        #expect(try h.package(h.ordinaryID).supportingContextData == Data("ordinary-draft".utf8))
        try verify(h, r); #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func queueAndMetadataIndependentlyDenyLegacyExecution() async throws {
        let (h, owner, r) = try await fixture(staged: true); _ = try await owner.receiveAppPhotos(r)
        let c = h.context(), rows = try #require(try SharedMediaNativeReceivingRows.read(r, in: c, absent: false))
        #expect(!rows.queue.permitsOrdinaryInference)
        #expect(!SharedMediaLegacyQueueAccess.permitsMetadata(rows.job.metadataJSON))
        #expect(try !SharedMediaLegacyQueueAccess.permits(c, scanID: r.cohort.originQueueID))
        #expect(throws: (any Error).self) {
            try SharedMediaLegacyQueueAccess.requireJobMutation(c, id: r.jobID, kind: .scanIngestion,
                subjectID: r.cohort.originQueueID, metadata: r.metadata, existing: rows.job)
        }
        rows.queue.mediaAuthorityRaw = "legacy"; #expect(!rows.queue.permitsOrdinaryInference)
        rows.queue.mediaAuthorityRaw = "sharedDirectNativeReceivingV1"; rows.queue.sharedMediaConsumerID = nil
        #expect(!rows.queue.permitsOrdinaryInference); c.rollback()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func cancelledCoordinatorWaitReleasesLocksWithoutAdmission() async throws {
        let (h, owner, r) = try await fixture(staged: true), coordinator = ScanInferencePersistenceCoordinator.shared
        let held = await coordinator.acquireAll(scanIds: [r.cohort.originQueueID, r.cohort.observationID])
        let task = Task { try await owner.receiveAppPhotos(r) }
        let first = held[0]
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await coordinator.hasWaitingWriter(scanId: first)), ContinuousClock.now < deadline { await Task.yield() }
        let waiting = await coordinator.hasWaitingWriter(scanId: first)
        #expect(waiting)
        task.cancel(); await coordinator.releaseAll(scanIds: held)
        await #expect(throws: (any Error).self) { _ = try await task.value }
        try unchanged(h, r)
        // Reacquisition proves both locks were released, not just the first.
        #expect(try await owner.receiveAppPhotos(r) == r.cohort)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func invalidatedOwnerCannotAdmitSavedIntent() async throws {
        let (h, owner, r) = try await fixture(staged: true)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPhotos(r) }
        try unchanged(h, r)
    }

    func fixture(count: Int = 1, receiving: Bool = false, staged: Bool = false, foreignOriginal: Bool = false,
                 temporaryStore: Bool = false, fenceBootstrap: Bool = false) async throws -> (Store, SharedMediaNativeOriginalOwner, SharedMediaNativeAppReceivingRequest) {
        // Temporary placement need not seed an unrelated historical V1 graph.
        // The process control uses the existing ordinary P2 path only.
        let h = try Store(receiving: receiving || temporaryStore, fenceBootstrap: fenceBootstrap)
        let owner = try await (receiving ? h.openWithReceivingConsumer().0 : h.open())
        if foreignOriginal {
            guard count == 1, !receiving else { throw SharedMediaStorageFailure.conflict }
            // Remove only the synthetic empty seed, before any original exists.
            // The real sharing operation requires a previously absent destination.
            let c = h.context(), packageID = h.packageID
            c.delete(try h.package(in: c))
            c.delete(try SharedMediaNativePairPlanGraph.one(c,
                FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID })))
            try c.save()
        } else {
            let metadata = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: [.init(freeText: "Exact submitted supporting description")])
            _ = try await owner.saveAppMetadata(metadata)
        }
        var pairs: [UUID] = []
        for ordinal in 0..<count {
            let sourcePackage = foreignOriginal ? UUID() : h.packageID
            let request = try await owner.prepareAppOriginal(packageID: sourcePackage, draftGeneration: h.draft, ordinal: Int64(ordinal), kind: .picker)
            let data = PhotoPreparationTestHarness.image(), acquired = try await owner.acquireAppOriginal(request) { data }
            var original = PhotoOriginalReference(ownerID: h.ownerID, packageID: sourcePackage, referenceID: request.referenceID,
                assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: h.draft, referenceRevision: acquired.referenceRevision)
            if foreignOriginal {
                let share = try await owner.prepareAppOriginalShare(original, packageID: h.packageID, draftGeneration: h.draft)
                original = try await owner.shareAppOriginal(share)
                let metadata = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft,
                    contexts: [.init(freeText: "Exact submitted supporting description")])
                _ = try await owner.saveAppMetadata(metadata)
            }
            let ready = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe)
            pairs.append(try ready.intent().pairID)
        }
        let request = try await owner.appReceivingRequest(packageID: h.packageID, pairIDs: pairs, operationID: UUID(),
            queueID: UUID(), observationID: UUID(), bindingID: UUID(), generation: UUID(), eventID: UUID(), timestamp: Date(timeIntervalSince1970: 1_700_000_000))
        if staged {
            let prepared = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: pairs)
            let inventory = try SharedMediaNativeAppMetadataFacts.successor(request.header)
            return (h, owner, .init(try prepared.descriptorForTransaction(header: inventory)))
        }
        return (h, owner, request)
    }
    private func verify(_ h: Store, _ r: SharedMediaNativeAppReceivingRequest) throws {
        let c = h.context(), rows = try #require(try SharedMediaNativeReceivingRows.read(r, in: c, absent: false))
        #expect(try SharedMediaNativeConsumerGraph.validateScoped(rows.consumer, context: c, format: .appV2) == r.cohort)
        let inventory = try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory, ownerID: h.ownerID, format: .appV2)
        let packageID = r.package.id
        let member = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        #expect((budget.metadataByPackage[packageID] ?? 0) >= Int64(rows.consumer.cohortData.count))
        #expect(try h.package(packageID).supportingContextData == r.frozenPackage().envelope)
        #expect(member.membersData == r.member.bytes)
    }
    private func unchanged(_ h: Store, _ r: SharedMediaNativeAppReceivingRequest, revision: Int64 = 0) throws {
        #expect(try h.package().supportingContextData == r.package.envelope)
        #expect(try h.package().revision == r.package.revision + revision)
        #expect(try h.context().fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try h.context().fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        #expect(try h.context().fetchCount(FetchDescriptor<OfflineQueueEvent>()) == 0)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaConsumerRecord>()) == 0)
    }
    private func reopen(_ h: Store) async throws -> SharedMediaNativeOriginalOwner {
        try await SharedMediaNativeReceivingStagingTests().reopen(h)
    }
}

extension SharedMediaNativeAppReceivingTests {
    /// Historical fixture only. This does not exercise or authorize fresh V1
    /// admission; the production old entry point is now exact-recovery-only.
    func seedLegacyReceived(_ h: Store, _ request: SharedMediaNativeAppReceivingRequest) throws {
        let c = h.context(), package = try h.package(in: c), frozen = try request.frozenPackage()
        package.supportingContextData = frozen.envelope; package.phaseRaw = frozen.phase; package.revision = frozen.revision
        let inventory = try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        inventory.revision = try request.freeze.commit.inventoryRevision
        _ = try SharedMediaNativeReceivingRows.insert(request, in: c)
        try c.save()
    }

    @Test func legacyUnstagedRequestCannotAdmitButHistoricalCompleteSetCanRecover() async throws {
        let (h, owner, request) = try await fixture()
        let before = try SharedMediaNativeReceivingStagingTests().facts(h)
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPhotos(request) }
        #expect(try SharedMediaNativeReceivingStagingTests().facts(h) == before)
        try SharedMediaNativeReceivingStagingTests().noReceivingRows(h)
        try seedLegacyReceived(h, request)
        try owner.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        #expect(try await owner.receiveAppPhotos(request) == request.cohort)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        #expect(try await cold.receiveAppPhotos(request) == request.cohort)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
}
