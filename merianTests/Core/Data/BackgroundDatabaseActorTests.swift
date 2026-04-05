import Testing
import SwiftData
import Foundation
@testable import Merian

@MainActor
struct BackgroundDatabaseActorTests {
    
    // Helper to create an isolated SwiftData container caching out to disk due to iOS 18 simulator array appending bugs.
    @MainActor
    private func createIsolatedContainer() throws -> ModelContainer {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
    }

    @Test func testBackgroundActorIsolatesSendablePayloadsDynamically() async throws {
        // Arrange
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let queuedScan = OfflineQueuedScan(localImagePaths: ["isolation_1.jpg", "isolation_2.jpg"])
        context.insert(queuedScan)
        try context.save()

        // Act: Invoke the actor entirely abstracted off the @MainActor through Task.detached
        let payloads = await Task.detached {
            let actor = BackgroundDatabaseActor(modelContainer: container)
            return await actor.fetchPendingScans(limit: 5)
        }.value

        // Assert: Ensure execution directly mapped Offline queues into Sendable structs correctly preventing Main Thread locks
        #expect(payloads.count == 1, "Background actor MUST safely extract database references natively")
        #expect(payloads.first?.localImagePaths.count == 2, "Actor isolation boundary MUST preserve deeply nested Array metadata cleanly")
        #expect(payloads.first?.id == queuedScan.id, "Sendable Payload struct MUST explicitly carry the offline scan UUID")
    }

    // MARK: - updateScanWithOverride: V29 identification review persistence

