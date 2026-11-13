import Foundation
import os
import SwiftData
import Testing
@testable import Merian

private final class InitialBindingFixtureAnchor: NSObject {}

@Suite("Original server facts stay closed", .serialized)
@MainActor
struct SharedMediaNativeInitialBindingFoundationTests {
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    typealias Fixture = SharedMediaNativeReleaseLiveFixture
    typealias Intent = SharedMediaNativeReceivingIntent
    private var variants: [(Data?, String?)] {
        [(Data(), nil), (nil, ""), (Data([0, 1, 255]), String(repeating: "a", count: 64))]
    }

    @Test(.sharedProcessState(.offlineQueueManager)) func authenticatedStatusConnectionPinsAdmissionThenCompletionWithoutImport() async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let original = try stored(store), acknowledgement = try originalAcknowledgement(allocation)
        let admission = try InitialCompletionDocuments.CpmAdmission(acknowledgement: acknowledgement, original: .saved(allocation))
        let acquisition = try completionAcquisition(admission)
        let bytes = try completionWire(admission, acquisition: acquisition)
        let fixture = InitialPhotoAllocationTransportTests.Fixture(ownerID: prepared.profile.ownerID)
        defer { fixture.close() }
        let calls = OSAllocatedUnfairLock(initialState: [String]())
        fixture.mock.register(path: "/check-scan-status") { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let fields = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let recovery = try #require(fields["initial_recovery"] as? [String: Any])
            let phase = try #require(recovery["phase"] as? String)
            calls.withLock { $0.append(phase) }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, phase == "admission" ? acknowledgement : bytes)
        }
        let transport = NativeReceivedStatusTransport(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher)
        let pinned = try await owner.recoverAppInitialServerFacts(prepared, using: transport)
        #expect(pinned == acquisition.record)
        #expect(calls.withLock { $0 } == ["admission", "completion"])
        let expected = Row(completing: acquisition.record, from: Row(admitting: admission, from: original))
        #expect(try stored(store) == expected)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func originalServerFieldsRejectAllLegacyOwnersWithoutMutation(_ completion: Bool) async throws {
        let (store, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(staged: true)
        let prepared = try Intent.Prepared(request), id = store.packageID, inventoryID = store.inventoryID
        for received in [false, true] {
            if received { _ = try await owner.receiveAppPrepared(prepared) }
            for (data, hash) in variants {
                let c = store.context()
                let slot = try Fixture.one(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
                let original = Row(slot)
                if completion { slot.initialCompletionData = data; slot.initialCompletionSHA256 = hash }
                else { slot.initialAdmissionData = data; slot.initialAdmissionSHA256 = hash }
                try c.save()
                let blocked = Row(slot)
                #expect(blocked != original)
                #expect(throws: SharedMediaStorageFailure.closed) { try blocked.requireNoInitialAnalysis() }
                let raw = try SharedMediaNativeReleasePairRaw.fields(slot)
                #expect(raw[completion ? "initialCompletionData" : "initialAdmissionData"] == (try SharedMediaNativeReleasePairRaw.value(data)))
                #expect(raw[completion ? "initialCompletionSHA256" : "initialAdmissionSHA256"] == (try SharedMediaNativeReleasePairRaw.value(hash)))
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
                slot.initialAdmissionData = nil; slot.initialAdmissionSHA256 = nil
                slot.initialCompletionData = nil; slot.initialCompletionSHA256 = nil; try c.save()
                #expect(Row(slot) == original)
            }
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func typedAdmissionReadPreservesAllocationAndReservesCompletion() async throws {
        let (store, owner, p, allocation) = try await allocatedFixture()
        let c = store.context(), id = store.packageID, inventoryID = store.inventoryID
        let slot = try Fixture.one(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
        let inventory = try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let before = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory, ownerID: store.ownerID, format: .appV2)
        let acknowledgement = try originalAcknowledgement(allocation)
        // Seed only the local disposable fixture to inspect the reader independently.
        slot.initialAdmissionData = acknowledgement
        slot.initialAdmissionSHA256 = SharedMediaAcquisitionEncoding.digest(acknowledgement)
        inventory.revision += 1; try c.save()
        let saved = Row(slot)
        #expect(throws: SharedMediaStorageFailure.closed) {
            _ = try SharedMediaNativePhotoAllocationSnapshot.read(saved, inventory: inventory, context: c)
        }
        let typed = try SharedMediaNativePhotoAllocationSnapshot.readInitial(saved, inventory: inventory, context: c)
        let pin = try #require(typed.initialPin)
        #expect(pin.admission.acknowledgement == acknowledgement && pin.completion == nil)
        #expect(pin.remainingAdvances == 1 && pin.currentBytes == Int64(acknowledgement.count + 64))
        #expect(try pin.chargedBytes - pin.currentBytes == 197_533)
        let after = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory, ownerID: store.ownerID, format: .appV2)
        #expect(try #require(after.metadataByPackage[id]) - #require(before.metadataByPackage[id]) == pin.chargedBytes)
        #expect(try #require(after.receivedLiabilityByPackage[id]).current - #require(before.receivedLiabilityByPackage[id]).current == pin.currentBytes)
        #expect(try #require(after.receivedLiabilityByPackage[id]).reserved - #require(before.receivedLiabilityByPackage[id]).reserved == 197_533)
        let clean = try SharedMediaNativeReceivingCleanGraph.pending(c, inventory: inventory)
        #expect(try #require(clean[id]).executionAdvances == allocation.remainingAdvances + 1)
        let peers = try SharedMediaNativePhotoAllocationPeer.rows(c, profile: p.profile, preserving: nil).peers
        #expect(try SharedMediaNativePhotoAllocationPeer.pending(c, inventory: inventory, preserving: peers)[id]?.row == saved)
        for (data, sha) in [(Optional<Data>.none, saved.initialAdmissionSHA256),
                            (saved.initialAdmissionData, Optional<String>.none),
                            (saved.initialAdmissionData, Optional(String(repeating: "0", count: 64)))] {
            slot.initialAdmissionData = data; slot.initialAdmissionSHA256 = sha; try c.save()
            #expect(throws: (any Error).self) {
                _ = try SharedMediaNativeReceivingCleanGraph.pending(c, inventory: inventory)
            }
            slot.initialAdmissionData = saved.initialAdmissionData; slot.initialAdmissionSHA256 = saved.initialAdmissionSHA256; try c.save()
        }
        for (data, sha) in variants {
            slot.initialCompletionData = data; slot.initialCompletionSHA256 = sha; try c.save()
            #expect(throws: (any Error).self) {
                _ = try SharedMediaNativeReceivingCleanGraph.pending(c, inventory: inventory)
            }
            await #expect(throws: (any Error).self) {
                _ = try await owner.recoverAppInitialAdmission(p) { _, _ in
                    Issue.record("Malformed initial pair reached the original reader"); return acknowledgement
                }
            }
            slot.initialCompletionData = nil; slot.initialCompletionSHA256 = nil; try c.save()
        }
        var foreign = try #require(InitialAnalysisCanonical.parse(acknowledgement).object)
        foreign["owner_id"] = .string(UUID().uuidString.lowercased())
        slot.initialAdmissionData = try InitialAnalysisCanonical.encode(.object(foreign))
        slot.initialAdmissionSHA256 = SharedMediaAcquisitionEncoding.digest(try #require(slot.initialAdmissionData)); try c.save()
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeReceivingCleanGraph.pending(c, inventory: inventory)
        }
        slot.initialAdmissionData = saved.initialAdmissionData; slot.initialAdmissionSHA256 = saved.initialAdmissionSHA256; try c.save()
        let oversizedAdmission = Data(repeating: 65, count: 8193)
        slot.initialAdmissionData = oversizedAdmission
        slot.initialAdmissionSHA256 = SharedMediaAcquisitionEncoding.digest(oversizedAdmission); try c.save()
        #expect(throws: SharedMediaStorageFailure.closed) {
            _ = try SharedMediaNativePhotoAllocationSnapshot.readInitial(Row(slot), inventory: inventory, context: c)
        }
        slot.initialAdmissionData = saved.initialAdmissionData; slot.initialAdmissionSHA256 = saved.initialAdmissionSHA256
        let oversizedCompletion = Data(repeating: 65, count: try InitialCompletionDocuments.CpmRecoveryRecord.maximumBytes + 1)
        slot.initialCompletionData = oversizedCompletion
        slot.initialCompletionSHA256 = SharedMediaAcquisitionEncoding.digest(oversizedCompletion); try c.save()
        #expect(throws: SharedMediaStorageFailure.conflict) {
            _ = try SharedMediaNativePhotoAllocationSnapshot.readInitial(Row(slot), inventory: inventory, context: c)
        }
        slot.initialCompletionData = nil; slot.initialCompletionSHA256 = nil; try c.save()
        let dirty = store.context()
        let dirtySlot = try Fixture.one(dirty, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
        dirtySlot.initialCompletionData = Data()
        #expect(throws: (any Error).self) { try #require(peers[id]).requireUnchanged(dirty) }
        dirty.rollback(); #expect(!dirty.hasChanges)
        let check = store.context()
        let checkedSlot = try Fixture.one(check, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
        #expect(Row(checkedSlot) == saved && !check.hasChanges && !c.hasChanges)
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(c, inventory: inventory)
        let advances = try #require(witnesses[id]).remainingAdvances
        #expect(advances >= 1) // The still-pending completion pin must fit.
        let revision = inventory.revision
        inventory.revision = Int64.max - advances; try c.save()
        _ = try SharedMediaNativeReceivingCleanGraph.pending(c, inventory: inventory)
        inventory.revision += 1; try c.save()
        #expect(throws: (any Error).self) { _ = try SharedMediaNativeReceivingCleanGraph.pending(c, inventory: inventory) }
        inventory.revision = revision; try c.save()
        let completion = try completionRecord(pin.admission)
        slot.initialCompletionData = completion.bytes
        slot.initialCompletionSHA256 = SharedMediaAcquisitionEncoding.digest(completion.bytes)
        inventory.revision += 1; try c.save()
        let completed = try SharedMediaNativePhotoAllocationSnapshot.readInitial(Row(slot), inventory: inventory, context: c)
        let completedPin = try #require(completed.initialPin)
        #expect(completedPin.completion == completion && completedPin.remainingAdvances == 0)
        #expect(try completedPin.chargedBytes == pin.chargedBytes)
        let finalBudget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory, ownerID: store.ownerID, format: .appV2)
        #expect(finalBudget.metadataByPackage[id] == after.metadataByPackage[id])
        #expect(try #require(finalBudget.receivedLiabilityByPackage[id]).current - #require(after.receivedLiabilityByPackage[id]).current == Int64(completion.bytes.count + 64))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func applicationPoststateOwnsScanConstructionAndExactMutationSet() async throws {
        typealias Proof = NativePhotoAllocationPoststate.Application
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let ack = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in ack })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        let c = store.context(), id = store.packageID, inventoryID = store.inventoryID
        let unrelated = ScanCollection(name: "Unrelated fixture collection")
        c.insert(unrelated); try c.save()
        let row = try Fixture.one(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
        let inventory = try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let original = Row(row), oldRevision = inventory.revision
        let before = try SharedMediaNativePhotoAllocationSnapshot.readInitial(original, inventory: inventory, context: c)
        let scalars = NativePhotoAllocationPoststate.ApplicationScalars(speciesID: "", timestamp: Date(timeIntervalSince1970: 1),
            captureDate: Date(timeIntervalSince1970: 1), fieldNotes: nil, contexts: [.init(freeText: " Exact fixture text ")])
        func proof() throws -> Proof {
            try Proof(before: before, row: row, inventory: inventory, scalars: scalars,
                acquisition: acquisition, context: c, availableBytes: { Int64.max })
        }
        let deletion = PendingCloudDeletionTask(scanId: prepared.observationID.uuidString)
        c.insert(deletion); try c.save()
        #expect(throws: SharedMediaStorageFailure.conflict) { try proof() }
        c.delete(deletion); try c.save()
        let rejected = try proof()
        try rejected.stage(c)
        try rejected.validate(c)
        // An unrelated new row after staging must not fit the exact write set.
        c.insert(ScanCollection(name: "Unexpected insertion"))
        #expect(throws: SharedMediaStorageFailure.conflict) { try rejected.validate(c) }
        c.rollback()
        #expect(try stored(store) == original && revision(store) == oldRevision)
        #expect(try c.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        let accepted = try proof()
        try accepted.stage(c)
        let inserted = try #require(c.insertedModelsArray.first as? LocalScanRecord)
        inserted.fieldNotes = "Unexpected mutation"
        #expect(throws: SharedMediaStorageFailure.conflict) { try accepted.validate(c) }
        inserted.fieldNotes = nil
        try accepted.validate(c)
        // Disposable fixture only: production save ownership remains unconnected.
        try c.save()
        let fresh = store.context()
        let savedInventory = try Fixture.one(fresh, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let savedRow = try Fixture.one(fresh, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
        let applied = try SharedMediaNativePhotoAllocationSnapshot.Applied.read(savedRow, inventory: savedInventory, context: fresh)
        #expect(applied.cohort == accepted.cohort && Row(savedRow) == original && savedInventory.revision == oldRevision + 1)
        #expect(try fresh.fetchCount(FetchDescriptor<ScanCollection>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<CapturedMediaEntry>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func retainedDisplayCompositionUsesExactBindingAndRejectsStalePublication() async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let ack = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in ack })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        _ = try #require(await owner.applyAppInitialResult(prepared) { _, _ in acquisition })
        let scanID = prepared.observationID.uuidString.lowercased(), binding = prepared.bindingID
        let resolved = try await owner.appReceivingQuery(SharedMediaNativeReceivingQuery.retainedInitial(
            observationID: prepared.observationID, bindingID: binding))
        #expect(try resolved.encoded() == prepared.encoded())
        let expected = try await owner.readRetainedAppPhotos(prepared, role: .display)
        let media = try await NativeInitialInsightMedia.read(scanID: scanID, bindingID: binding,
            container: store.container, owner: { owner }, isCurrent: { true })
        #expect(Array(media.items.prefix(expected.photos.count)) == expected.photos.map { .retainedDisplayImage(id: $0.pairID, data: $0.bytes) })
        #expect(media.liveImageData == nil && media.imagePathsForUpload.isEmpty)
        #expect(media.items.last == .description(ObservationContext(freeText: "Exact submitted supporting description")))
        let c = store.context(), scan = try Fixture.one(c, FetchDescriptor<LocalScanRecord>())
        #expect(scan.capturedMediaJSON == nil && scan.coverImagePath == nil)
        let unchanged = try revision(store)
        for changedObservation in [false, true] {
            await #expect(throws: (any Error).self) {
                _ = try await owner.appReceivingQuery(SharedMediaNativeReceivingQuery.retainedInitial(
                    observationID: changedObservation ? UUID() : prepared.observationID,
                    bindingID: changedObservation ? binding : UUID()))
            }
        }
        var current = true
        await #expect(throws: (any Error).self) {
            _ = try await NativeInitialInsightMedia.read(scanID: scanID, bindingID: binding,
                container: store.container, owner: { current = false; return owner }, isCurrent: { current })
        }
        await #expect(throws: (any Error).self) {
            _ = try await NativeInitialInsightMedia.read(scanID: scanID, bindingID: binding,
                container: store.container, owner: {
                    scan.sharedMediaConsumerID = UUID(); try c.save(); return owner
                }, isCurrent: { true })
        }
        scan.sharedMediaConsumerID = binding; try c.save()
        var publicationChecks = 0, published = false
        await #expect(throws: (any Error).self) {
            _ = try await NativeInitialInsightMedia.read(scanID: scanID, bindingID: binding,
                container: store.container, owner: { owner }, isCurrent: {
                    publicationChecks += 1
                    // Four checks bracket owner resolution, query and file read.
                    // Inject a queued deletion only after the file read returns.
                    if publicationChecks == 4 {
                        c.insert(PendingCloudDeletionTask(scanId: scanID))
                        do { try c.save() } catch { Issue.record(error); return false }
                    }
                    return true
                }, publish: { _ in published = true })
        }
        #expect(publicationChecks == 4 && !published)
        #expect(try revision(store) == unchanged)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func atomicApplicationPreservesOriginalAndLaterSelectionAcrossReplay() async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let ack = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in ack })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        let original = try stored(store), firstRevision = try revision(store)
        try owner.setMetadataFault(nil, availableBytes: 0)
        await #expect(throws: (any Error).self) {
            _ = try await owner.applyAppInitialResult(prepared) { _, _ in Issue.record("Capacity hold reacquired result"); return acquisition }
        }
        try owner.setMetadataFault(nil)
        #expect(try await owner.applyAppInitialResult(prepared) { _, validate in try validate(); return nil } == nil)
        let other = try completionAcquisition(admission, reasoning: "Different original result")
        await #expect(throws: (any Error).self) {
            _ = try await owner.applyAppInitialResult(prepared) { _, _ in other }
        }
        // A deletion that wins immediately before the atomic section must hold
        // application. Taking the same lock here also detects nested callbacks.
        try owner.setMetadataFault { boundary in
            if boundary == .beforeSave {
                try ConfirmedSpeciesReviewPersistence.transaction {
                    let context = store.context()
                    context.insert(PendingCloudDeletionTask(scanId: prepared.observationID.uuidString))
                    try context.save()
                }
            }
        }
        await #expect(throws: (any Error).self) {
            _ = try await owner.applyAppInitialResult(prepared) { _, _ in acquisition }
        }
        #expect(try stored(store) == original && revision(store) == firstRevision)
        let cleanup = store.context()
        #expect(try cleanup.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        let deletion = try Fixture.one(cleanup, FetchDescriptor<PendingCloudDeletionTask>())
        cleanup.delete(deletion); try cleanup.save()
        try owner.setMetadataFault { if $0 == .afterSave { throw SharedMediaStorageFailure.unavailable } }
        let applied = try #require(await owner.applyAppInitialResult(prepared) { current, validate in
            try validate(); #expect(current == admission); return acquisition
        })
        #expect(try stored(store) == original && revision(store) == firstRevision + 1)
        let context = store.context()
        let scan = try Fixture.one(context, FetchDescriptor<LocalScanRecord>())
        #expect(scan.id == prepared.observationID.uuidString.lowercased() && scan.speciesId.isEmpty)
        #expect(abs(scan.timestamp.timeIntervalSince1970 - 1_793_761_200.123456) < 0.0000005)
        #expect(scan.sharedMediaConsumerID == prepared.bindingID && scan.fieldNotes == nil)
        #expect(scan.selectedAnalysisID == nil && scan.analysisOwnerAccountID == nil)
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let supporting: SharedMediaNativeFrozenSupporting = try SharedMediaAcquisitionEncoding.decode(frozen.supportingBytes,
            maximum: Int(PhotoPreparationPolicy.metadata))
        let texts = try scan.observationContextsJSON?.map { try JSONDecoder().decode(ObservationContext.self, from: Data($0.utf8)).freeText }
        #expect(texts == supporting.contexts.map(\.freeText))
        let first = try #require(frozen.entries.first)
        let originalReference = try SharedMediaNativeDerivativeIntent.decode(first.intent.bytes).preparation.original.reference.referenceID
        let captured = supporting.presentation.first { $0.referenceID == originalReference }?.captureDate
            ?? Date(timeIntervalSinceReferenceDate: Double(bitPattern: prepared.timestampBits))
        #expect(scan.captureDate == captured)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
        let laterSelection = UUID().uuidString.lowercased()
        scan.fieldNotes = "Later user notes"; scan.selectedAnalysisID = laterSelection
        scan.analysisOwnerAccountID = prepared.profile.ownerID.uuidString.lowercased(); scan.observationStateRevision = 7
        try context.save()
        try owner.setMetadataFault { if $0 == .beforeSave { Issue.record("Applied replay must not save") } }
        #expect(try await owner.applyAppInitialResult(prepared) { _, _ in Issue.record("Applied replay reacquired result"); return nil } == applied)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(store)
        #expect(try await cold.applyAppInitialResult(prepared) { _, _ in Issue.record("Cold replay reacquired result"); return nil } == applied)
        let retained = try Fixture.one(store.context(), FetchDescriptor<LocalScanRecord>())
        #expect(retained.fieldNotes == "Later user notes" && retained.selectedAnalysisID == laterSelection && retained.observationStateRevision == 7)
        #expect(try stored(store) == original && revision(store) == firstRevision + 1)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["cancel", "account", "deletion"])
    func suspendedApplicationCannotCrossOriginalFence(_ fault: String) async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let ack = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in ack })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        let original = try stored(store), firstRevision = try revision(store)
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        let operation = Task {
            try await owner.applyAppInitialResult(prepared) { _, _ in
                await entered.open(); await release.wait(); return acquisition
            }
        }
        await entered.wait()
        var transition: Task<Bool, Never>?
        switch fault {
        case "cancel": operation.cancel()
        case "deletion":
            let context = store.context()
            context.insert(PendingCloudDeletionTask(scanId: prepared.observationID.uuidString)); try context.save()
        default:
            transition = Task { await owner.invalidateAndAwaitForAccountTransition() }
            while !owner.heldOriginalAdmissionClosedForTesting { await Task.yield() }
        }
        await release.open()
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        #expect(try stored(store) == original && revision(store) == firstRevision)
        #expect(try store.context().fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        if let transition { #expect(await transition.value) }
        else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
    }

    @Test func nativeHistoryAcknowledgementPreservesMediaAndLaterSelection() async throws {
        try await verifyHistoryAcknowledgement(advancedSelection: false)
    }

    @Test func advancedEnrollmentAcknowledgementPreservesOriginalAndLaterSelection() async throws {
        try await verifyHistoryAcknowledgement(advancedSelection: true)
    }

    @Test func retainedAISelectionFreezesHistoricalProvenanceAndCopiesChildOwnedInputs() async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let reply = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in reply })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        _ = try #require(await owner.applyAppInitialResult(prepared) { _, _ in acquisition })
        let baselineID = try await enrollInitialFixture(store, prepared: prepared, acquisition: acquisition, advancedSelection: true)
        _ = try #require(await owner.acknowledgeAppInitialHistory(prepared) { _, _ in acquisition })
        let source = try ObservationReanalysisSource.capture(observationID: prepared.observationID,
            analysisID: baselineID, ownerID: store.ownerID, container: store.container)
        #expect(source.photos.isEmpty && source.evidence.isEmpty)
        let account = ObservationHistoryCloudClient(begin: { expected in
            #expect(expected == store.ownerID)
            return AccountBoundWorkLease(id: UUID(), session: AuthTransitionSession(userID: expected, isAnonymous: false))
        }, isCurrent: { _ in true }, finish: { _ in }, fetch: { _ in throw ObservationHistoryError.unavailable })
        let loader = CaptureReanalysisEvidenceLoader(account: account, retainedOwner: { owner }, loadPhoto: { _, _, _ in
            Issue.record("Native AI input must never resolve a protected server reference"); throw MerianError.invalidResponse
        })
        let expected = try await owner.readRetainedAppPhotos(prepared, role: .ai)
        let input = try #require(await loader.retained(source: source, container: store.container, isCurrent: { true }))
        #expect(input.photos.map { $0.bytes } == expected.photos.map(\.bytes))
        #expect(input.photos.map { $0.photo.pairID } == expected.photos.map(\.pairID))
        #expect(throws: (any Error).self) { try input.selection([UUID()]) }
        let context = store.context(), scan = try Fixture.one(context, FetchDescriptor<LocalScanRecord>())
        let selectedID = try #require(scan.selectedAnalysisID.flatMap(UUID.init(uuidString:)))
        let otherSource = try ObservationReanalysisSource.capture(observationID: prepared.observationID,
            analysisID: selectedID, ownerID: store.ownerID, container: store.container)
        #expect(try await loader.retained(source: otherSource, container: store.container, isCurrent: { true }) == nil)
        let laterSelection = UUID().uuidString.lowercased()
        scan.selectedAnalysisID = laterSelection; scan.observationStateRevision = 9
        scan.fieldNotes = "Mutable parent text must not become submitted evidence"; try context.save()
        try input.validate(container: store.container)
        var current = true
        await #expect(throws: (any Error).self) {
            _ = try await ObservationReanalysisRetainedInput.read(source: source, container: store.container,
                owner: { current = false; return owner }, isCurrent: { current })
        }
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let producer = ObservationReanalysisProducer(files: .init(documents: root), ownership: .init(), account: account,
            loadOriginal: { _, _, _ in Issue.record("Retained input became a server original"); throw MerianError.invalidResponse })
        let editor = CaptureReanalysisEditor(source: source, container: store.container, account: account,
            loader: loader, producer: producer, isCurrent: { true }, requestSubmitted: { _ in }, requestCleanup: {})
        #expect(!editor.canContinue)
        await editor.loadSelection() // Continue wins scheduling before the view's discovery task.
        #expect(editor.phase == .choosing && editor.capture.isEmpty)
        await editor.loadRetainedOptions()
        #expect(editor.canContinue)
        #expect(editor.retainedPhotoIDs == expected.photos.map(\.pairID) && editor.selectedPhotoIDs.isEmpty)
        for id in editor.retainedPhotoIDs { editor.toggle(id) }
        await editor.loadSelection()
        #expect(editor.phase == .editing && editor.capture.images.count == expected.photos.count)
        #expect(editor.capture.observationContexts.map { $0.context.freeText } == ["Exact submitted supporting description"])
        let capture = editor.capture
        for (image, value) in zip(capture.images, input.photos) {
            #expect(image.compressedData == value.bytes && image.photoOriginalReference == nil)
            #expect(image.reanalysisProvenance == .retained(value.photo, edited: false))
            #expect(image.replacing(compressedData: image.compressedData).reanalysisProvenance == .retained(value.photo, edited: true))
            #expect(throws: (any Error).self) {
                try ObservationReanalysisPreparationPlan(source: source, choices: [.photo(.retained(value.photo, Data([0]), edited: false))])
            }
        }
        let session = CaptureReanalysisSession(source: source, generation: UUID())
        let deletion = PendingCloudDeletionTask(scanId: prepared.observationID.uuidString.lowercased())
        context.insert(deletion); try context.save()
        #expect(throws: (any Error).self) {
            try session.preparation(capture: capture, generation: session.generation, container: store.container)
        }
        #expect(session.plan == nil)
        context.delete(deletion); try context.save()
        let plan = try session.preparation(capture: capture, generation: session.generation, container: store.container)
        let originalJobs = try context.fetchCount(FetchDescriptor<OfflineJobRecord>())
        scan.sharedMediaConsumerID = UUID(); try context.save()
        await #expect(throws: (any Error).self) {
            _ = try await session.stage(capture: capture, generation: session.generation, container: store.container,
                producer: producer, action: .submit, isCurrent: { true })
        }
        #expect(try store.context().fetchCount(FetchDescriptor<OfflineJobRecord>()) == originalJobs)
        scan.sharedMediaConsumerID = prepared.bindingID; try context.save()
        let result = try await session.stage(capture: capture, generation: session.generation, container: store.container,
            producer: producer, action: .submit, isCurrent: { true })
        guard case let .submitted(submission) = result else { Issue.record("Expected a durable submitted child"); return }
        #expect(submission.draft.identity.sourceAnalysisID == baselineID && submission.draft.identity.analysisID == plan.analysisID)
        #expect(submission.draft.identity.analysisID != baselineID)
        for path in submission.draft.photoPaths { #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)) }
        let childJobCount = try store.context().fetchCount(FetchDescriptor<OfflineJobRecord>())
        // Once the exact draft/files are owned by the child, retry never needs a
        // fresh native read or current native binding. Source/account fences stay.
        scan.sharedMediaConsumerID = UUID(); try context.save()
        _ = try await session.stage(capture: capture, generation: session.generation, container: store.container,
            producer: producer, action: .submit, isCurrent: { true })
        #expect(try session.plan?.analysisID == plan.analysisID && store.context().fetchCount(FetchDescriptor<OfflineJobRecord>()) == childJobCount)
        scan.sharedMediaConsumerID = prepared.bindingID; try context.save()
        let saved = try Fixture.one(store.context(), FetchDescriptor<LocalScanRecord>())
        #expect(saved.selectedAnalysisID == laterSelection && saved.observationStateRevision == 9)
        #expect(try store.context().fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 2)
        editor.invalidate(); #expect(editor.retainedPhotoIDs.isEmpty && editor.capture.isEmpty)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func retainedPhotoChildRecoversOnceAndHistorySelectionUndoPreservesBothVersions() async throws {
        var phase = "applying original"
        defer { if phase != "complete" { print("Retained photo journey stopped: " + phase) } }
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let reply = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in reply })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        _ = try #require(await owner.applyAppInitialResult(prepared) { _, _ in acquisition })
        let displayed = try ObservationHistoryEnrollmentService.baseline(observation: prepared.observationID, container: store.container)
        #expect(displayed.isPristineNativeReview)
        phase = "enrolling original"
        let baselineID = try await enrollInitialFixture(store, prepared: prepared, acquisition: acquisition)
        phase = "acknowledging original"
        _ = try #require(await owner.acknowledgeAppInitialHistory(prepared) { _, _ in acquisition })
        phase = "reading acknowledged review"
        let enrolled = try ObservationHistoryStateSyncService.displayBaseline(observation: prepared.observationID, container: store.container)
        #expect(enrolled.retainsIdentification(of: displayed))
        let restoredClear = try ConfirmedSpeciesReview.restoring(enrolled.species)
        let clear = try #require(restoredClear)
        #expect(clear.revision == 0 && clear.identity == nil && clear.userReviewState == .unreviewed && enrolled.ai == nil)
        try await checkPreservedChild(store: store, owner: owner, prepared: prepared, baselineID: baselineID)
        phase = "complete"
    }

    func continueFreshPhotoInHistory(store: SharedMediaNativeAppMetadataTests.Store, owner: SharedMediaNativeOriginalOwner,
                                     prepared: Intent.Prepared, admission: InitialCompletionDocuments.CpmAdmission,
                                     expectedAI: [Data], expectedDescriptions: [String]) async throws {
        let candidate = try #require(try await owner.discoverAppReceivedCandidates().first { $0.profile == prepared.profile && $0.packageID == prepared.package.id })
        let acquisition = try completionAcquisition(admission)
        let baselineID = UUID()
        let association = try #require(try await CaptureNativeRecoveryModel.completeInitialHistory(candidate, owner: owner,
            isCurrent: { true }, readAdmission: { allocation, validate in
                try validate()
                _ = try InitialCompletionDocuments.CpmAdmission(acknowledgement: admission.acknowledgement, original: .saved(allocation))
                return admission.acknowledgement
            }, readCompletion: { original, validate in
                try validate()
                #expect(original == admission)
                return acquisition
            }, enroll: { observation in
                #expect(observation == prepared.observationID)
                _ = try await enrollInitialFixture(store, prepared: prepared, acquisition: acquisition, baselineID: baselineID)
            }))
        #expect(association.observationID == prepared.observationID && association.baselineAnalysisID == baselineID)
        try await checkPreservedChild(store: store, owner: owner, prepared: prepared, baselineID: baselineID,
                                      expectedAI: expectedAI, expectedDescriptions: expectedDescriptions)
    }

    private func checkPreservedChild(store: SharedMediaNativeAppMetadataTests.Store, owner: SharedMediaNativeOriginalOwner,
                                     prepared: Intent.Prepared, baselineID: UUID, expectedAI: [Data]? = nil,
                                     expectedDescriptions: [String]? = nil) async throws {
        var phase = "capturing original"
        defer { if phase != "complete" { print("Retained child journey stopped: " + phase) } }
        let source = try ObservationReanalysisSource.capture(observationID: prepared.observationID,
            analysisID: baselineID, ownerID: store.ownerID, container: store.container)
        let account = ObservationReanalysisProducerTests().account()
        let loader = CaptureReanalysisEvidenceLoader(account: account, retainedOwner: { owner })
        phase = "loading retained evidence"
        let input = try #require(await loader.retained(source: source, container: store.container, isCurrent: { true }))
        let originalMedia = input.photos.map { $0.bytes }
        if let expectedAI { #expect(originalMedia == expectedAI) }
        if let expectedDescriptions {
            #expect(input.descriptions.map { Data($0.utf8) } == expectedDescriptions.map { Data($0.utf8) })
        }
        let capture = try await loader.load(input, selected: Set(input.photos.map { $0.photo.pairID }),
            container: store.container, isCurrent: { true })
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ObservationReanalysisFileStore(documents: root)
        let producer = ObservationReanalysisProducer(files: files, ownership: .init(), account: account)
        let session = CaptureReanalysisSession(source: source, generation: UUID())
        phase = "submitting child"
        let staged = try await session.stage(capture: capture, generation: session.generation, container: store.container,
            producer: producer, action: .submit, isCurrent: { true })
        guard case let .submitted(submitted) = staged else { Issue.record("Expected submitted child"); return }
        let clock = Date(timeIntervalSince1970: 1_780_000_000)
        let advisory = ObservationReanalysisAdmission(account: account, preflight: { request, expectedOwner, validate in
            try validate(); #expect(expectedOwner == store.ownerID)
            #expect(request.analysisID == submitted.draft.identity.analysisID)
            return IdentificationDispatchAuthorization(recipient: .gemini, validate: validate)
        }, now: { clock })
        phase = "admitting child"
        let admitted = try await advisory.admit(submitted.draft, container: store.container, isCurrent: { true })
        let request = admitted.intent.request
        var (_, result) = try ObservationReanalysisResultTests().fixture()
        let body = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        for key in ["observation_id", "analysis_id", "source_analysis_id", "request_digest", "evidence_manifest"] { result[key] = body[key] }
        result["ordinal"] = 2
        var identification = try #require(result["result"] as? [String: Any])
        identification["scan_id"] = source.observationID.uuidString.lowercased(); result["result"] = identification
        let resultBytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        _ = try ObservationReanalysisResult.decode(resultBytes, matching: request)
        var phases: [String] = [], executed = false
        let dependencies = ObservationReanalysisExecutor.Dependencies(recover: { saved, validate in
            try validate(); #expect(saved.request.body == request.body); phases.append("recover")
            return executed ? resultBytes : nil
        }, authorize: { saved, validate in
            try validate(); #expect(saved == admitted.intent); phases.append("authorize")
            return IdentificationDispatchAuthorization(recipient: .gemini, validate: validate)
        }, read: { draft, validate in
            phases.append("read")
            return try await files.readPhotos(draft: draft, validateBeforeRead: validate, validateBeforeReturn: validate)
        }, upload: { upload, expectedOwner, validate in
            try validate(); #expect(expectedOwner == store.ownerID); phases.append("upload")
            let value = try upload.prepare()
            return .init(observationID: value.observationID, analysisID: value.analysisID, items: value.references)
        }, analyze: { saved, authorization in
            try authorization.validate(); #expect(saved == admitted.intent && !executed)
            phases.append("analyze"); executed = true
            throw URLError(.networkConnectionLost) // Server outcome exists, its reply is lost.
        })
        var executor = ObservationReanalysisExecutor(dependencies: dependencies, account: account, now: { clock })
        phase = "executing child"
        guard case .waiting = try await executor.execute(admitted, admission: .initial, container: store.container,
            isCurrent: { true }) else { Issue.record("Expected exact unresolved child"); return }
        let waiting = try ObservationReanalysisExecutionStore.read(admitted.intent.identity, container: store.container, isCurrent: { true })
        #expect(waiting.intent.request.body == request.body && waiting.dispatch != .ready)
        let next = try #require(waiting.nextRun); executor.now = { next }
        phase = "recovering child"
        guard case .completed = try await executor.execute(waiting, admission: .dueRetry, container: store.container,
            isCurrent: { true }) else { Issue.record("Expected recovered immutable result"); return }
        #expect(phases == ["recover", "authorize", "read", "upload", "analyze", "recover"])
        try await checkChildSelectionUndo(store: store, prepared: prepared, source: source,
            baselineID: baselineID, child: request.analysisID, resultBytes: resultBytes, account: account)
        phase = "rereading original media"
        let retained = try await owner.readRetainedAppPhotos(prepared, role: .ai)
        #expect(retained.photos.map(\.bytes) == originalMedia)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        phase = "complete"
    }

    @Test func initialHistorySubmitsFreshAudioChildAndRecoversWithoutReplacingSource() async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let acknowledgement = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in acknowledgement })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        _ = try #require(await owner.applyAppInitialResult(prepared) { _, _ in acquisition })
        let baselineID = try await enrollInitialFixture(store, prepared: prepared, acquisition: acquisition)
        _ = try #require(await owner.acknowledgeAppInitialHistory(prepared) { _, _ in acquisition })
        #expect(try NativeInitialHistoryBaseline.read(prepared, context: store.context())?.association.baselineAnalysisID == baselineID)
        let target = HistoricalReanalysisTarget(observationID: prepared.observationID, analysisID: baselineID, ownerID: store.ownerID)
        let source = try ObservationReanalysisSource.captureForAudio(observationID: prepared.observationID,
            analysisID: baselineID, ownerID: store.ownerID, container: store.container)
        #expect(source.audio == nil) // The initial baseline supplies identity, not the new WAV.
        let wav = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 64, sampleAt: { Int16($0) })
        let before = "  Fresh audio\u{FEFF}\n", after = "e\u{301} 🐾\u{0}"
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inputURL = root.appendingPathComponent("fresh.wav")
        try wav.write(to: inputURL)
        let account = ObservationReanalysisProducerTests().account()
        let queue = ObservationAudioExecutionOwner()
        let exits = AsyncStream<Void>.makeStream()
        defer { exits.continuation.finish() }
        var iterator = exits.stream.makeAsyncIterator()
        var audioSeed: ObservationAudioPreparationTests.Seed?
        var boundary: ObservationAudioExecutionServiceTests.Boundary?
        var outcomes: [ObservationAudioExecutionService.Outcome] = []
        var starts = 0, authorizations = 0
        let composition = PreparedHistoryReanalysisComposition(routes: AppRouteCoordinator(), cloud: account,
            currentOwner: { store.ownerID }, generation: { 1 }, sessionIsCurrent: { $0.userID == store.ownerID },
            preparationOwner: .init(), enrollmentOwner: .init(), containerIsCurrent: { $0 === store.container },
            submitted: { _ in Issue.record("Audio entered photo submission") }, cleanup: {},
            audio: .init(authorize: { ownerID, validate in
                try validate(); #expect(ownerID == store.ownerID); authorizations += 1
                return IdentificationDispatchAuthorization(recipient: .gemini, validate: validate)
            }, start: { key, proof, container, _ in
                starts += 1
                do {
                    #expect(container === store.container && key.snapshot.work.intent.identity.sourceAnalysisID == baselineID)
                    if audioSeed == nil {
                        let seed = ObservationAudioPreparationTests.Seed(container: container, source: source,
                            preparation: proof.preparation, bytes: wav, root: root)
                        #expect(try Data(contentsOf: seed.file) == wav)
                        #expect(proof.preparation.audio.mediaID != baselineID)
                        audioSeed = seed
                        let serviceBoundary = try ObservationAudioExecutionServiceTests.Boundary(seed)
                        let fixtureBytes = try #require(serviceBoundary.bytes)
                        var result = try #require(JSONSerialization.jsonObject(with: fixtureBytes) as? [String: Any])
                        var identification = try #require(result["result"] as? [String: Any])
                        identification["scan_id"] = source.observationID.uuidString.lowercased()
                        result["result"] = identification
                        serviceBoundary.bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                        _ = try ObservationReanalysisResult.decode(#require(serviceBoundary.bytes), matching: key.snapshot.work.intent.request)
                        serviceBoundary.hook = { phase in
                            if phase == "analyze" { throw URLError(.networkConnectionLost) }
                        }
                        boundary = serviceBoundary
                    }
                    let serviceBoundary = try #require(boundary)
                    #expect(proof.preparation == audioSeed?.preparation)
                    return queue.start(key, account: account, isCurrent: { true }, operation: { scope in
                        let result = await serviceBoundary.service.run(key.snapshot, proof: proof, container: container,
                            scope: scope, cleanup: serviceBoundary.cleanup)
                        outcomes.append(result)
                    }, didFinish: { exits.continuation.yield(()) })
                } catch {
                    Issue.record("Audio queue handoff failed: \(error)")
                    exits.continuation.yield(())
                    return .unavailable
                }
            }), documents: { root })
        let host = try composition.openAudioHost(target: target, container: store.container)
        #expect(host.present())
        host.prepareInput(from: inputURL, using: .init(directory: root, transcode: { url, directory in
            let output = directory.appendingPathComponent("prepared.wav")
            try FileManager.default.copyItem(at: url, to: output)
            return output
        }))
        while host.isPreparingInput { await Task.yield() }
        try #require(host.preparedInput == wav)
        host.submitPrepared(descriptionsBefore: [before], descriptionsAfter: [after])
        while host.isBusy { await Task.yield() }
        try #require(starts == 1)
        _ = await iterator.next()
        let seed = try #require(audioSeed), serviceBoundary = try #require(boundary)
        #expect(outcomes == [.held] && starts == 1 && authorizations == 1)
        let held = try ObservationAudioExecutionStore.read(seed.proof, container: store.container, isCurrent: { true })
        #expect(held.work.consumedAttempt == 1 && held.work.state == .held)
        #expect(held.work.intent.request.evidence == seed.preparation.evidence)
        #expect(seed.preparation.evidence == [.description(before), .audio(seed.preparation.audio), .description(after)])
        #expect(try Fixture.one(store.context(), FetchDescriptor<LocalScanRecord>()).selectedAnalysisID == baselineID.uuidString.lowercased())
        host.close(); #expect(host.present())
        host.retry()
        while host.isBusy { await Task.yield() }
        try #require(starts == 2)
        _ = await iterator.next()
        #expect(outcomes == [.held, .completed] && starts == 2 && authorizations == 1)
        #expect(serviceBoundary.events == ["read", "upload", "authorize", "analyze", "outcome", "cleanup"])
        let resultBytes = try #require(serviceBoundary.bytes)
        try await checkChildSelectionUndo(store: store, prepared: prepared, source: source, baselineID: baselineID,
            child: seed.preparation.identity.analysisID, resultBytes: resultBytes, account: account)
        host.close(); await queue.invalidateAndAwait()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func checkChildSelectionUndo(store: SharedMediaNativeAppMetadataTests.Store, prepared: Intent.Prepared,
                                         source: ObservationReanalysisSource, baselineID: UUID, child: UUID,
                                         resultBytes: Data, account: ObservationHistoryCloudClient) async throws {
        var phase = "checking both versions"
        defer { if phase != "complete" { print("Child History selection stopped: " + phase) } }
        let observation = source.observationID.uuidString.lowercased()
        let snapshots = Dictionary(uniqueKeysWithValues: try store.context().fetch(FetchDescriptor<LocalAnalysisRecord>())
            .map { ($0.id, $0.resultSnapshotData) })
        #expect(snapshots == [baselineID.uuidString.lowercased(): source.snapshot, child.uuidString.lowercased(): resultBytes])
        #expect(try Fixture.one(store.context(), FetchDescriptor<LocalScanRecord>()).selectedAnalysisID == baselineID.uuidString.lowercased())
        #expect(try ObservationHistoryListingService(cloud: account).hasMultiple(observationID: observation, container: store.container))
        var serverSelected = baselineID.uuidString.lowercased(), serverRevision = 1
        var cloud = account
        cloud.fetchState = { lookup in
            #expect(lookup.observation_id == observation)
            let target = lookup.analysis_id ?? serverSelected
            var state = try ObservationHistoryStateTests().fixture()
            state["owner_id"] = store.ownerID.uuidString.lowercased(); state["observation_id"] = observation
            state["state_revision"] = serverRevision; state["selected_analysis_id"] = serverSelected
            var analysis = try #require(state["analysis"] as? [String: Any])
            analysis["snapshot"] = String(decoding: try #require(snapshots[target]), as: UTF8.self)
            state["analysis"] = analysis
            return try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        }
        cloud.select = { selection in
            #expect(selection.expected_observation_revision == serverRevision)
            let previous = serverSelected
            serverSelected = selection.analysis_id; serverRevision += 1
            return try JSONEncoder().encode(ObservationHistorySelectionReceipt(schema_version: 1,
                operation_id: selection.operation_id, observation_id: observation, previous_analysis_id: previous,
                selected_analysis_id: serverSelected, observation_revision: serverRevision,
                review_revision: selection.expected_review_revision))
        }
        phase = "previewing child"
        _ = try await ObservationHistoryPreviewService(cloud: cloud).preview(observationID: observation, analysisID: child, container: store.container)
        let selection = ObservationHistorySelectionService(cloud: cloud)
        let editedContext = store.context()
        let edited = try Fixture.one(editedContext, FetchDescriptor<LocalScanRecord>())
        let priorName = edited.scientificName
        edited.scientificName = "Later visible edit"; try editedContext.save()
        #expect(throws: ObservationHistoryStateSyncService.AdmissionError.selectionProjectionRequired) {
            try selection.prepare(observationID: observation, analysisID: child, ownerID: store.ownerID, container: store.container)
        }
        edited.scientificName = priorName; try editedContext.save()
        phase = "selecting child"
        let selected = try selection.prepare(observationID: observation, analysisID: child, ownerID: store.ownerID, container: store.container)
        #expect(throws: SharedMediaStorageFailure.conflict) {
            _ = try SharedMediaNativeReceivingRows.appliedConsumer(prepared, in: store.context())
        }
        _ = try await selection.sendPending(observationID: observation, container: store.container)
        #expect(try Fixture.one(store.context(), FetchDescriptor<LocalScanRecord>()).selectedAnalysisID == child.uuidString.lowercased())
        let operation = try #require(UUID(uuidString: selected.operation_id))
        phase = "undoing selection"
        _ = try selection.prepareUndo(observationID: observation, operationID: operation, ownerID: store.ownerID, container: store.container)
        _ = try await selection.sendPending(observationID: observation, container: store.container)
        phase = "checking original association"
        let parent = try Fixture.one(store.context(), FetchDescriptor<LocalScanRecord>())
        #expect(parent.selectedAnalysisID == baselineID.uuidString.lowercased() && parent.observationStateRevision == 3)
        #expect(parent.sharedMediaConsumerID == prepared.bindingID)
        #expect(try NativeInitialHistoryBaseline.read(prepared, context: store.context())?.association.baselineAnalysisID == baselineID)
        #expect(try store.context().fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try Dictionary(uniqueKeysWithValues: store.context().fetch(FetchDescriptor<LocalAnalysisRecord>())
            .map { ($0.id, $0.resultSnapshotData) }) == snapshots)
        phase = "checking competing jobs after Undo"
        let collisionContext = store.context()
        let unknown = OfflineJobRecord(id: "unrecognized-photo-consumer", kind: .future, subjectId: observation, status: .complete)
        collisionContext.insert(unknown); try collisionContext.save()
        #expect(throws: SharedMediaStorageFailure.conflict) {
            _ = try SharedMediaNativeReceivingRows.appliedConsumer(prepared, in: store.context())
        }
        collisionContext.delete(unknown); try collisionContext.save()
        phase = "complete"
    }

    private func verifyHistoryAcknowledgement(advancedSelection: Bool) async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let reply = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in reply })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        let applied = try #require(await owner.applyAppInitialResult(prepared) { _, _ in acquisition })
        #expect(try await owner.acknowledgeAppInitialHistory(prepared) { _, _ in Issue.record("Missing baseline must hold"); return nil } == nil)
        let baselineID = try await enrollInitialFixture(store, prepared: prepared, acquisition: acquisition, advancedSelection: advancedSelection)
        if advancedSelection {
            let context = store.context(), scan = try Fixture.one(context, FetchDescriptor<LocalScanRecord>())
            #expect(scan.selectedAnalysisID != baselineID.uuidString.lowercased() && scan.observationStateRevision == 2)
            #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 2)
            // A rejection can settle after enrollment but before the native
            // receipt handoff. It is historical, and only for the exact owner.
            let request = ObservationHistorySelectionRequest(observation: prepared.observationID,
                analysis: baselineID, revision: 2, review: 0)
            let rejection = ObservationHistorySelectionRejection(schema_version: 1, operation_id: request.operation_id,
                observation_id: request.observation_id, analysis_id: request.analysis_id,
                expected_observation_revision: 2, expected_review_revision: 0, outcome: "revision_conflict")
            let previous = try #require(scan.selectedAnalysisID)
            func recordRejection(_ owner: UUID) throws {
                try ObservationHistorySelectionIntent.store(.init(version: 2, owner: owner.uuidString.lowercased(),
                    previous: previous, previousReview: 0, request: request, rejection: rejection), context: context)
                try context.save()
            }
            try recordRejection(UUID())
            #expect(throws: SharedMediaStorageFailure.conflict) {
                _ = try SharedMediaNativeReceivingRows.appliedConsumer(prepared, in: store.context())
            }
            try recordRejection(store.ownerID)
        }
        let historyBefore: [String: Data] = advancedSelection ? Dictionary(uniqueKeysWithValues:
            try store.context().fetch(FetchDescriptor<LocalAnalysisRecord>()).map { ($0.id, $0.resultSnapshotData) }) : [:]
        let peerPackageID = UUID()
        let peer = try await owner.prepareAppOriginal(packageID: peerPackageID, draftGeneration: UUID(), ordinal: 0, kind: .picker)
        let peerBytes = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireAppOriginal(peer) { peerBytes }
        let oldRevision = try revision(store), originalRow = try stored(store)
        let context = store.context(), packageID = prepared.package.id
        let package = try Fixture.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let packageBefore = SharedMediaNativeAppMetadataFacts.Package(package)
        let scan = try Fixture.one(context, FetchDescriptor<LocalScanRecord>())
        let laterSelection = UUID().uuidString.lowercased()
        scan.selectedAnalysisID = laterSelection; scan.observationStateRevision = 9
        scan.fieldNotes = "Later private notes"; scan.confidenceScore = 0.123
        try context.save()
        // The exact completed association is permitted, not arbitrary jobs with
        // the same subject. No generic missing-quartet guard is relaxed.
        let unknown = OfflineJobRecord(id: "unrelated-fixture-job", kind: .future, subjectId: scan.id, status: .complete)
        context.insert(unknown); try context.save()
        await #expect(throws: (any Error).self) { _ = try await owner.acknowledgeAppInitialHistory(prepared) { _, _ in acquisition } }
        context.delete(unknown); try context.save()
        func pendingBudget() throws -> SharedMediaNativeAcquisitionBudget.Snapshot {
            let current = store.context(), id = store.inventoryID
            let inventory = try Fixture.one(current, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
            return try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: current, inventory: inventory,
                ownerID: store.ownerID, format: .appV2)
        }
        let budget = try pendingBudget()
        #expect(budget.metadataByPackage[packageID] == nil && budget.metadataByPackage[peerPackageID] != nil)
        let baseline = try #require(try NativeInitialHistoryBaseline.read(prepared, context: store.context()))
        let expected = try SharedMediaNativeConsumerCohort.AppliedInitial(acknowledging: applied, association: baseline.association)
        let growth = max(0, Int64(try expected.encoded().count) - Int64(try applied.encoded().count))
        // Find the existing totals' exact free-space boundary without exposing
        // private accounting or fabricating a retained pending-package entry.
        var lower: Int64 = 0, upper = Int64.max
        try budget.totals.checkAvailable(upper, additionalReservation: growth)
        for _ in 0..<63 {
            let middle = lower + (upper - lower) / 2
            do { try budget.totals.checkAvailable(middle, additionalReservation: growth); upper = middle }
            catch SharedMediaStorageFailure.capacity { lower = middle + 1 }
        }
        #expect(lower == upper && upper > SharedMediaStoragePolicy.reserve + growth)
        try owner.setMetadataFault(nil, availableBytes: upper - 1)
        await #expect(throws: SharedMediaStorageFailure.capacity) {
            _ = try await owner.acknowledgeAppInitialHistory(prepared) { _, _ in Issue.record("Capacity hold reacquired original"); return acquisition }
        }
        try owner.setMetadataFault({ if $0 == .afterSave { throw SharedMediaStorageFailure.unavailable } }, availableBytes: upper)
        let acknowledged = try #require(await owner.acknowledgeAppInitialHistory(prepared) { current, validate in
            try validate(); #expect(current == admission); return acquisition
        })
        #expect(acknowledged == expected && acknowledged.format == .history && acknowledged.consumerRevision == 2)
        #expect(try pendingBudget().totals == budget.totals)
        #expect(try pendingBudget().metadataByPackage == budget.metadataByPackage)
        #expect(acknowledged.historyHandoffRemainingAdvances == 0 && acknowledged.historyBaseline?.baselineAnalysisID == baselineID)
        #expect(acknowledged.original == applied.original && acknowledged.receipt == applied.receipt)
        #expect(try revision(store) == oldRevision + 1 && stored(store) == originalRow)
        let saved = store.context()
        let savedPackage = try Fixture.one(saved, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        #expect(SharedMediaNativeAppMetadataFacts.Package(savedPackage) == packageBefore)
        let retained = try Fixture.one(saved, FetchDescriptor<LocalScanRecord>())
        #expect(retained.selectedAnalysisID == laterSelection && retained.fieldNotes == "Later private notes" && retained.confidenceScore == 0.123)
        if advancedSelection {
            let historyAfter = Dictionary(uniqueKeysWithValues:
                try saved.fetch(FetchDescriptor<LocalAnalysisRecord>()).map { ($0.id, $0.resultSnapshotData) })
            #expect(historyBefore.count == 2 && historyAfter == historyBefore)
        } else {
            #expect(try saved.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
        }
        #expect(try SharedMediaNativeTerminalScan.read(container: store.container, inventoryID: store.inventoryID).appliedHandoffAdvances == 0)
        try owner.setMetadataFault { if $0 == .beforeSave { Issue.record("Acknowledged replay must not save") } }
        #expect(try await owner.acknowledgeAppInitialHistory(prepared) { _, _ in Issue.record("Acknowledged replay fetched original"); return nil } == acknowledged)
        #expect(try await owner.applyAppInitialResult(prepared) { _, _ in Issue.record("Application replay fetched original"); return nil } == acknowledged)
        _ = try await owner.readRetainedAppPhotos(prepared, role: .display)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(store)
        #expect(try await cold.acknowledgeAppInitialHistory(prepared) { _, _ in Issue.record("Cold replay fetched original"); return nil } == acknowledged)
        let metadata = store.context()
        let job = try #require(try metadata.fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.baselineJobID(scan.id)))
        let originalMetadata = job.metadataJSON
        job.metadataJSON = "{}"; try metadata.save()
        await #expect(throws: (any Error).self) { _ = try await cold.readRetainedAppPhotos(prepared, role: .display) }
        job.metadataJSON = originalMetadata; try metadata.save()
        #expect(try revision(store) == oldRevision + 1 && stored(store) == originalRow)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func recoveredAssociationAcknowledgesWithoutInventingIntentOrChangingSelection() async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let reply = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in reply })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        _ = try #require(await owner.applyAppInitialResult(prepared) { _, _ in acquisition })
        let baselineID = try await enrollInitialFixture(store, prepared: prepared, acquisition: acquisition)
        let context = store.context(), observation = prepared.observationID
        let job = try #require(try context.fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.baselineJobID(observation.uuidString)))
        context.delete(job)
        let scan = try Fixture.one(context, FetchDescriptor<LocalScanRecord>()), later = UUID().uuidString.lowercased()
        scan.selectedAnalysisID = later; scan.observationStateRevision = 9; scan.fieldNotes = "Later selection remains"
        try context.save()
        #expect(try NativeInitialHistoryBaseline.read(prepared, context: store.context()) == nil)
        let child = try Fixture.one(store.context(), FetchDescriptor<LocalAnalysisRecord>())
        let data = try JSONSerialization.data(withJSONObject: ["schema_version": 1, "owner_id": store.ownerID.uuidString.lowercased(),
            "observation_id": observation.uuidString.lowercased(), "baseline_analysis_id": baselineID.uuidString.lowercased(),
            "snapshot": String(decoding: child.resultSnapshotData, as: UTF8.self),
            "snapshot_sha256": ObservationHistoryEnrollmentIntent.baselineDigest(child.resultSnapshotData)])
        var cloud = ObservationHistoryCloudClient(begin: { _ in
            AccountBoundWorkLease(id: UUID(), session: AuthTransitionSession(userID: store.ownerID, isAnonymous: false))
        }, isCurrent: { _ in true }, finish: { _ in }, fetch: { _ in throw ObservationHistoryError.unavailable })
        cloud.enroll = { _ in Issue.record("Recovered association reenrolled"); throw ObservationHistoryError.unavailable }
        cloud.recoverBaseline = { requested in #expect(requested == observation); return data }
        let revisionBefore = try revision(store), rowBefore = try stored(store)
        _ = try await ObservationHistoryEnrollmentOwner().continueInitialHistory(observation: observation, owner: store.ownerID,
            generation: 1, container: store.container, cloud: cloud, isCurrent: { true })
        #expect(try revision(store) == revisionBefore && stored(store) == rowBefore)
        let recovered = try #require(try NativeInitialHistoryBaseline.read(prepared, context: store.context()))
        #expect(recovered.association.intentID == nil && recovered.association.provenance == .serverRecovery)
        let acknowledged = try #require(await owner.acknowledgeAppInitialHistory(prepared) { _, validate in try validate(); return acquisition })
        #expect(acknowledged.historyBaseline == recovered.association && acknowledged.historyHandoffRemainingAdvances == 0)
        #expect(try revision(store) == revisionBefore + 1 && stored(store) == rowBefore)
        let saved = try Fixture.one(store.context(), FetchDescriptor<LocalScanRecord>())
        #expect(saved.selectedAnalysisID == later && saved.observationStateRevision == 9 && saved.fieldNotes == "Later selection remains")
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(store)
        #expect(try await cold.acknowledgeAppInitialHistory(prepared) { _, _ in Issue.record("Recovered replay fetched completion"); return nil } == acknowledged)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["cancel", "account", "deletion", "baseline"])
    func suspendedHistoryAcknowledgementRetainsPendingAdvance(_ fault: String) async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let reply = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in reply })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        let applied = try #require(await owner.applyAppInitialResult(prepared) { _, _ in acquisition })
        _ = try await enrollInitialFixture(store, prepared: prepared, acquisition: acquisition)
        let oldRevision = try revision(store), originalRow = try stored(store)
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var reachedReader = false
        let operation = Task {
            do {
                return try await owner.acknowledgeAppInitialHistory(prepared) { _, _ in
                    reachedReader = true
                    await entered.open(); await release.wait(); return acquisition
                }
            } catch {
                await entered.open() // Propagate failure before the suspension barrier.
                throw error
            }
        }
        await entered.wait()
        guard reachedReader else {
            _ = try await operation.value
            Issue.record("Acknowledgement returned without reaching the original reader")
            return
        }
        var transition: Task<Bool, Never>?
        let context = store.context()
        switch fault {
        case "cancel": operation.cancel()
        case "account":
            transition = Task { await owner.invalidateAndAwaitForAccountTransition() }
            while !owner.heldOriginalAdmissionClosedForTesting { await Task.yield() }
        case "deletion":
            context.insert(PendingCloudDeletionTask(scanId: prepared.observationID.uuidString)); try context.save()
        default:
            let job = try #require(try context.fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.baselineJobID(prepared.observationID.uuidString)))
            job.metadataJSON = "{}"; try context.save()
        }
        await release.open()
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        #expect(try revision(store) == oldRevision && stored(store) == originalRow)
        let id = prepared.bindingID
        let consumer = try Fixture.one(store.context(), FetchDescriptor<SharedMediaConsumerRecord>(predicate: #Predicate { $0.id == id }))
        #expect(try SharedMediaNativeConsumerCohort.AppliedInitial.decode(consumer.cohortData) == applied && consumer.revision == 1)
        if let transition { #expect(await transition.value) }
        else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
    }

    @Test(.sharedProcessState(.offlineQueueManager)) func explicitInitialContinuationResumesApplicationAndPreservesHistory() async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let candidate = try #require(try await owner.discoverAppReceivedCandidates().first)
        let reply = try originalAcknowledgement(allocation)
        let admission = try InitialCompletionDocuments.CpmAdmission(acknowledgement: reply, original: .saved(allocation))
        let acquisition = try completionAcquisition(admission)
        let network = InitialPhotoAllocationTransportTests.Fixture(ownerID: store.ownerID)
        defer { network.close() }
        let found = try completionWire(admission, acquisition: acquisition)
        var pendingFields = try #require(InitialAnalysisCanonical.parseCompletionStatus(found).object)
        pendingFields["outcome"] = .string("pending")
        for key in pendingFields.keys where !["version", "outcome", "admission_canonical"].contains(key) {
            pendingFields[key] = .null
        }
        let pending = try InitialAnalysisCanonical.encode(.object(pendingFields))
        let calls = OSAllocatedUnfairLock(initialState: [String]())
        let originalBinding = try InitialCompletionDocuments.CpmBinding.saved(allocation)
        network.mock.register(path: "/check-scan-status") { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let envelope = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(Set(envelope.keys) == ["initial_recovery"])
            let recovery = try #require(envelope["initial_recovery"] as? [String: Any])
            let phase = try #require(recovery["phase"] as? String)
            let original = try #require(recovery["original"] as? [String: Any])
            #expect(request.httpMethod == "POST" && request.timeoutInterval == 5)
            #expect(request.value(forHTTPHeaderField: "X-Merian-Initial-Recovery") == phase + "-v1")
            #expect(original["owner_id"] as? String == originalBinding.ownerID)
            #expect(original["scan_id"] as? String == originalBinding.scanID)
            if phase == "admission" {
                #expect(original.count == 8)
                #expect(original["candidate_canonical"] as? String == originalBinding.candidateCanonical)
                #expect(original["assignment_digest"] as? String == originalBinding.assignmentDigest)
            } else {
                #expect(phase == "completion" && original.count == 12)
                #expect(try InitialAnalysisCanonical.encode(InitialAnalysisCanonical.parse(
                    JSONSerialization.data(withJSONObject: original, options: [.sortedKeys, .withoutEscapingSlashes]))) == admission.admission)
            }
            let sequence = calls.withLock { $0.append(phase); return $0 }
            // Loss before acknowledgement reaches the native owner must not
            // trigger a transport retry or create a durable admission pin.
            if sequence.count == 1 { throw URLError(.networkConnectionLost) }
            let response = phase == "admission" ? reply : (sequence.filter { $0 == "completion" }.count == 1 ? pending : found)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json", "Cache-Control": "no-store"])!, response)
        }
        let transport = NativeReceivedStatusTransport(baseURL: "https://example.supabase.co", dispatcher: network.dispatcher)
        var admissions = 0, completions = 0, enrollments = 0
        let readAdmission: @MainActor (SharedMediaNativePhotoAllocation, @escaping NativeReceivedStatusTransport.Validator) async throws -> Data? = { allocation, validate in
            admissions += 1
            return try await transport.recoverAdmission(.saved(allocation), validate: validate)
        }
        let readCompletion: @MainActor (InitialCompletionDocuments.CpmAdmission, @escaping NativeReceivedStatusTransport.Validator) async throws -> InitialCompletionDocuments.CpmAcquisition? = { admission, validate in
            completions += 1
            return try await transport.recoverCompletion(admission, validate: validate)
        }
        let untouched = try stored(store), untouchedRevision = try revision(store)
        await #expect(throws: (any Error).self) {
            _ = try await CaptureNativeRecoveryModel.completeInitialHistory(candidate, owner: owner, isCurrent: { true },
                readAdmission: readAdmission, readCompletion: readCompletion,
                enroll: { _ in Issue.record("Lost acknowledgement enrolled History") })
        }
        #expect(calls.withLock { $0 } == ["admission"])
        #expect(try stored(store) == untouched && revision(store) == untouchedRevision)
        #expect(try await CaptureNativeRecoveryModel.completeInitialHistory(candidate, owner: owner, isCurrent: { true },
            readAdmission: readAdmission, readCompletion: readCompletion,
            enroll: { _ in Issue.record("Pending completion enrolled History") }) == nil)
        let waiting = try stored(store)
        #expect(waiting.initialAdmissionData == reply && waiting.initialCompletionData == nil)
        #expect(waiting.resultData == untouched.resultData && waiting.preparedData == untouched.preparedData)
        #expect(waiting.allocationData == untouched.allocationData)
        #expect(try store.context().fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        #expect(calls.withLock { $0 } == ["admission", "admission", "completion"])
        // A concrete interruption after application must not turn restart into
        // another recovery/application call or another analysis execution.
        await #expect(throws: SharedMediaStorageFailure.unavailable) {
            _ = try await CaptureNativeRecoveryModel.completeInitialHistory(candidate, owner: owner, isCurrent: { true },
                readAdmission: readAdmission, readCompletion: readCompletion,
                enroll: { _ in throw SharedMediaStorageFailure.unavailable })
        }
        #expect(admissions == 3 && completions == 3)
        let applied = try #require(try await owner.discoverAppInitialContinuation(candidate))
        #expect(applied.phase == .applied && applied.baseline == nil)
        #expect(try applied.prepared.encoded() == prepared.encoded())
        #expect(try await owner.discoverAppReceivedCandidates().isEmpty)
        try await addSkippedInitialPage(store, owner: owner, candidate: candidate)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(store)
        let skipped = try await cold.appReceivingQuery(SharedMediaNativeReceivingQuery.initialHandoffPage(nil))
        #expect(skipped.candidates.isEmpty)
        let cursor = try #require(skipped.next)
        let page = try await cold.appReceivingQuery(SharedMediaNativeReceivingQuery.initialHandoffPage(cursor))
        #expect(page.candidates == [candidate] && page.next == nil)
        let completed = try #require(try await CaptureNativeRecoveryModel.completeInitialHistory(candidate, owner: cold,
            isCurrent: { true }, readAdmission: { _, _ in Issue.record("Restart repeated admission recovery"); return nil },
            readCompletion: readCompletion,
            enroll: { observation in
                #expect(observation == prepared.observationID); enrollments += 1
                _ = try await enrollInitialFixture(store, prepared: prepared, acquisition: acquisition)
            }))
        #expect(completions == 4 && enrollments == 1 && completed.observationID == prepared.observationID)
        let acknowledgedPage = try await cold.appReceivingQuery(SharedMediaNativeReceivingQuery.initialHandoffPage(nil))
        #expect(acknowledgedPage.candidates.isEmpty)
        let acknowledgedCursor = try #require(acknowledgedPage.next)
        let acknowledgedNext = try await cold.appReceivingQuery(SharedMediaNativeReceivingQuery.initialHandoffPage(acknowledgedCursor))
        #expect(acknowledgedNext.candidates.isEmpty && acknowledgedNext.next == nil)
        let context = store.context(), scan = try Fixture.one(context, FetchDescriptor<LocalScanRecord>())
        let later = UUID().uuidString.lowercased()
        scan.selectedAnalysisID = later; scan.observationStateRevision = 8; scan.fieldNotes = "Later selection"
        try context.save()
        let before = try revision(store), routes = AppRouteCoordinator()
        var current = true
        let model = CaptureNativeRecoveryModel(ownerID: store.ownerID, isCurrent: { current },
            initialRead: { try await cold.discoverAppInitialContinuation($0) }, initialCompletion: { selected, validate in
                try await CaptureNativeRecoveryModel.completeInitialHistory(selected, owner: cold,
                    isCurrent: { (try? validate()) != nil },
                    readAdmission: { _, _ in Issue.record("Terminal replay fetched admission"); return nil },
                    readCompletion: { _, _ in Issue.record("Terminal replay fetched completion"); return nil },
                    enroll: { _ in Issue.record("Terminal replay enrolled again") })
            }, initialOpen: { association in
                routes.request(.scan(scanId: association.observationID.uuidString.lowercased()), source: .internalUserAction)
            }, discover: { try await cold.discoverAppReceivedCandidates() })
        #expect(!model.openSavedResult())
        await model.resumeInitial(candidate)
        #expect(model.state == .holding(candidate) && model.historyStatus == .idle && model.canAddToHistory)
        model.addToHistory(); model.addToHistory()
        while model.historyStatus == .saving { await Task.yield() }
        #expect(model.historyStatus == .saved(completed))
        #expect(routes.nextRequestID == nil && model.canOpenSavedResult)
        current = false
        #expect(!model.openSavedResult() && routes.nextRequestID == nil)
        current = true; model.setVisible(false)
        #expect(!model.openSavedResult() && routes.nextRequestID == nil)
        model.setVisible(true)
        #expect(model.openSavedResult())
        #expect(!model.openSavedResult() && model.state == .closed)
        let route = try #require(routes.claimNext())
        #expect(route.route == .scan(scanId: prepared.observationID.uuidString.lowercased()))
        #expect(route.source == .internalUserAction)
        #expect(completions == 4 && enrollments == 1)
        #expect(calls.withLock { $0 } == ["admission", "admission", "completion", "admission", "completion", "completion", "completion"])
        #expect(try revision(store) == before)
        let saved = try Fixture.one(store.context(), FetchDescriptor<LocalScanRecord>())
        #expect(saved.selectedAnalysisID == later && saved.fieldNotes == "Later selection")
        // UUID alone must not retarget a stale operation or received digest.
        let stale = SharedMediaNativeReceivedCandidate(profile: candidate.profile, packageID: candidate.packageID,
            draftGeneration: candidate.draftGeneration, operationID: UUID(), revision: candidate.revision,
            preparedSHA256: candidate.preparedSHA256, receivedSHA256: candidate.receivedSHA256)
        await #expect(throws: SharedMediaStorageFailure.stale) { _ = try await cold.discoverAppInitialContinuation(stale) }
        await model.closeAndWait()
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["close", "hidden", "account"])
    func explicitInitialContinuationDrainsPresentation(_ boundary: String) async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let candidate = try #require(try await owner.discoverAppReceivedCandidates().first)
        let reply = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in reply })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        _ = try await owner.applyAppInitialResult(prepared) { _, _ in acquisition }
        let before = try revision(store), entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var current = true, entries = 0, returned = false
        let model = CaptureNativeRecoveryModel(ownerID: store.ownerID, isCurrent: { current },
            initialRead: { try await owner.discoverAppInitialContinuation($0) }, initialCompletion: { _, validate in
                entries += 1; await entered.open(); await release.wait()
                defer { returned = true }; try validate(); Issue.record("Invalidated presentation continued"); return nil
            }, discover: { [] })
        await model.resumeInitial(candidate)
        try #require(model.canAddToHistory)
        model.addToHistory(); model.addToHistory()
        await entered.wait(); #expect(entries == 1)
        var closed = false
        let closing: Task<Void, Never>?
        switch boundary {
        case "close": closing = Task { await model.closeAndWait(); closed = true }
        case "hidden": model.setVisible(false); closing = nil
        default: current = false; closing = Task { await model.closeAndWait(); closed = true }
        }
        if closing != nil { while model.state != .closed { await Task.yield() } }
        #expect(!closed && !returned)
        await release.open(); await closing?.value; await model.waitForStatusCleanup()
        #expect(returned && entries == 1 && (closing == nil || closed))
        #expect(try revision(store) == before)
        let state = try #require(try await owner.discoverAppInitialContinuation(candidate))
        #expect(state.phase == .applied && state.baseline == nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["reply", "import"])
    func nativeEnrollmentRecoveryRequiresSameDurableIntent(_ fault: String) async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let candidate = try #require(try await owner.discoverAppReceivedCandidates().first)
        let reply = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in reply })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        _ = try await owner.applyAppInitialResult(prepared) { _, _ in acquisition }
        let baselineID = UUID(), before = try revision(store)
        await #expect(throws: SharedMediaStorageFailure.unavailable) {
            _ = try await enrollInitialFixture(store, prepared: prepared, acquisition: acquisition, baselineID: baselineID, fault: fault)
        }
        let proof = try #require(try ObservationHistoryEnrollmentService.nativeRecoveryAdmission(candidate, container: store.container))
        #expect(proof.intent.observationID == prepared.observationID)
        let recoveryPage = try ObservationHistoryEnrollmentService.nativeRecoveryPage(ownerID: store.ownerID,
            container: store.container, cursor: nil)
        #expect(recoveryPage.candidates == [candidate] && recoveryPage.next == nil)
        let pageContext = store.context()
        var tombstones: [OfflineJobRecord] = []
        for index in 1...SharedMediaStoragePolicy.pageSize {
            let subject = String(format: "00000000-0000-0000-0000-%012d", index)
            let row = OfflineJobRecord(id: ObservationHistoryEnrollmentIntent.prefix + subject,
                kind: .future, subjectId: subject, status: .cancelled)
            tombstones.append(row); pageContext.insert(row)
        }
        try pageContext.save()
        let skipped = try ObservationHistoryEnrollmentService.nativeRecoveryPage(ownerID: store.ownerID,
            container: store.container, cursor: nil)
        #expect(skipped.candidates.isEmpty)
        let skippedCursor = try #require(skipped.next)
        let following = try ObservationHistoryEnrollmentService.nativeRecoveryPage(ownerID: store.ownerID,
            container: store.container, cursor: skippedCursor)
        #expect(following.candidates == [candidate] && following.next == nil)
        #expect(throws: (any Error).self) {
            _ = try ObservationHistoryEnrollmentService.nativeRecoveryPage(ownerID: UUID(), container: store.container, cursor: skippedCursor)
        }
        for row in tombstones { pageContext.delete(row) }
        try pageContext.save()
        await #expect(throws: (any Error).self) {
            _ = try await owner.appReceivingQuery(SharedMediaNativeReceivingQuery.initialHandoffPage(nil))
        }
        let metadataModel = CaptureNativeRecoveryModel(ownerID: store.ownerID, isCurrent: { true }, lifetime: { nil },
            initialRead: { selected in
                let saved = try #require(try ObservationHistoryEnrollmentService.nativeRecoveryAdmission(selected, container: store.container))
                return .init(prepared: saved.prepared, phase: .enrollmentHeld, baseline: nil)
            }, initialCompletion: { _, _ in Issue.record("Discovery started enrollment"); return nil },
            initialPageRead: { _, cursor in
                try ObservationHistoryEnrollmentService.nativeRecoveryPage(ownerID: store.ownerID, container: store.container, cursor: cursor)
            }, discover: { throw SharedMediaStorageFailure.unavailable })
        await metadataModel.open(); await metadataModel.findSavedInitial(.enrollment)
        await metadataModel.selectSavedInitial(candidate)
        #expect(metadataModel.state == .holding(candidate) && metadataModel.canAddToHistory)
        await metadataModel.closeAndWait()
        #expect(try proof.prepared.encoded() == prepared.encoded())
        await #expect(throws: (any Error).self) { _ = try await owner.discoverAppInitialContinuation(candidate) }
        await #expect(throws: (any Error).self) { _ = try await owner.readRetainedAppPhotos(prepared, role: .display) }
        let context = store.context(), observation = prepared.observationID.uuidString.lowercased()
        let unknown = OfflineJobRecord(id: "unknown-enrollment-fixture", kind: .future, subjectId: observation, status: .complete)
        context.insert(unknown); try context.save()
        #expect(throws: (any Error).self) { _ = try ObservationHistoryEnrollmentService.nativeRecoveryAdmission(candidate, container: store.container) }
        context.delete(unknown); try context.save()
        let jobID = ObservationHistoryEnrollmentIntent.jobID(observation)
        let job = try #require(try context.fetchOfflineJob(id: jobID)), metadata = job.metadataJSON
        context.delete(job); try context.save()
        var calls = 0
        await #expect(throws: (any Error).self) {
            _ = try await enrollInitialFixture(store, prepared: prepared, acquisition: acquisition, baselineID: baselineID,
                recovery: proof, didDispatch: { calls += 1 })
        }
        #expect(calls == 0)
        #expect(try context.fetchOfflineJob(id: jobID) == nil)
        // Restore only this disposable test's exact original interrupted row.
        context.insert(OfflineJobRecord(id: jobID, kind: .future, subjectId: observation, status: .needsAttention, metadataJSON: metadata))
        try context.save()
        let recovered = try await enrollInitialFixture(store, prepared: prepared, acquisition: acquisition,
            baselineID: baselineID, recovery: proof, didDispatch: { calls += 1 })
        #expect(recovered == baselineID && calls == 1)
        #expect(try revision(store) == before)
        let association = try #require(try ObservationHistoryEnrollmentIntent.baseline(observationID: prepared.observationID,
            ownerID: store.ownerID, context: store.context()))
        #expect(association.intentID == proof.intent.intentID)
        #expect(try ObservationHistoryEnrollmentService.nativeRecoveryAdmission(candidate, container: store.container) == nil)
        // Enrollment can finish for another waiter after this view closes. A
        // later explicit action acknowledges that association without reenrolling.
        let result = try #require(try await CaptureNativeRecoveryModel.completeInitialHistory(candidate, owner: owner,
            isCurrent: { true }, readAdmission: { _, _ in Issue.record("Recovery repeated admission"); return nil },
            readCompletion: { _, validate in try validate(); return acquisition },
            enroll: { _ in Issue.record("Recovered association enrolled again") }))
        #expect(result.baselineAnalysisID == baselineID)
        let completedPage = try ObservationHistoryEnrollmentService.nativeRecoveryPage(ownerID: store.ownerID,
            container: store.container, cursor: nil)
        #expect(completedPage.candidates.isEmpty)
        // A metadata-only selection cannot display an ordinary saved outcome
        // unless the native lifetime has become available after completion.
        let missingLifetime = CaptureNativeRecoveryModel(ownerID: store.ownerID, isCurrent: { true }, lifetime: { nil },
            initialRead: { _ in .init(prepared: proof.prepared, phase: .enrollmentHeld, baseline: nil) },
            initialCompletion: { _, validate in try validate(); return result }, discover: { [] })
        await missingLifetime.resumeInitial(candidate)
        try #require(missingLifetime.canAddToHistory)
        missingLifetime.addToHistory()
        while missingLifetime.historyStatus == .saving { await Task.yield() }
        #expect(missingLifetime.historyStatus == .held)
        await missingLifetime.closeAndWait()
        #expect(try revision(store) == before + 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func addSkippedInitialPage(_ store: SharedMediaNativeAppMetadataTests.Store,
                                       owner: SharedMediaNativeOriginalOwner,
                                       candidate: SharedMediaNativeReceivedCandidate) async throws {
        let packageID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")), draft = UUID()
        let request = try await owner.prepareAppOriginal(packageID: packageID, draftGeneration: draft, ordinal: 0, kind: .picker)
        let image = PhotoPreparationTestHarness.image()
        let acquired = try await owner.acquireAppOriginal(request) { image }
        let original = PhotoOriginalReference(ownerID: store.ownerID, packageID: packageID, referenceID: request.referenceID,
            assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: draft,
            referenceRevision: acquired.referenceRevision)
        let ready = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: SharedMediaNativeOriginalDispositionSharingTests.recipe)
        let prepared = try await owner.stageAppReceiving(packageID: packageID, draftGeneration: draft, pairIDs: [ready.intent().pairID])
        _ = try await owner.receiveAppPrepared(prepared)
        let admission = try await owner.appReleaseStageRequest(prepared, releaseID: UUID())
        _ = try await owner.stageAppRelease(admission)
        let started = try await owner.startAppRelease(admission.request)
        let retiring = try await owner.retireAppReleasePair(started)
        let removed = try await owner.removeAppReleasePair(retiring)
        let originalRetiring = try await owner.disposeAppReleaseOriginal(removed)
        let originalGone = try await owner.removeAppReleaseOriginal(originalRetiring)
        let terminal = try await owner.finishAppRelease(originalGone)
        let fixture = SharedMediaNativeReceivingTerminalReaderTests(), context = store.context()
        // Valid historical reader fixtures, following one actual release. These
        // exact low keys put the real applied result beyond a full skipped page.
        for index in 2...SharedMediaStoragePolicy.pageSize {
            let id = try #require(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)))
            try #require(id.uuidString.lowercased() < candidate.packageID.uuidString.lowercased())
            let value = try fixture.clone(terminal, packageID: id), plan = value.plan
            let row = SharedMediaReceivingIntentRecord(packageID: id, inventoryID: plan.profile.inventoryID,
                inventoryGeneration: plan.profile.generation, ownerID: plan.profile.ownerID, draftGeneration: plan.package.generation,
                operationID: plan.operationID, preparedData: Data(), preparedSHA256: plan.preparedSHA256)
            try fixture.restore(row, value); context.insert(row)
        }
        try context.save()
    }

    func enrollInitialFixture(_ store: SharedMediaNativeAppMetadataTests.Store,
                                      prepared: Intent.Prepared, acquisition: InitialCompletionDocuments.CpmAcquisition,
                                      baselineID: UUID = UUID(), recovery: NativeInitialEnrollmentRecovery? = nil, advancedSelection: Bool = false,
                                      fault: String? = nil, didDispatch: @escaping () -> Void = {}) async throws -> UUID {
        let ownerID = prepared.profile.ownerID, observationID = prepared.observationID
        let observation = observationID.uuidString.lowercased(), baseline = baselineID.uuidString.lowercased()
        // Frozen result-v1 encodes decimals as strings. Reuse its qualified
        // application projection for synthetic V3 JSON, never mutable display.
        func originalField(_ key: String) throws -> Any {
            guard let bytes = try acquisition.result.applicationFieldJSON(key) else { return NSNull() }
            return try JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])
        }
        let projection = try #require(JSONSerialization.jsonObject(with: acquisition.record.projection) as? [String: Any])
        let association = projection["species_association"] as? [String: Any]
        var state = try ObservationHistoryStateTests().fixture()
        state["owner_id"] = ownerID.uuidString.lowercased(); state["observation_id"] = observation
        state["selected_analysis_id"] = baseline
        var analysis = try #require(state["analysis"] as? [String: Any])
        let sourceSnapshot = try #require(analysis["snapshot"] as? String)
        var snapshot = try #require(JSONSerialization.jsonObject(with: Data(sourceSnapshot.utf8)) as? [String: Any])
        snapshot["observation_id"] = observation; snapshot["analysis_id"] = baseline
        snapshot["result"] = ["scan_id": observation, "species_id": association?["species_id"] ?? NSNull(),
            "primary_identification": try originalField("primary_identification"),
            "identification_provenance": try JSONSerialization.jsonObject(with: acquisition.result.applicationProvenance()),
            "is_biological_subject": try originalField("is_biological_subject"), "candidates": try originalField("candidates"),
            "pet_identification": try originalField("pet_identification"), "ai_confidence_score": try originalField("confidence_score"),
            "ai_reasoning": try originalField("ai_reasoning"), "inference_tier": try originalField("inference_tier")] as [String: Any]
        analysis["snapshot"] = String(decoding: try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]), as: UTF8.self)
        state["analysis"] = analysis
        var selected = state
        var pairData: Data?
        if advancedSelection {
            let fixture = Data(try DatabaseActorTestSupport.loadRepositorySource(at:
                "services/supabase/functions/_shared/analysisHistory/fixtures/enrollment-selection-v1.json").utf8)
            let pair = try #require(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
            selected = try #require(pair["selected_state"] as? [String: Any])
            let later = UUID().uuidString.lowercased()
            selected["owner_id"] = ownerID.uuidString.lowercased(); selected["observation_id"] = observation
            selected["selected_analysis_id"] = later; selected["state_revision"] = 2
            var selectedAnalysis = try #require(selected["analysis"] as? [String: Any])
            let text = try #require(selectedAnalysis["snapshot"] as? String)
            var laterSnapshot = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            laterSnapshot["analysis_id"] = later; laterSnapshot["observation_id"] = observation
            var result = try #require(laterSnapshot["result"] as? [String: Any]); result["scan_id"] = observation
            laterSnapshot["result"] = result
            selectedAnalysis["snapshot"] = String(decoding: try JSONSerialization.data(withJSONObject: laterSnapshot, options: [.sortedKeys]), as: UTF8.self)
            selected["analysis"] = selectedAnalysis
            state["state_revision"] = 2; state["selected_analysis_id"] = later
            let original = try #require(analysis["snapshot"] as? String)
            pairData = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
                "baseline_sha256": ObservationHistoryEnrollmentIntent.baselineDigest(Data(original.utf8)),
                "baseline_state": state, "selected_state": selected], options: [.sortedKeys])
        }
        let stateData = try JSONSerialization.data(withJSONObject: selected, options: [.sortedKeys])
        let receipt = try JSONSerialization.data(withJSONObject: ["schema_version": 1, "owner_id": ownerID.uuidString.lowercased(),
            "observation_id": observation, "baseline_analysis_id": baseline])
        var cloud = ObservationHistoryCloudClient(begin: { expected in
            #expect(expected == ownerID)
            return AccountBoundWorkLease(id: UUID(), session: AuthTransitionSession(userID: ownerID, isAnonymous: false))
        }, isCurrent: { _ in true }, finish: { _ in }, fetch: { _ in throw ObservationHistoryError.unavailable })
        cloud.enroll = { requested in
            didDispatch(); #expect(requested == observationID)
            if fault == "reply" { throw SharedMediaStorageFailure.unavailable }
            return receipt
        }
        cloud.fetchState = { request in #expect(request.observation_id == observation && request.analysis_id == nil); return stateData }
        cloud.reconcileEnrollment = { requested in
            #expect(requested == observationID)
            return try #require(pairData)
        }
        var service = ObservationHistoryEnrollmentService(cloud: cloud)
        var saves = 0
        service.save = { context in
            saves += 1
            if fault == "import" && saves == 2 { throw SharedMediaStorageFailure.unavailable }
            try context.save()
        }
        return try await service.enroll(observationID: observation,
            expectedOwnerID: ownerID, container: store.container, recovery: recovery)
    }

    @Test(.sharedProcessState(.offlineQueueManager))
    func boundedAttemptsKeepStatusAndReleaseOnlyVerifiedApplications() async throws {
        let (store, owner, first, firstAllocation) = try await allocatedFixture()
        var held: [Intent.Prepared] = []
        for index in 0..<PhotoPreparationPolicy.maximumPackages {
            let (prepared, allocation) = index == 0 ? (first, firstAllocation) : try await additionalAllocatedFixture(owner: owner, ownerID: store.ownerID)
            let candidate = try #require(await owner.discoverAppReceivedCandidates().first { $0.packageID == prepared.package.id })
            let interval = try #require(await owner.prepareAppRecoveryInterval(candidate))
            #expect(try await interval.settle(elapsed: .seconds(30)).acknowledged)
            let ack = try originalAcknowledgement(allocation)
            let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in ack })
            let acquisition = try completionAcquisition(admission)
            _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
            // A real local application save succeeds, but its readback reply is
            // lost. This does not simulate SQLite failure or a process crash.
            try owner.setMetadataFault { if $0 == .beforeReadback { throw SharedMediaStorageFailure.unavailable } }
            await #expect(throws: (any Error).self) {
                _ = try await owner.applyAppInitialResult(prepared) { _, _ in acquisition }
            }
            try owner.setMetadataFault(nil)
            #expect(owner.recoveryPresentationLive.retainedAttemptCountForTesting == index + 1)
            held.append(prepared)
        }
        let (next, allocation) = try await additionalAllocatedFixture(owner: owner, ownerID: store.ownerID)
        let candidate = try #require(await owner.discoverAppReceivedCandidates().first { $0.packageID == next.package.id })
        let before = try revision(store)
        var writes = 0, reads = 0
        try owner.setMetadataFault { if $0 == .beforeSave { writes += 1 } }
        let access = CaptureNativeRecoveryStatusAccess.app(isCurrent: { true }, owner: { owner }) { _, _, validate in
            try validate(); reads += 1; return Data("{\"status\":\"found\"}".utf8)
        }
        #expect(try await access.reserve(candidate) == nil)
        #expect(try await access.check(candidate))
        #expect(writes == 0 && reads == 1)
        #expect(try revision(store) == before)
        #expect(owner.recoveryPresentationLive.retainedAttemptCountForTesting == PhotoPreparationPolicy.maximumPackages)
        try owner.setMetadataFault(nil)
        // Exact replay is read-only and releases precisely one retained entry.
        let replay = try await owner.applyAppInitialResult(held[0]) { _, _ in Issue.record("Replay reacquired original result"); return nil }
        #expect(replay != nil)
        #expect(try revision(store) == before)
        #expect(owner.recoveryPresentationLive.retainedAttemptCountForTesting == PhotoPreparationPolicy.maximumPackages - 1)
        let interval = try #require(await owner.prepareAppRecoveryInterval(candidate))
        #expect(owner.recoveryPresentationLive.retainedAttemptCountForTesting == PhotoPreparationPolicy.maximumPackages)
        #expect(try await interval.settle(elapsed: .seconds(30)).acknowledged)
        for prepared in held.dropFirst() {
            #expect(try await owner.applyAppInitialResult(prepared) { _, _ in Issue.record("Replay reacquired original result"); return nil } != nil)
        }
        let ack = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(next) { _, _ in ack })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(next) { _, _ in acquisition }
        #expect(try await owner.applyAppInitialResult(next) { _, _ in acquisition } != nil)
        #expect(owner.recoveryPresentationLive.retainedAttemptCountForTesting == 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func additionalAllocatedFixture(owner: SharedMediaNativeOriginalOwner, ownerID: UUID) async throws -> (Intent.Prepared, SharedMediaNativePhotoAllocation) {
        let packageID = UUID(), draft = UUID(), bytes = PhotoPreparationTestHarness.image()
        let request = try await owner.prepareAppOriginal(packageID: packageID, draftGeneration: draft, ordinal: 0, kind: .picker)
        let acquired = try await owner.acquireAppOriginal(request) { bytes }
        let original = PhotoOriginalReference(ownerID: ownerID, packageID: packageID,
            referenceID: request.referenceID, assetID: request.assetID, assetGeneration: request.assetGeneration,
            draftGeneration: draft, referenceRevision: acquired.referenceRevision)
        let ready = try await owner.prepareAndDeliverAppPhoto(original: original,
            recipe: .init(format: .stillImage, isPro: false, cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0))
        let prepared = try await owner.stageAppReceiving(packageID: packageID, draftGeneration: draft,
            pairIDs: [ready.intent().pairID], photoAdmission: .init(authorization: .init(recipient: .gemini, validate: {})))
        _ = try await owner.receiveAppPrepared(prepared)
        return (prepared, try await allocateFixture(owner: owner, prepared: prepared))
    }

    @Test(arguments: [false, true])
    func settledPresentationSurvivesInitialPinsAndApplication(_ beforeAdmission: Bool) async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let ack = try originalAcknowledgement(allocation)
        let admission = try InitialCompletionDocuments.CpmAdmission(acknowledgement: ack, original: .saved(allocation))
        let acquisition = try completionAcquisition(admission)
        if !beforeAdmission { _ = try await owner.recoverAppInitialAdmission(prepared) { _, _ in ack } }
        let original = try stored(store)
        let candidate = try #require(await owner.discoverAppReceivedCandidates().first)
        let interval = try #require(await owner.prepareAppRecoveryInterval(candidate))
        #expect(interval.allowance == .seconds(30))
        #expect(owner.recoveryPresentationLive.retainedAttemptCountForTesting == 1)
        if beforeAdmission {
            await #expect(throws: (any Error).self) {
                _ = try await owner.recoverAppInitialAdmission(prepared) { _, _ in Issue.record("Active reservation crossed admission"); return ack }
            }
        } else {
            await #expect(throws: (any Error).self) {
                _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in Issue.record("Active reservation crossed completion"); return acquisition }
            }
        }
        #expect(try stored(store) == original)
        // Exhausted settled time still permits explicit completion; only a live
        // reservation prevents the handoff, not needsAttention itself.
        let settled = try await interval.settle(elapsed: beforeAdmission ? .milliseconds(1) : .seconds(30))
        #expect(settled.acknowledged && settled.presentation.activeReservationID == nil)
        #expect(settled.presentation.needsAttention == !beforeAdmission)
        let bytes = try settled.presentation.encoded()
        _ = try await owner.recoverAppInitialAdmission(prepared) { _, _ in ack }
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        let context = store.context(), queueID = prepared.queueID.uuidString.lowercased()
        let queue = try Fixture.one(context, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == queueID }))
        #expect(queue.recoveryPresentationData == bytes)
        let liability = try SharedMediaNativeReceivingRows.recoveryPresentation(bytes, prepared: prepared)
        #expect(liability.chargedBytes == 512)
        // A fully lost application return retains its attempt until exact replay;
        // an acknowledged post-save reconciliation can retire it immediately.
        if beforeAdmission {
            try owner.setMetadataFault { if $0 == .beforeReadback { throw SharedMediaStorageFailure.unavailable } }
            await #expect(throws: (any Error).self) {
                _ = try await owner.applyAppInitialResult(prepared) { _, _ in acquisition }
            }
            #expect(owner.recoveryPresentationLive.retainedAttemptCountForTesting == 1)
        } else {
            try owner.setMetadataFault { if $0 == .afterSave { throw SharedMediaStorageFailure.unavailable } }
        }
        if beforeAdmission { try owner.setMetadataFault(nil) }
        let applied = try #require(await owner.applyAppInitialResult(prepared) { _, _ in
            if beforeAdmission { Issue.record("Verified replay repeated result acquisition") }
            return acquisition
        })
        try owner.setMetadataFault(nil)
        #expect(owner.recoveryPresentationLive.retainedAttemptCountForTesting == 0)
        #expect(applied.receipt.format == .presentation && applied.receipt.presentationByteCount == bytes.count)
        try applied.receipt.requirePresentation(bytes)
        #expect(throws: (any Error).self) { try applied.receipt.requirePresentation(nil) }
        #expect(throws: (any Error).self) { try applied.receipt.requirePresentation(AnalysisRecoveryPresentation.initial(for: settled.presentation.identity).encoded()) }
        #expect(try store.context().fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        _ = try await enrollInitialFixture(store, prepared: prepared, acquisition: acquisition)
        let acknowledged = try #require(await owner.acknowledgeAppInitialHistory(prepared) { _, _ in acquisition })
        #expect(acknowledged.receipt == applied.receipt)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(store)
        let replay = try #require(await cold.applyAppInitialResult(prepared) { _, _ in Issue.record("Cold replay repeated result acquisition"); return nil })
        #expect(replay.receipt == applied.receipt)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func applicationReceiptBindsOriginalWithoutGrantingApplication() async throws {
        typealias Receipt = SharedMediaNativeConsumerCohort.InitialApplicationReceipt
        typealias Capacity = NativePhotoAllocationPoststate.ApplicationCapacity
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let ack = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in ack })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        let context = store.context(), id = store.packageID, inventoryID = store.inventoryID
        let row = try Fixture.one(context, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
        let inventory = try Fixture.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let original = Row(row), beforeRevision = inventory.revision
        let snapshot = try SharedMediaNativePhotoAllocationSnapshot.readInitial(original, inventory: inventory, context: context)
        let record = try LocalScanRecordFactory.makeInitialRecord(from: acquisition.result, speciesID: "",
            timestamp: Date(timeIntervalSince1970: 1), captureDate: Date(timeIntervalSince1970: 1),
            capturedMediaJSON: nil, coverImagePath: nil, fieldNotes: nil)
        record.mediaAuthorityRaw = "sharedDirectNativeInitialV1"; record.sharedMediaConsumerID = prepared.bindingID
        let baseline = try LocalScanRecordFactory.initialApplicationBaseline(record: record, result: acquisition.result)
        let receipt = try Receipt(snapshot: snapshot, row: row, acquisition: acquisition, baseline: baseline)
        try Capacity.preliminary(before: snapshot, context: context, inventory: inventory, availableBytes: { Int64.max })
        let measured = try Capacity.measured(before: snapshot, row: row, acquisition: acquisition, record: record,
            context: context, inventory: inventory, availableBytes: { Int64.max })
        #expect(measured.receipt == receipt && measured.original == snapshot.transaction.cohort)
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try Capacity.preliminary(before: snapshot, context: context, inventory: inventory, availableBytes: { 0 })
        }
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try Capacity.measured(before: snapshot, row: row, acquisition: acquisition, record: record,
                context: context, inventory: inventory, availableBytes: { 0 })
        }
        record.fieldNotes = String(repeating: "x", count: 740_000)
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try Capacity.measured(before: snapshot, row: row, acquisition: acquisition, record: record,
                context: context, inventory: inventory, availableBytes: { Int64.max })
        }
        record.fieldNotes = nil
        let bytes = try receipt.encoded()
        #expect(bytes.count <= Receipt.maximumBytes && Receipt.maximumBytes == 4096)
        #expect(try Receipt.decode(bytes) == receipt)
        #expect(receipt.observationID == prepared.observationID && receipt.inferenceGeneration == prepared.generation)
        #expect(receipt.resultDigest == acquisition.result.resultDigest && receipt.baselineByteCount == baseline.count)
        let changed = try Receipt(snapshot: snapshot, row: row, acquisition: acquisition, baseline: Data("later edit".utf8))
        #expect(changed.baselineSHA256 != receipt.baselineSHA256 && changed.originalRowSHA256 == receipt.originalRowSHA256)
        let maximum = try Receipt(snapshot: snapshot, row: row, acquisition: acquisition,
            baseline: Data(repeating: 0, count: Receipt.maximumBaselineBytes))
        #expect(try maximum.encoded().count <= Receipt.maximumBytes)
        for baseline in [Data(), Data(repeating: 0, count: Receipt.maximumBaselineBytes + 1)] {
            #expect(throws: (any Error).self) { try Receipt(snapshot: snapshot, row: row, acquisition: acquisition, baseline: baseline) }
        }
        let other = try completionAcquisition(admission, reasoning: "A different immutable result")
        #expect(throws: (any Error).self) { try Receipt(snapshot: snapshot, row: row, acquisition: other, baseline: baseline) }
        let digest = try Receipt.originalDigest(row)
        row.releaseStartData = Data()
        #expect(try Receipt.originalDigest(row) != digest) // nil and empty cannot collide.
        #expect(throws: (any Error).self) { try Receipt(snapshot: snapshot, row: row, acquisition: acquisition, baseline: baseline) }
        row.releaseStartData = nil
        row.revision += 1
        #expect(try Receipt.originalDigest(row) != digest)
        row.revision = original.revision
        #expect(try Receipt.originalDigest(row) == digest)
        context.rollback()
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(receipt.format == .presentation && receipt.presentationByteCount == 0)
        try receipt.requirePresentation(nil)
        #expect(throws: (any Error).self) { try receipt.requirePresentation(Data()) }
        var legacy = object
        legacy["format"] = "nativeInitialApplicationV1"
        legacy.removeValue(forKey: "presentationSHA256"); legacy.removeValue(forKey: "presentationByteCount")
        let legacyBytes = try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys, .withoutEscapingSlashes])
        let legacyReceipt = try Receipt.decode(legacyBytes)
        #expect(try legacyReceipt.encoded() == legacyBytes)
        try legacyReceipt.requirePresentation(nil)
        #expect(throws: (any Error).self) { try legacyReceipt.requirePresentation(Data()) }
        legacy["presentationByteCount"] = 0
        #expect(throws: (any Error).self) { try Receipt.decode(JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])) }
        for (key, value) in [("unexpected", "x" as Any), ("format", "unknown" as Any),
                             ("presentationByteCount", 513 as Any), ("presentationSHA256", "bad" as Any),
                             ("baselineByteCount", 0 as Any), ("resultDigest", "bad" as Any)] {
            var changed = object; changed[key] = value
            #expect(throws: (any Error).self) { try Receipt.decode(JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys])) }
        }
        #expect(throws: (any Error).self) { try Receipt.decode(Data(repeating: 0, count: Receipt.maximumBytes + 1)) }
        #expect(throws: (any Error).self) { try SharedMediaNativeConsumerCohort.decode(bytes) }
        #expect(try stored(store) == original && revision(store) == beforeRevision)
        #expect(try context.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func applicationCapacityPreservesChargedHeadroomLogicalPeersAndDisk() throws {
        typealias Capacity = NativePhotoAllocationPoststate.ApplicationCapacity
        let cap = PhotoPreparationPolicy.metadata, package = UUID(), peer = UUID()
        #expect(try Capacity.additionalMetadata(oldMetadata: cap - 17, measuredGrowth: nil) == 17)
        #expect(try Capacity.additionalMetadata(oldMetadata: cap - 17, measuredGrowth: 17) == 17)
        for growth in [-1, 18, Int64.max] {
            #expect(throws: SharedMediaStorageFailure.capacity) {
                try Capacity.additionalMetadata(oldMetadata: cap - 17, measuredGrowth: growth)
            }
        }
        for old in [-1, cap + 1, Int64.max] {
            #expect(throws: SharedMediaStorageFailure.capacity) { try Capacity.additionalMetadata(oldMetadata: old, measuredGrowth: nil) }
        }
        var totals = SharedMediaStoragePolicy.Totals()
        try totals.includePhotoPackage(id: package, bytes: PhotoPreparationPolicy.package - 17)
        try totals.includePhotoPackage(id: peer, bytes: PhotoPreparationPolicy.package)
        try totals.includePhotoPhysical(materialized: PhotoPreparationPolicy.durable - 117, reserved: 100)
        let before = totals, free = SharedMediaStoragePolicy.reserve + 117
        try totals.requirePhotoMetadataGrowth(packageID: package, bytes: 17, availableBytes: free)
        for (id, bytes, available) in [(package, Int64(18), free), (package, 17, free - 1),
                                       (peer, 1, free), (UUID(), 0, free)] {
            #expect(throws: SharedMediaStorageFailure.capacity) {
                try totals.requirePhotoMetadataGrowth(packageID: id, bytes: bytes, availableBytes: available)
            }
        }
        var physicalLimit = SharedMediaStoragePolicy.Totals()
        try physicalLimit.includePhotoPackage(id: package, bytes: 0)
        try physicalLimit.includePhotoPhysical(materialized: PhotoPreparationPolicy.durable, reserved: 0)
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try physicalLimit.requirePhotoMetadataGrowth(packageID: package, bytes: 1, availableBytes: Int64.max)
        }
        #expect(totals == before)
    }

    @Test func retainedInitialReaderPreservesLaterSelectionAndRejectsPartialOwnership() async throws {
        typealias Applied = SharedMediaNativePhotoAllocationSnapshot.Applied
        typealias Cohort = SharedMediaNativeConsumerCohort.AppliedInitial
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let ack = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in ack })
        let acquisition = try completionAcquisition(admission)
        _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        let c = store.context(), id = store.packageID, inventoryID = store.inventoryID
        let row = try Fixture.one(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
        let inventory = try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let original = Row(row)
        let snapshot = try SharedMediaNativePhotoAllocationSnapshot.readInitial(original, inventory: inventory, context: c)
        let rows = try SharedMediaNativeReceivingPhaseGraph.receivedRows(snapshot.transaction, context: c)
        let record = try LocalScanRecordFactory.makeInitialRecord(from: acquisition.result, speciesID: "",
            timestamp: Date(timeIntervalSince1970: 1), captureDate: Date(timeIntervalSince1970: 1),
            capturedMediaJSON: nil, coverImagePath: nil, fieldNotes: nil)
        record.mediaAuthorityRaw = "sharedDirectNativeInitialV1"; record.sharedMediaConsumerID = prepared.bindingID
        let baseline = try LocalScanRecordFactory.initialApplicationBaseline(record: record, result: acquisition.result)
        let receipt = try SharedMediaNativeConsumerCohort.InitialApplicationReceipt(snapshot: snapshot,
            row: row, acquisition: acquisition, baseline: baseline)
        let cohort = try Cohort(original: snapshot.transaction.cohort, receipt: receipt)
        let bytes = try cohort.encoded()
        #expect(try Cohort.decode(bytes) == cohort)
        #expect(cohort.historyHandoffRemainingAdvances == 1)
        for count in [0, 2, Int64.max] {
            var changed = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            changed["historyHandoffRemainingAdvances"] = count
            #expect(throws: (any Error).self) { try Cohort.decode(JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys])) }
        }
        #expect(throws: (any Error).self) { try SharedMediaNativeConsumerCohort.decode(bytes) }
        #expect(throws: (any Error).self) { try Cohort.decode(snapshot.transaction.cohort.encoded()) }
        var malformed = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        malformed["unexpected"] = true
        #expect(throws: (any Error).self) { try Cohort.decode(JSONSerialization.data(withJSONObject: malformed, options: [.sortedKeys])) }
        let package = try Fixture.one(c, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        let member = try Fixture.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        // Disposable fixture only. There is still no production application writer.
        rows.consumer.cohortData = bytes; rows.consumer.cohortSHA256 = try cohort.digest()
        rows.consumer.contractVersion = cohort.format.rawValue
        rows.consumer.kindRaw = "localScan"; rows.consumer.consumerID = prepared.observationID.uuidString.lowercased()
        rows.consumer.revision += 1; package.accountingTierRaw = "retained"; package.revision += 1
        c.insert(record); c.delete(member); c.delete(rows.queue); c.delete(rows.job); c.delete(rows.event)
        inventory.revision += 1; try c.save()
        let retained = try Applied.read(row, inventory: inventory, context: c)
        #expect(retained.row == original && retained.completion == acquisition.record && retained.cohort == cohort)
        #expect(throws: (any Error).self) { try SharedMediaNativePhotoAllocationSnapshot.readInitial(original, inventory: inventory, context: c) }
        #expect(throws: (any Error).self) { try SharedMediaNativeConsumerGraph.validateScoped(rows.consumer, context: c, format: .appV2) }
        // Descriptive later state, not qualification of V3 enrollment/import.
        record.fieldNotes = "Later notes é 🐾"; record.commonName = "Later reviewed display"
        record.analysisOwnerAccountID = prepared.profile.ownerID.uuidString.lowercased()
        record.selectedAnalysisID = UUID().uuidString.lowercased(); record.observationStateRevision = 7
        try c.save()
        let laterSelection = record.selectedAnalysisID
        #expect(try Applied.read(row, inventory: inventory, context: c).cohort == cohort)
        #expect(record.fieldNotes == "Later notes é 🐾" && record.selectedAnalysisID == laterSelection)
        #expect(Row(row) == original && !c.hasChanges)
        let terminalSummary = try SharedMediaNativeTerminalScan.read(container: store.container, inventoryID: inventoryID)
        #expect(terminalSummary.bytes == 0 && terminalSummary.consumptionAdvances == 0)
        #expect(terminalSummary.appliedHandoffAdvances == 1)
        try SharedMediaNativeReceivingCleanGraph.requireAggregateRunway(inventoryRevision: Int64.max - 1,
            witnesses: [], historical: terminalSummary)
        #expect(throws: (any Error).self) {
            try SharedMediaNativeReceivingCleanGraph.requireAggregateRunway(inventoryRevision: Int64.max,
                witnesses: [], historical: terminalSummary)
        }
        let namespace = try SharedMediaNativeTerminalIdentity.namespace(prepared, context: c)
        for identity in [prepared.operationID, prepared.eventID, prepared.bindingID] {
            #expect(throws: (any Error).self) {
                try SharedMediaNativeTerminalScan.requireAbsent([identity], container: store.container, inventoryID: inventoryID)
            }
        }
        try SharedMediaNativeTerminalScan.requireAbsent([UUID()], container: store.container, inventoryID: inventoryID)
        #expect(!namespace.all.isEmpty && !namespace.physical.isEmpty)
        #expect(throws: (any Error).self) {
            try SharedMediaNativeTerminalIdentity.auditAppliedPage([retained], live: [id: .initial(snapshot)],
                context: c, expectedHeader: retained.header, checkpoint: {})
        }
        func auditCurrent() async throws -> SharedMediaNativeScopedSnapshot {
            let expected = SharedMediaStorageSnapshot(generation: inventory.generation, revision: inventory.revision,
                phase: inventory.phaseRaw, cursor: inventory.cursor)
            return try await SharedMediaNativeScopedAudit(app: store.container, profile: prepared.profile,
                expected: expected, check: {}, betweenPages: {}).run()
        }
        let audited = try await auditCurrent()
        #expect(audited.pendingPackages == 0 && audited.consumers == 1)
        #expect(audited.allocations > 0 && audited.receipts > 0) // Still owned, not freed.
        try await checkRetainedReads(store, owner: owner, prepared: prepared, cohort: cohort)
        inventory.revision += 1; try c.save()
        #expect(throws: (any Error).self) { try retained.requireCurrent(context: c) }
        #expect(try Applied.read(row, inventory: inventory, context: c).cohort == cohort)
        record.analysisOwnerAccountID = UUID().uuidString.lowercased(); try c.save()
        #expect(throws: (any Error).self) { try Applied.read(row, inventory: inventory, context: c) }
        record.analysisOwnerAccountID = prepared.profile.ownerID.uuidString.lowercased(); try c.save()
        for fault in ["slot", "completion", "consumer", "revision", "scan", "package", "membership", "queue", "deletion"] {
            switch fault {
            case "slot": row.revision += 1
            case "completion": row.initialCompletionData = Data()
            case "consumer": rows.consumer.cohortSHA256 = String(repeating: "0", count: 64)
            case "revision": rows.consumer.revision = 2
            case "scan": record.sharedMediaConsumerID = nil
            case "package": package.revision += 1
            case "membership": c.insert(SharedMediaPendingMembershipRecord(packageID: id, inventoryID: inventoryID,
                inventoryGeneration: inventory.generation, ownerID: store.ownerID, draftGeneration: prepared.package.generation, membersData: cohort.original.membership))
            case "queue": c.insert(OfflineQueuedScan(id: prepared.queueID.uuidString.uppercased()))
            default: c.insert(PendingCloudDeletionTask(scanId: record.id.uppercased()))
            }
            // Dirty contexts are rejected before inspecting their partial graphs.
            #expect(throws: (any Error).self) { try Applied.read(row, inventory: inventory, context: c) }
            try c.save()
            #expect(throws: (any Error).self) { try Applied.read(row, inventory: inventory, context: c) }
            row.revision = original.revision; row.initialCompletionData = original.initialCompletionData
            rows.consumer.cohortSHA256 = try cohort.digest(); rows.consumer.revision = 1
            record.sharedMediaConsumerID = prepared.bindingID
            package.revision = try snapshot.transaction.freeze.commit.packageRevision + 1
            for item in try c.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()) { c.delete(item) }
            for item in try c.fetch(FetchDescriptor<OfflineQueuedScan>()) { c.delete(item) }
            for item in try c.fetch(FetchDescriptor<PendingCloudDeletionTask>()) { c.delete(item) }
            try c.save()
            #expect(try Applied.read(row, inventory: inventory, context: c).row == original)
        }
        c.delete(record); try c.save()
        #expect(throws: (any Error).self) { try Applied.read(row, inventory: inventory, context: c) }
        #expect(try c.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        await #expect(throws: (any Error).self) { try await auditCurrent() }
        // A separate disposable restoration isolates the reverse orphan-evidence
        // check. Production never recreates a deleted scan or receiving row.
        let restored = try LocalScanRecordFactory.makeInitialRecord(from: acquisition.result, speciesID: "",
            timestamp: Date(timeIntervalSince1970: 1), captureDate: Date(timeIntervalSince1970: 1),
            capturedMediaJSON: nil, coverImagePath: nil, fieldNotes: nil)
        restored.mediaAuthorityRaw = "sharedDirectNativeInitialV1"; restored.sharedMediaConsumerID = prepared.bindingID
        c.insert(restored); try c.save()
        #expect(try Applied.read(row, inventory: inventory, context: c).row == original)
        c.delete(row); try c.save()
        await #expect(throws: (any Error).self) { try await auditCurrent() }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func checkRetainedReads(_ store: SharedMediaNativeAppMetadataTests.Store, owner: SharedMediaNativeOriginalOwner,
                                    prepared: Intent.Prepared, cohort: SharedMediaNativeConsumerCohort.AppliedInitial) async throws {
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let intents = try frozen.entries.map { try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes) }
        let originalRow = try stored(store), originalRevision = try revision(store)
        for role in [SharedMediaNativeRetainedPhotoReadback.Role.ai, .display] {
            let value = try await owner.readRetainedAppPhotos(prepared, role: role)
            #expect(value.cohort == cohort && value.supportingBytes == frozen.supportingBytes)
            #expect(value.photos.map(\.pairID) == intents.map(\.pairID))
            for (photo, intent) in zip(value.photos, intents) {
                let input = role == .ai ? intent.ai : intent.display
                #expect(Int64(photo.bytes.count) == input.byteCount)
                #expect(SharedMediaAcquisitionEncoding.digest(photo.bytes) == input.sha256)
            }
        }
        await #expect(throws: (any Error).self) { try await owner.readReceivedAppPhotos(prepared) }
        #expect(try stored(store) == originalRow && revision(store) == originalRevision)
        for fault in ["consumer", "cancel", "account"] {
            // Exercise the retained branch at the actual sealed file await.
            let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
            try await owner.setAcquisitionEntryPause { if $0 == .readPair { await entered.open(); await release.wait() } }
            let reading = Task { try await owner.readRetainedAppPhotos(prepared, role: .display) }
            await entered.wait()
            let context = store.context(), id = prepared.bindingID
            let consumer = try Fixture.one(context, FetchDescriptor<SharedMediaConsumerRecord>(predicate: #Predicate { $0.id == id }))
            var transition: Task<Bool, Never>?
            switch fault {
            case "consumer": consumer.revision = 2; try context.save()
            case "cancel": reading.cancel()
            default:
                transition = Task { await owner.invalidateAndAwaitForAccountTransition() }
                while !owner.heldOriginalAdmissionClosedForTesting { await Task.yield() }
            }
            await release.open()
            await #expect(throws: (any Error).self) { try await reading.value }
            if fault == "consumer" { consumer.revision = 1; try context.save() }
            if let transition { #expect(await transition.value) }
            else { try await owner.setAcquisitionEntryPause(nil) }
            #expect(try stored(store) == originalRow && revision(store) == originalRevision)
        }
    }

    @Test func retainedNamespaceAllowsOnlyExactPhysicalSharingInBothOrders() throws {
        typealias Identity = SharedMediaNativeTerminalIdentity
        let asset = UUID(), acquisition = UUID(), generation = UUID(), owner = UUID()
        let physical = Identity.Physical(assetID: asset, acquisitionID: acquisition,
            generation: generation, ownerID: owner, identityDigest: String(repeating: "a", count: 64))
        let first = Identity.Namespace(all: [UUID(), asset, acquisition], physical: [physical])
        let shared = Identity.Namespace(all: [UUID(), asset, acquisition], physical: [physical])
        try Identity.requireCompatible(first, shared); try Identity.requireCompatible(shared, first)
        let wrongGeneration = Identity.Physical(assetID: asset, acquisitionID: acquisition,
            generation: UUID(), ownerID: owner, identityDigest: physical.identityDigest)
        let wrongAsset = Identity.Physical(assetID: UUID(), acquisitionID: acquisition,
            generation: generation, ownerID: owner, identityDigest: physical.identityDigest)
        for other in [Identity.Namespace(all: first.all, physical: first.physical),
                      Identity.Namespace(all: [asset], physical: []),
                      Identity.Namespace(all: [asset, acquisition], physical: [wrongGeneration]),
                      Identity.Namespace(all: [wrongAsset.assetID, acquisition], physical: [wrongAsset])] {
            #expect(throws: SharedMediaStorageFailure.conflict) { try Identity.requireCompatible(first, other) }
            #expect(throws: SharedMediaStorageFailure.conflict) { try Identity.requireCompatible(other, first) }
        }
    }

    private func allocatedFixture() async throws -> (SharedMediaNativeAppMetadataTests.Store, SharedMediaNativeOriginalOwner, Intent.Prepared, SharedMediaNativePhotoAllocation) {
        let (store, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        return (store, owner, p, try await allocateFixture(owner: owner, prepared: p))
    }
    private func allocateFixture(owner: SharedMediaNativeOriginalOwner, prepared: Intent.Prepared) async throws -> SharedMediaNativePhotoAllocation {
        try await owner.allocateAppPhotoRoles(prepared, backendBinding: true, authorizeCreate: { prepared, _ in
            .init(recipient: try #require(prepared.photoAdmission).expectedProcessorPermission, validate: {})
        }) { request, validate, settle in
            try validate(); try settle()
            let entries = try SharedMediaNativePhotoRoleMapping.references(request.allocation.claim).enumerated().map { index, reference in
                SharedMediaNativePhotoRoleMapping.Entry(photoOrdinal: index / 3,
                    role: SharedMediaNativePhotoRoleMapping.Role.allCases[index % 3], referenceID: reference, objectID: UUID())
            }
            return .allocated(.init(receipt: .init(assignmentDigest: String(repeating: "a", count: 64),
                createdAtMilliseconds: 1, expiresAtMilliseconds: 1_800_001), entries: entries,
                backendBinding: InitialPhotoUploadTicketTests().binding()))
        }
    }
    private func stored(_ store: SharedMediaNativeAppMetadataTests.Store) throws -> Row {
        let id = store.packageID
        return .init(try Fixture.one(store.context(), FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id })))
    }
    private func revision(_ store: SharedMediaNativeAppMetadataTests.Store) throws -> Int64 {
        try SharedMediaNativeReceivingStagingTests().inventory(store).revision
    }

    @Test func admissionSaveReplayAmbiguityAndRestartPreserveOriginal() async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let original = try stored(store), firstRevision = try revision(store), ack = try originalAcknowledgement(allocation)
        let absent = try await owner.recoverAppInitialAdmission(prepared) { current, validate in
            try validate(); #expect(current == allocation); return nil
        }
        let afterAbsence = try stored(store), afterAbsenceRevision = try revision(store)
        #expect(absent == nil && afterAbsence == original && afterAbsenceRevision == firstRevision)
        try owner.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.unavailable } }
        await #expect(throws: (any Error).self) { _ = try await owner.recoverAppInitialAdmission(prepared) { _, _ in ack } }
        #expect(try stored(store) == original && revision(store) == firstRevision)
        try owner.setMetadataFault { if $0 == .afterSave { throw SharedMediaStorageFailure.unavailable } }
        let pinned = try await owner.recoverAppInitialAdmission(prepared) { current, validate in
            try validate(); #expect(current == allocation); return ack
        }
        let admission = try #require(pinned)
        let saved = try stored(store)
        let savedRevision = try revision(store)
        #expect(saved == Row(admitting: admission, from: original) && savedRevision == firstRevision + 1)
        try owner.setMetadataFault { if $0 == .beforeSave { Issue.record("Exact admission replay must not save") } }
        #expect(try await owner.recoverAppInitialAdmission(prepared) { _, _ in ack } == admission)
        var changed = try #require(InitialAnalysisCanonical.parse(ack).object)
        changed["admission_receipt_id"] = .string(UUID().uuidString.lowercased())
        let different = try InitialAnalysisCanonical.encode(.object(changed))
        await #expect(throws: SharedMediaStorageFailure.conflict) { _ = try await owner.recoverAppInitialAdmission(prepared) { _, _ in different } }
        #expect(try stored(store) == saved && revision(store) == firstRevision + 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        await #expect(throws: (any Error).self) { _ = try await owner.recoverAppInitialAdmission(prepared) { _, _ in Issue.record("Closed account reached reader"); return ack } }
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(store)
        #expect(try await cold.recoverAppInitialAdmission(prepared) { _, validate in try validate(); return ack } == admission)
        #expect(try stored(store) == saved && revision(store) == firstRevision + 1)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func admissionSealRejectsSameRowAndExtraDirtyWrites(_ completing: Bool) async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let ack = try originalAcknowledgement(allocation)
        var acquisition: InitialCompletionDocuments.CpmAcquisition?
        if completing {
            let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in ack })
            acquisition = try completionAcquisition(admission)
        }
        let original = try stored(store), originalRevision = try revision(store)
        let id = store.packageID, inventoryID = store.inventoryID
        let context = store.context()
        let row = try Fixture.one(context, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
        let inventory = try Fixture.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let snapshot = try SharedMediaNativePhotoAllocationSnapshot.initialCandidate(prepared, context: context, inventory: inventory)
        let seal: NativePhotoAllocationPoststate.InitialPin
        if let acquisition { seal = try .init(before: snapshot, acquisition: acquisition, row: row, inventory: inventory, context: context) }
        else { seal = try .init(before: snapshot, acknowledgement: ack, row: row, inventory: inventory, context: context) }
        try seal.requireReservation(context, inventory: inventory, availableBytes: { Int64.max })
        row.initialAdmissionData = seal.after.initialAdmissionData; row.initialAdmissionSHA256 = seal.after.initialAdmissionSHA256
        row.initialCompletionData = seal.after.initialCompletionData; row.initialCompletionSHA256 = seal.after.initialCompletionSHA256
        inventory.revision += 1; try seal.validate(context, row: row, inventory: inventory)
        let mutations: [(SharedMediaReceivingIntentRecord) -> Void] = [
            { $0.preparedData = Data() }, { $0.resultData = Data() }, { $0.allocationData = Data() },
            { $0.initialAdmissionData = Data() }, { $0.initialAdmissionSHA256 = "partial" },
            { $0.initialCompletionData = Data() }, { $0.initialCompletionSHA256 = "partial" },
            { $0.releaseStartData = Data() }, { $0.revision += 1 }, { $0.operationID = UUID() }
        ]
        for mutate in mutations {
            mutate(row)
            #expect(throws: SharedMediaStorageFailure.conflict) { try seal.validate(context, row: row, inventory: inventory) }
            row.preparedData = original.preparedData; row.resultData = original.resultData; row.allocationData = original.allocationData
            row.initialAdmissionData = seal.after.initialAdmissionData; row.initialAdmissionSHA256 = seal.after.initialAdmissionSHA256
            row.initialCompletionData = seal.after.initialCompletionData; row.initialCompletionSHA256 = seal.after.initialCompletionSHA256; row.releaseStartData = nil
            row.revision = original.revision; row.operationID = original.operationID
            try seal.validate(context, row: row, inventory: inventory)
        }
        let package = try Fixture.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        package.revision += 1
        #expect(throws: SharedMediaStorageFailure.conflict) { try seal.validate(context, row: row, inventory: inventory) }
        context.rollback()
        #expect(try stored(store) == original && revision(store) == originalRevision)
        #expect(prepared.package.id == id && !context.hasChanges)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func admissionPeerSurvivesIndependentEditAndRejectsLatePeerMutation() async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let second = UUID(), draft = UUID(), ack = try originalAcknowledgement(allocation)
        let request = try await owner.prepareAppOriginal(packageID: second, draftGeneration: draft, ordinal: 0, kind: .picker)
        let image = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireAppOriginal(request) { image }
        _ = try await owner.recoverAppInitialAdmission(prepared) { _, _ in ack }
        let saved = try stored(store)
        let edit = try await owner.prepareAppMetadata(packageID: second, draftGeneration: draft, contexts: [.init(freeText: "Later independent selection")])
        _ = try await owner.saveAppMetadata(edit)
        #expect(try stored(store) == saved)
        let before = try store.package(second).supportingContextData
        let next = try await owner.prepareAppMetadata(packageID: second, draftGeneration: draft, contexts: [.init(freeText: "Must not commit")])
        var reached = false
        try owner.setMetadataFault { boundary in
            guard boundary == .beforeSave else { return }; reached = true
            let context = store.context(), id = store.packageID
            let row = try Fixture.one(context, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
            row.initialCompletionData = Data(); try context.save()
        }
        await #expect(throws: (any Error).self) { _ = try await owner.saveAppMetadata(next) }
        let after = try store.package(second).supportingContextData
        #expect(reached && after == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func admissionReservesExactDiskAndRevisionRunway(_ completing: Bool) async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let ack = try originalAcknowledgement(allocation), id = store.packageID, inventoryID = store.inventoryID
        var acquisition: InitialCompletionDocuments.CpmAcquisition?
        if completing {
            let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in ack })
            acquisition = try completionAcquisition(admission)
        }
        let original = try stored(store)
        func seal() throws -> (ModelContext, SharedMediaInventoryRecord, NativePhotoAllocationPoststate.InitialPin) {
            let context = store.context()
            let row = try Fixture.one(context, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
            let inventory = try Fixture.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            let before = try SharedMediaNativePhotoAllocationSnapshot.initialCandidate(prepared, context: context, inventory: inventory)
            let value: NativePhotoAllocationPoststate.InitialPin
            if let acquisition { value = try .init(before: before, acquisition: acquisition, row: row, inventory: inventory, context: context) }
            else { value = try .init(before: before, acknowledgement: ack, row: row, inventory: inventory, context: context) }
            return (context, inventory, value)
        }
        let (context, inventory, initial) = try seal()
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory, ownerID: store.ownerID, format: .appV2)
        var totals = budget.totals
        try totals.includePhotoPhysical(materialized: 0, reserved: completing ? 0 : Int64(ack.count + 64 + 197_533))
        // Use the policy's own exact availability requirement, not an arbitrary low clamp.
        var lower: Int64 = 0, upper = Int64.max
        while lower < upper {
            let midpoint = lower + (upper - lower) / 2
            if (try? totals.checkAvailable(midpoint)) != nil { upper = midpoint }
            else { lower = midpoint + 1 }
        }
        let required = lower
        #expect(throws: (any Error).self) { try initial.requireReservation(context, inventory: inventory, availableBytes: { required - 1 }) }
        try initial.requireReservation(context, inventory: inventory, availableBytes: { required })
        let revision = inventory.revision
        inventory.revision = Int64.max - allocation.remainingAdvances - (completing ? 0 : 1); try context.save()
        #expect(throws: (any Error).self) {
            let (tooLate, lateInventory, late) = try seal()
            try late.requireReservation(tooLate, inventory: lateInventory, availableBytes: { Int64.max })
        }
        inventory.revision -= 1; try context.save()
        let (last, lastInventory, final) = try seal()
        try final.requireReservation(last, inventory: lastInventory, availableBytes: { Int64.max })
        inventory.revision = revision; try context.save()
        #expect(try stored(store) == original)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        #expect(prepared.package.id == id)
    }

    @Test(arguments: ["cancel", "account", "saved"])
    func suspendedAdmissionReplyCannotCrossOriginalFence(_ fault: String) async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let original = try stored(store), ack = try originalAcknowledgement(allocation)
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        let operation = Task {
            try await owner.recoverAppInitialAdmission(prepared) { _, _ in
                await entered.open(); await release.wait(); return ack
            }
        }
        await entered.wait()
        var transition: Task<Bool, Never>?
        switch fault {
        case "cancel": operation.cancel()
        case "saved":
            let context = store.context(), id = store.packageID
            let row = try Fixture.one(context, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
            row.operationID = UUID(); try context.save()
        default:
            transition = Task { await owner.invalidateAndAwaitForAccountTransition() }
            while !owner.heldOriginalAdmissionClosedForTesting { await Task.yield() }
        }
        await release.open()
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        let saved = try stored(store)
        #expect(saved.initialAdmissionData == nil && saved.initialAdmissionSHA256 == nil)
        #expect(saved.preparedData == original.preparedData && saved.resultData == original.resultData && saved.allocationData == original.allocationData)
        if let transition { #expect(await transition.value) }
        else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
    }

    @Test func completionSaveReplayAmbiguityAndRestartPreserveOriginal() async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let ack = try originalAcknowledgement(allocation)
        await #expect(throws: SharedMediaStorageFailure.closed) {
            _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in Issue.record("Unadmitted completion reader"); return nil }
        }
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in ack })
        let acquisition = try completionAcquisition(admission)
        let original = try stored(store), firstRevision = try revision(store)
        let other = try completionAcquisition(admission, reasoning: "Different retained result")
        #expect(throws: (any Error).self) {
            _ = try InitialCompletionDocuments.CpmAcquisition(result: other.result,
                documents: .init(receipt: acquisition.record.receipt, projection: acquisition.record.projection), admission: admission)
        }
        var foreignReply = try #require(InitialAnalysisCanonical.parse(ack).object)
        foreignReply["admission_receipt_id"] = .string(UUID().uuidString.lowercased())
        let foreignAdmission = try InitialCompletionDocuments.CpmAdmission(
            acknowledgement: InitialAnalysisCanonical.encode(.object(foreignReply)), original: .saved(allocation))
        let foreign = try completionAcquisition(foreignAdmission)
        await #expect(throws: (any Error).self) {
            _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in foreign }
        }
        #expect(try stored(store) == original && revision(store) == firstRevision)
        let absent = try await owner.recoverAppInitialCompletion(prepared) { current, validate in
            try validate(); #expect(current == admission); return nil
        }
        #expect(absent == nil)
        #expect(try stored(store) == original && revision(store) == firstRevision)
        try owner.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.unavailable } }
        await #expect(throws: (any Error).self) {
            _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition }
        }
        #expect(try stored(store) == original && revision(store) == firstRevision)
        try owner.setMetadataFault { if $0 == .afterSave { throw SharedMediaStorageFailure.unavailable } }
        let pinned = try await owner.recoverAppInitialCompletion(prepared) { current, validate in
            try validate(); #expect(current == admission); return acquisition
        }
        let saved = try stored(store)
        #expect(pinned == acquisition.record && saved == Row(completing: acquisition.record, from: original))
        #expect(try revision(store) == firstRevision + 1)
        try owner.setMetadataFault { if $0 == .beforeSave { Issue.record("Completion replay must not save") } }
        #expect(try await owner.recoverAppInitialCompletion(prepared) { _, _ in acquisition } == pinned)
        #expect(try await owner.recoverAppInitialCompletion(prepared) { _, _ in nil } == pinned)
        let changed = try completionAcquisition(admission, reasoning: "Another valid but different synthetic result")
        await #expect(throws: SharedMediaStorageFailure.conflict) {
            _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in changed }
        }
        #expect(try stored(store) == saved && revision(store) == firstRevision + 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        await #expect(throws: (any Error).self) {
            _ = try await owner.recoverAppInitialCompletion(prepared) { _, _ in Issue.record("Closed account reached completion reader"); return acquisition }
        }
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(store)
        #expect(try await cold.recoverAppInitialCompletion(prepared) { _, validate in try validate(); return acquisition } == pinned)
        #expect(try stored(store) == saved && revision(store) == firstRevision + 1)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["cancel", "account", "saved"])
    func suspendedCompletionReplyCannotCrossOriginalFence(_ fault: String) async throws {
        let (store, owner, prepared, allocation) = try await allocatedFixture()
        let ack = try originalAcknowledgement(allocation)
        let admission = try #require(await owner.recoverAppInitialAdmission(prepared) { _, _ in ack })
        let original = try stored(store), acquisition = try completionAcquisition(admission)
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        let operation = Task {
            try await owner.recoverAppInitialCompletion(prepared) { _, _ in
                await entered.open(); await release.wait(); return acquisition
            }
        }
        await entered.wait()
        var transition: Task<Bool, Never>?
        switch fault {
        case "cancel": operation.cancel()
        case "saved":
            let context = store.context(), id = store.packageID
            let row = try Fixture.one(context, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
            row.operationID = UUID(); try context.save()
        default:
            transition = Task { await owner.invalidateAndAwaitForAccountTransition() }
            while !owner.heldOriginalAdmissionClosedForTesting { await Task.yield() }
        }
        await release.open()
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        let saved = try stored(store)
        #expect(saved.initialCompletionData == nil && saved.initialCompletionSHA256 == nil)
        #expect(saved.initialAdmissionData == original.initialAdmissionData && saved.preparedData == original.preparedData && saved.resultData == original.resultData && saved.allocationData == original.allocationData)
        if let transition { #expect(await transition.value) }
        else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
    }

    /// Synthetic canonical response shared by native transport/application
    /// checks; this is not a captured SQL or hosted response.
    private func completionWire(_ admission: InitialCompletionDocuments.CpmAdmission,
                                acquisition: InitialCompletionDocuments.CpmAcquisition) throws -> Data {
        let wire: [String: InitialAnalysisCanonical.Value] = [
            "version": .integer(1), "outcome": .string("found"),
            "admission_canonical": .string(String(decoding: admission.admission, as: UTF8.self)),
            "reference_canonical": .string(String(decoding: acquisition.result.reference, as: UTF8.self)),
            "original_provenance_canonical": .string(String(decoding: acquisition.result.provenance, as: UTF8.self)),
            "receipt_canonical": .string(String(decoding: acquisition.record.receipt, as: UTF8.self)),
            "projection_canonical": .string(String(decoding: acquisition.record.projection, as: UTF8.self)),
            "result_canonical": .string(String(decoding: acquisition.result.result, as: UTF8.self)),
            "result_digest": .string(acquisition.result.resultDigest), "provenance_digest": .string(acquisition.result.provenanceDigest)]
        return try InitialAnalysisCanonical.encode(.object(wire))
    }

    private func completionAcquisition(_ admission: InitialCompletionDocuments.CpmAdmission,
                                       reasoning: String? = nil) throws -> InitialCompletionDocuments.CpmAcquisition {
        struct FixtureFile: Decodable {
            struct Vector: Decodable {
                struct Evidence: Decodable { let result_canonical: String }
                let evidence: Evidence
            }
            let retained_results: [Vector]
        }
        let url = try #require(Bundle(for: InitialBindingFixtureAnchor.self).url(forResource: "InitialCompletionFixtures", withExtension: "json"))
        let fixture = try #require(JSONDecoder().decode(FixtureFile.self, from: Data(contentsOf: url)).retained_results.first)
        let record = try completionRecord(admission)
        let reference = try #require(InitialAnalysisCanonical.parse(record.reference).object)
        var result = try #require(InitialAnalysisCanonical.parse(Data(fixture.evidence.result_canonical.utf8)).object)
        for key in ["scan_id", "invocation_id", "submission_digest", "config_digest", "funding_binding_digest"] { result[key] = reference[key] }
        var data = try #require(result["data"]?.object)
        data["scan_id"] = reference["scan_id"]
        if let reasoning { data["ai_reasoning"] = .string(reasoning) }
        result["data"] = .object(data)
        let resultBytes = try InitialAnalysisCanonical.encode(.object(result))
        let digest = SharedMediaAcquisitionEncoding.digest(Data("merian.initial-analysis.result.v1\n".utf8) + resultBytes)
        let retained = try InitialRetainedResult(reference: record.reference, result: resultBytes, provenance: record.originalProvenance,
            resultDigest: digest, provenanceDigest: SharedMediaAcquisitionEncoding.digest(Data("merian.initial-analysis.result-provenance.v1\n".utf8) + record.originalProvenance),
            expectedReference: record.reference, originalProvenance: record.originalProvenance)
        var r = try #require(InitialAnalysisCanonical.parse(record.receipt).object)
        var p = try #require(InitialAnalysisCanonical.parse(record.projection).object)
        r["result_digest"] = .string(digest); p["result_digest"] = .string(digest)
        let projection = try InitialAnalysisCanonical.encode(.object(p))
        r["completion_projection_digest"] = .string(SharedMediaAcquisitionEncoding.digest(Data("merian.initial-analysis.completion-projection.v1\n".utf8) + projection))
        return try .init(result: retained,
            documents: .init(receipt: InitialAnalysisCanonical.encode(.object(r)), projection: projection), admission: admission)
    }

    private func completionRecord(_ admission: InitialCompletionDocuments.CpmAdmission) throws -> InitialCompletionDocuments.CpmRecoveryRecord {
        struct FixtureFile: Decodable {
            struct Record: Decodable { let receipt: String, projection: String, reference: String, provenance: String }
            let recovery_record: Record
        }
        let url = try #require(Bundle(for: InitialBindingFixtureAnchor.self).url(forResource: "InitialCompletionFixtures", withExtension: "json"))
        let fixture = try JSONDecoder().decode(FixtureFile.self, from: Data(contentsOf: url)).recovery_record
        let a = try #require(InitialAnalysisCanonical.parse(admission.admission).object)
        var r = try #require(InitialAnalysisCanonical.parse(Data(fixture.receipt.utf8)).object)
        var p = try #require(InitialAnalysisCanonical.parse(Data(fixture.projection.utf8)).object)
        for (key, value) in a { r[key] = value }
        r["operation_id"] = a["scan_id"]
        p["owner_id"] = a["owner_id"]; p["scan_id"] = a["scan_id"]
        var capture = try #require(p["capture_context"]?.object)
        capture["submission_digest"] = a["submission_digest"]; p["capture_context"] = .object(capture)
        let projection = try InitialAnalysisCanonical.encode(.object(p))
        r["completion_projection_digest"] = .string(SharedMediaAcquisitionEncoding.digest(
            Data("merian.initial-analysis.completion-projection.v1\n".utf8) + projection))
        var reference = try #require(InitialAnalysisCanonical.parse(Data(fixture.reference.utf8)).object)
        for key in reference.keys where key != "invocation_id" { reference[key] = r[key] }
        return try .init(reference: InitialAnalysisCanonical.encode(.object(reference)),
            originalProvenance: Data(fixture.provenance.utf8),
            documents: .init(receipt: InitialAnalysisCanonical.encode(.object(r)), projection: projection), admission: admission)
    }

    func originalAcknowledgement(_ allocation: SharedMediaNativePhotoAllocation) throws -> Data {
        typealias V = InitialAnalysisCanonical.Value
        let original = try InitialCompletionDocuments.CpmBinding.saved(allocation)
        let candidate = try #require(InitialAnalysisCanonical.parse(Data(original.candidateCanonical.utf8)).object)
        let contentText = try #require(candidate["content_canonical"]?.string)
        let content = try #require(InitialAnalysisCanonical.parse(Data(contentText.utf8)).object)
        let contexts = try #require(content["contexts"]?.array)
        let contextBytes = try InitialAnalysisCanonical.encode(.array(contexts))
        let hash = String(repeating: "c", count: 64)
        let admission = try InitialAnalysisCanonical.encode(.object([
            "version": .integer(1), "owner_id": .string(original.ownerID), "scan_id": .string(original.scanID),
            "route": .string("identify-multimodal"), "input_schema_version": .integer(2),
            "submission_digest": .string(original.contentDigest), "config_digest": .string(hash),
            "funding_binding_id": .string(UUID().uuidString.lowercased()), "funding_binding_digest": .string(hash),
            "funding_binding_version": .integer(1), "ordered_description_count": .integer(Int64(contexts.count)),
            "ordered_description_digest": .string(SharedMediaAcquisitionEncoding.digest(
                Data("merian.initial-analysis.cpm-photo-contexts.v1\n".utf8) + contextBytes)),
        ]))
        return try InitialAnalysisCanonical.encode(V.object([
            "version": .integer(1), "variant": .string("cpm_completion_admission_v1"), "authority": .string("none"),
            "owner_id": .string(original.ownerID), "scan_id": .string(original.scanID),
            "candidate_digest": .string(original.candidateDigest), "assignment_digest": .string(original.assignmentDigest),
            "backend_generation": .string(original.backendGeneration), "backend_configuration_digest": .string(original.backendConfigurationDigest),
            "admission_receipt_id": .string(UUID().uuidString.lowercased()), "admission_receipt_digest": .string(hash),
            "admission_canonical": .string(try #require(String(data: admission, encoding: .utf8))),
        ]))
    }

    private func set(_ row: SharedMediaReceivingIntentRecord, completion: Bool, data: Data?, digest: String?) {
        if completion { row.initialCompletionData = data; row.initialCompletionSHA256 = digest }
        else { row.initialAdmissionData = data; row.initialAdmissionSHA256 = digest }
    }

    @Test(arguments: [false, true])
    func originalServerFieldsBlockStagedStartAndColdRecovery(_ completion: Bool) async throws {
        let helper = SharedMediaNativeReleaseStartOwnerTests()
        let (store, owner, _, admission) = try await helper.fixture()
        let request = admission.request
        _ = try await owner.stageAppRelease(admission)
        for (data, digest) in variants {
            let context = store.context(), slot = try helper.record(store, context)
            let original = Row(slot)
            set(slot, completion: completion, data: data, digest: digest); try context.save()
            let blocked = Row(slot)
            #expect(throws: SharedMediaStorageFailure.closed) { _ = try helper.staged(store) }
            await #expect(throws: SharedMediaStorageFailure.closed) { _ = try await owner.startAppRelease(request) }
            #expect(try helper.row(store) == blocked)
            set(slot, completion: completion, data: nil, digest: nil); try context.save()
            #expect(try helper.row(store) == original)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        // Cold opening audits the persisted liability before granting dispatch.
        // The prior owner must release its store fence before testing that gate.
        for (data, digest) in variants {
            let context = store.context(), slot = try helper.record(store, context)
            let original = Row(slot)
            set(slot, completion: completion, data: data, digest: digest); try context.save()
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
            set(slot, completion: completion, data: nil, digest: nil); try context.save()
            #expect(try helper.row(store) == original)
        }
    }

    @Test(arguments: [false, true])
    func originalServerFieldsBlockReleaseOrphanAuditAndPurge(_ completion: Bool) async throws {
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
                set(slot, completion: completion, data: data, digest: hash); try c.save()
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
                    set(slot, completion: completion, data: nil, digest: nil)
                    #expect(Row(slot) == original)
                }
                try c.save(); try await audit(); _ = try f.read()
            }
        }
    }
    @Test func identityQueriesPreserveOptionalAliasesAndSelectiveBounds() async throws {
        let (_, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(staged: false)
        let prepared = try Intent.Prepared(request)
        let key = SharedMediaNativeReceivingRows.CollisionKey(prepared)
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let context = ModelContext(container); context.autosaveEnabled = false
        // More irrelevant rows than the receiving fetch limit: nil/nonmatching
        // reverse identities must not broaden this to a scan of all job rows.
        for index in 0..<4 {
            context.insert(OfflineJobRecord(id: UUID().uuidString, kind: .scanIngestion,
                subjectId: index.isMultiple(of: 2) ? nil : UUID().uuidString))
            context.insert(OfflineQueueEvent(id: UUID().uuidString, jobId: nil,
                scanId: index.isMultiple(of: 2) ? nil : UUID().uuidString, kind: .queued))
        }
        try context.save()
        func requireAbsent() throws {
            try SharedMediaNativeReceivingRows.requireAbsent(key, in: context)
            try SharedMediaNativeReleaseStageIdentity.direct(prepared.queueID, context: context)
            try SharedMediaNativeReleaseStageIdentity.direct(prepared.observationID, context: context)
        }
        try requireAbsent()
        for identity in Set([prepared.queueID, prepared.observationID]) {
            for alias in [identity.uuidString.lowercased(), identity.uuidString.uppercased()] {
                let job = OfflineJobRecord(id: UUID().uuidString, kind: .scanIngestion, subjectId: alias)
                context.insert(job)
                #expect(throws: SharedMediaStorageFailure.conflict) {
                    try SharedMediaNativeReceivingRows.requireAbsent(key, in: context)
                }
                #expect(throws: SharedMediaStorageFailure.conflict) {
                    try SharedMediaNativeReleaseStageIdentity.direct(identity, context: context)
                }
                context.delete(job); try context.save(); try requireAbsent()
                for reverseJob in [false, true] {
                    let event = OfflineQueueEvent(id: UUID().uuidString,
                        jobId: reverseJob ? "scan-ingestion:" + alias : nil,
                        scanId: reverseJob ? nil : alias, kind: .queued)
                    context.insert(event)
                    #expect(throws: SharedMediaStorageFailure.conflict) {
                        try SharedMediaNativeReceivingRows.requireAbsent(key, in: context)
                    }
                    #expect(throws: SharedMediaStorageFailure.conflict) {
                        try SharedMediaNativeReleaseStageIdentity.direct(identity, context: context)
                    }
                    context.delete(event); try context.save(); try requireAbsent()
                }
            }
        }
        #expect(!context.hasChanges)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

}