    @Test func testUpdateScanWithOverrideSetsOverrideString() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "override-actor-test",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanWithOverride(scanId: scanId, override: "Procyon cancrivorus", confirmed: false)

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.userIdentificationOverride == "Procyon cancrivorus", "updateScanWithOverride must persist the override name")
        #expect(fetched?.userConfirmedIdentification == false, "confirmed must be false when only override is set")
    }

    @Test func testUpdateScanWithOverrideClearsWithNil() async throws {
        // Simulate resetting a previously-overridden scan.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "clear-override-test",
            scientificName: "Procyon cancrivorus",
            commonName: "Crab-eating Raccoon",
            userIdentificationOverride: "Procyon cancrivorus"
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanWithOverride(scanId: scanId, override: nil, confirmed: false)

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.userIdentificationOverride == nil, "updateScanWithOverride(override: nil) must clear the override column")
        #expect(fetched?.userConfirmedIdentification == false)
    }

    @Test func testUpdateScanWithOverrideSetsConfirmedTrue() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "confirmed-actor-test",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanWithOverride(scanId: scanId, override: nil, confirmed: true)

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.userConfirmedIdentification == true, "updateScanWithOverride must persist confirmed=true")
        #expect(fetched?.userIdentificationOverride == nil, "override must remain nil on a confirm-only action")
    }

    // MARK: - updateScanAsFlagged / updateScanAsUnflagged: V31 moderation review persistence

    // MARK: - fetchPendingScans: non-pending exclusion (V33)

    @Test func testFetchPendingScansExcludesNonPendingScans() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        // Only .pending scans should be fetched for upload dispatch.
        let pending    = OfflineQueuedScan(localImagePaths: ["pending.webp"],    scanState: .pending)
        let uploading  = OfflineQueuedScan(localImagePaths: ["uploading.webp"],  scanState: .uploading)
        let staged     = OfflineQueuedScan(localImagePaths: ["staged.webp"],     scanState: .staged)
        let inferencing = OfflineQueuedScan(localImagePaths: ["inferencing.webp"], scanState: .inferencing)
        let failed     = OfflineQueuedScan(localImagePaths: ["failed.webp"],     scanState: .failed)

        for scan in [pending, uploading, staged, inferencing, failed] {
            context.insert(scan)
        }
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let payloads = await actor.fetchPendingScans(limit: 10)

        #expect(payloads.count == 1, "fetchPendingScans must return only .pending scans")
        #expect(payloads.first?.id == pending.id, "Only the .pending scan must be returned")
    }

    // MARK: - updateScanAsFlagged / updateScanAsUnflagged: V31 moderation review persistence

    @Test func testUpdateScanAsFlaggedSetsFlag() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "flag-actor-test",
            scientificName: "Aedes aegypti",
            commonName: "Yellow Fever Mosquito",
            isFlagged: false
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanAsFlagged(scanId: scanId)

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.isFlagged == true, "updateScanAsFlagged must persist isFlagged=true")
    }

    @Test func testUpdateScanAsUnflaggedRemovesFlag() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "unflag-actor-test",
            scientificName: "Aedes aegypti",
            commonName: "Yellow Fever Mosquito",
            isFlagged: true
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanAsUnflagged(scanId: scanId)

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.isFlagged == false, "updateScanAsUnflagged must persist isFlagged=false")
    }

    // MARK: - tryClaimForInference: distributed lock (V33)

    @Test func testTryClaimForInferenceSucceedsOnStagedScan() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(localImagePaths: ["claim.webp"], scanState: .staged)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimed = await actor.tryClaimForInference(scanId: scanId)

        #expect(claimed == true, "tryClaimForInference must return true when scan is .staged")
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.inferencing.rawValue,
                "scan must be .inferencing after a successful claim")
    }

    @Test func testTryClaimForInferenceFailsWhenAlreadyInferencing() async throws {
        // Guards the double-pipeline race: if replayInferenceForUploadedScans and
        // processUploadCompletion both see the scan in .staged and race to claim it,
        // only one can win. The second call must return false.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(localImagePaths: ["already.webp"], scanState: .inferencing)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimed = await actor.tryClaimForInference(scanId: scanId)

        #expect(claimed == false, "tryClaimForInference must return false when scan is already .inferencing")
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.inferencing.rawValue,
                "state must remain .inferencing — not regressed by a failed claim")
    }

    @Test func testTryClaimForInferenceFailsWhenPending() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(localImagePaths: ["pending.webp"], scanState: .pending)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimed = await actor.tryClaimForInference(scanId: scanId)

        #expect(claimed == false, "tryClaimForInference must return false for non-.staged scans")
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.pending.rawValue,
                "state must remain .pending after a failed claim")
    }

    @Test func testTryClaimForInferenceDoesNotResurrectTombstone() async throws {
        // A .failed tombstone must never enter the inference pipeline.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(localImagePaths: ["dead.webp"], scanState: .failed)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimed = await actor.tryClaimForInference(scanId: scanId)

        #expect(claimed == false, "tryClaimForInference must not resurrect a tombstoned scan")
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.failed.rawValue,
                "tombstoned scan must remain .failed after a claim attempt")
    }

    @Test func testTryClaimForInferenceSecondCallReturnsFalse() async throws {
        // Simulate processUploadCompletion winning the claim, then replayInference trying again.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(localImagePaths: ["race.webp"], scanState: .staged)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let firstClaim  = await actor.tryClaimForInference(scanId: scanId)
        let secondClaim = await actor.tryClaimForInference(scanId: scanId)

        #expect(firstClaim == true,  "First claim on a .staged scan must succeed")
        #expect(secondClaim == false, "Second claim on the same scan must fail — pipeline already in progress")
    }

    // MARK: - transitionScanToStaged: tombstone resurrection guard (V33)

    @Test func testTransitionScanToStagedSucceedsFromInferencing() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(localImagePaths: ["retry.webp"], scanState: .inferencing)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.transitionScanToStaged(id: scanId)

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.staged.rawValue,
                "transitionScanToStaged must retreat .inferencing → .staged on transient failure")
    }

    @Test func testTransitionScanToStagedDoesNotResurrectTombstone() async throws {
        // The critical guard: a MainActor softDeleteQueuedScan wins the race and sets .failed.
        // The background actor must not overwrite it when its transitionScanToStaged runs later.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(localImagePaths: ["tombstoned.webp"], scanState: .failed)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.transitionScanToStaged(id: scanId)

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.failed.rawValue,
                "transitionScanToStaged must not overwrite a .failed tombstone — last-writer-wins guard")
    }

    @Test func testTransitionScanToStagedIsNoOpFromPending() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(localImagePaths: ["pending.webp"], scanState: .pending)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.transitionScanToStaged(id: scanId)

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.pending.rawValue,
                "transitionScanToStaged must be a no-op for non-.inferencing scans")
    }

    // MARK: - markScanAsStaged: source-state guard and R2 key persistence (V33)

    @Test func testMarkScanAsStagedPersistsR2Keys() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(localImagePaths: ["img.webp"], scanState: .uploading)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let r2Keys = ["staging/user123/\(scanId)_img.webp"]
        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.markScanAsStaged(scanId: scanId, r2Keys: r2Keys)

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.staged.rawValue,
                "markScanAsStaged must transition .uploading → .staged")
        #expect(fetched?.stagedR2Keys == r2Keys,
                "markScanAsStaged must persist R2 keys so inference can use them without auth reconstruction")
    }

    @Test func testMarkScanAsStagedDoesNotResurrectTombstone() async throws {
        // Prevents a late-arriving HTTP 200 for a partially-uploaded scan from
        // resurrecting it into the inference pipeline after it was tombstoned.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(localImagePaths: ["dead.webp"], scanState: .failed)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.markScanAsStaged(scanId: scanId, r2Keys: ["staging/user/\(scanId)_dead.webp"])

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.failed.rawValue,
                "markScanAsStaged must not resurrect .failed tombstones")
        #expect(fetched?.stagedR2Keys == nil,
                "R2 keys must not be written to a tombstoned scan")
    }

    @Test func testMarkScanAsStagedIsNoOpFromPending() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(localImagePaths: ["pending.webp"], scanState: .pending)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.markScanAsStaged(scanId: scanId, r2Keys: ["staging/user/\(scanId)_pending.webp"])

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.pending.rawValue,
                "markScanAsStaged must be a no-op for non-.uploading scans — prevents skipping the upload state")
        #expect(fetched?.stagedR2Keys == nil)
    }

    // MARK: - markScansAsUploading: source-state guard (V33)

    @Test func testMarkScansAsUploadingOnlyTransitionsPendingScans() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let pending    = OfflineQueuedScan(localImagePaths: ["p.webp"], scanState: .pending)
        let uploading  = OfflineQueuedScan(localImagePaths: ["u.webp"], scanState: .uploading)
        let staged     = OfflineQueuedScan(localImagePaths: ["s.webp"], scanState: .staged)
        let failed     = OfflineQueuedScan(localImagePaths: ["f.webp"], scanState: .failed)

        for scan in [pending, uploading, staged, failed] { context.insert(scan) }
        try context.save()

        // Pass all four IDs — only the .pending one must advance.
        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.markScansAsUploading(scanIds: [pending.id, uploading.id, staged.id, failed.id])

        let allDescriptor = FetchDescriptor<OfflineQueuedScan>()
        let all = try context.fetch(allDescriptor)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.scanStateRaw) })

        #expect(byId[pending.id]   == ScanQueueState.uploading.rawValue, ".pending must advance to .uploading")
        #expect(byId[uploading.id] == ScanQueueState.uploading.rawValue, "already-.uploading must stay .uploading")
        #expect(byId[staged.id]    == ScanQueueState.staged.rawValue,    ".staged must not be regressed")
        #expect(byId[failed.id]    == ScanQueueState.failed.rawValue,    ".failed tombstone must not be touched")
    }

    // MARK: - reconcileOrphanedUploadingScans: startup recovery (V33)

    @Test func testReconcileOrphanedUploadingScansResetsOrphansKeepsActive() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let orphan = OfflineQueuedScan(localImagePaths: ["orphan.webp"], scanState: .uploading)
        let active = OfflineQueuedScan(localImagePaths: ["active.webp"], scanState: .uploading)
        let pending = OfflineQueuedScan(localImagePaths: ["pending.webp"], scanState: .pending)

        for scan in [orphan, active, pending] { context.insert(scan) }
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        // Only `active` has a live URLSession task.
        await actor.reconcileOrphanedUploadingScans(activeScanIds: Set([active.id]))

        let allDescriptor = FetchDescriptor<OfflineQueuedScan>()
        let all = try context.fetch(allDescriptor)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.scanStateRaw) })

        #expect(byId[orphan.id]  == ScanQueueState.pending.rawValue,   "orphaned .uploading scan must reset to .pending")
        #expect(byId[active.id]  == ScanQueueState.uploading.rawValue, ".uploading scan with active task must stay .uploading")
        #expect(byId[pending.id] == ScanQueueState.pending.rawValue,   ".pending scan must be unaffected")
    }

    @Test func testReconcileOrphanedUploadingScansWithEmptyActiveSet() async throws {
        // Process died mid-dispatch — no URLSession tasks survived. All .uploading → .pending.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan1 = OfflineQueuedScan(localImagePaths: ["a.webp"], scanState: .uploading)
        let scan2 = OfflineQueuedScan(localImagePaths: ["b.webp"], scanState: .uploading)

        context.insert(scan1)
        context.insert(scan2)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.reconcileOrphanedUploadingScans(activeScanIds: Set())

        let allDescriptor = FetchDescriptor<OfflineQueuedScan>()
        let all = try context.fetch(allDescriptor)
        for scan in all {
            #expect(scan.scanStateRaw == ScanQueueState.pending.rawValue,
                    "all .uploading scans must be reset when no active tasks exist")
        }
    }

    // MARK: - resetOrphanedInferencingScans: startup recovery (V33)

    @Test func testResetOrphanedInferencingScansResetsAllToStaged() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let inf1   = OfflineQueuedScan(localImagePaths: ["i1.webp"], scanState: .inferencing)
        let inf2   = OfflineQueuedScan(localImagePaths: ["i2.webp"], scanState: .inferencing)
        let staged = OfflineQueuedScan(localImagePaths: ["s.webp"],  scanState: .staged)
        let failed = OfflineQueuedScan(localImagePaths: ["f.webp"],  scanState: .failed)

        for scan in [inf1, inf2, staged, failed] { context.insert(scan) }
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.reconcileOrphanedInferencingScans(activeInferenceScanIds: [])

        let allDescriptor = FetchDescriptor<OfflineQueuedScan>()
        let all = try context.fetch(allDescriptor)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.scanStateRaw) })

        #expect(byId[inf1.id]   == ScanQueueState.staged.rawValue,     ".inferencing must reset to .staged")
        #expect(byId[inf2.id]   == ScanQueueState.staged.rawValue,     "all .inferencing scans must reset")
        #expect(byId[staged.id] == ScanQueueState.staged.rawValue,     ".staged must be unaffected")
        #expect(byId[failed.id] == ScanQueueState.failed.rawValue,     ".failed tombstone must be unaffected")
    }

    // MARK: - Full state machine lifecycle (V33)

    @Test func testFullStateMachineLifecycle() async throws {
        // Walks a single scan through every forward state transition, then validates
        // the transient-retry path, then re-claims and verifies the second claim is blocked.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(localImagePaths: ["lifecycle.webp"], scanState: .pending)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)

        func fetchState() throws -> Int {
            var d = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            d.fetchLimit = 1
            return (try context.fetch(d).first?.scanStateRaw) ?? -1
        }

        // .pending → .uploading
        await actor.markScansAsUploading(scanIds: [scanId])
        #expect(try fetchState() == ScanQueueState.uploading.rawValue, ".pending must advance to .uploading")

        // .uploading → .staged (with R2 keys persisted)
        let r2Keys = ["staging/user/\(scanId)_lifecycle.webp"]
        await actor.markScanAsStaged(scanId: scanId, r2Keys: r2Keys)
        #expect(try fetchState() == ScanQueueState.staged.rawValue, ".uploading must advance to .staged")
        var d = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        d.fetchLimit = 1
        #expect(try context.fetch(d).first?.stagedR2Keys == r2Keys, "R2 keys must be persisted at staging")

        // .staged → .inferencing (claim)
        let firstClaim = await actor.tryClaimForInference(scanId: scanId)
        #expect(firstClaim == true, ".staged scan must be claimable for inference")
        #expect(try fetchState() == ScanQueueState.inferencing.rawValue, "claimed scan must be .inferencing")

        // Concurrent second claim is blocked
        let secondClaim = await actor.tryClaimForInference(scanId: scanId)
        #expect(secondClaim == false, "second claim on .inferencing scan must fail")

        // Transient failure → retreat to .staged
        await actor.transitionScanToStaged(id: scanId)
        #expect(try fetchState() == ScanQueueState.staged.rawValue, "transient failure must retreat to .staged")

        // Re-claim after retry
        let retryClaim = await actor.tryClaimForInference(scanId: scanId)
        #expect(retryClaim == true, "re-claim on .staged scan must succeed after retry")
        #expect(try fetchState() == ScanQueueState.inferencing.rawValue, "retried scan must be .inferencing again")
    }
}
