import Darwin
import Foundation
@testable import Merian
import os
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct CaptureVideoReanalysisHostTests {
    func idle(_ host: CaptureVideoReanalysisHost) async { while host.isBusy { await Task.yield() } }

    @Test func stableAuthRenewsExactClosedLifetimeWithoutReopeningOldOwners() async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let di = AppDIContainer.preview, manager = di.supabaseManager
        di.offlineQueueManager.modelContext = ModelContext(seed.container)
        try di.configureNativeMediaForTesting(container: seed.container, admission: seed.startup)
        let prepared = di.preparedReanalysisHostOwner, cleanup = di.offlineQueueManager.reanalysisErasureOwner
        let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: seed.source.ownerID, runtime: AuthRuntimeState())
        var quiet = false
        _ = try di.preparedInputBorrowForTesting(container: seed.container, account: account, consumer: prepared,
            install: manager.installNativeMediaAccountTransitionDrain, close: { quiet })
        let original = try #require(di.nativeMediaLifetime)
        #expect(await original.shutdown() == false)
        #expect(await di.renewNativeMediaLifetime(for: manager, isCurrent: { true }) == false)
        #expect(di.preparedReanalysisHostOwner === prepared && di.offlineQueueManager.reanalysisErasureOwner === cleanup)
        quiet = true
        #expect(await original.shutdown())
        #expect(throws: SharedMediaStorageFailure.closed) {
            try manager.retireNativeMediaAccountTransitionDrain(SharedMediaNativeOriginalDrain())
        }
        for permittedChecks in 1...2 {
            var validations = 0
            #expect(await di.renewNativeMediaLifetime(for: manager, isCurrent: { validations += 1; return validations <= permittedChecks }) == false)
            #expect(di.nativeMediaLifetime === original && di.preparedReanalysisHostOwner === prepared)
            #expect(di.offlineQueueManager.reanalysisErasureOwner === cleanup)
        }
        #expect(await di.renewNativeMediaLifetime(for: manager, isCurrent: { true }))
        #expect(di.nativeMediaLifetime == nil && di.preparedReanalysisHostOwner !== prepared)
        #expect(di.offlineQueueManager.reanalysisErasureOwner !== cleanup)
        #expect(throws: (any Error).self) { try prepared.armAccountLifetime(manager: manager) }
        #expect(throws: (any Error).self) {
            _ = try original.borrowLocalFence(for: prepared, role: .preparedInputs, container: seed.container, close: { true })
        }
        let replacement = di.preparedReanalysisHostOwner
        try replacement.armAccountLifetime(manager: manager)
        let borrow = try di.preparedInputBorrowForTesting(container: seed.container, account: account, consumer: replacement,
            install: manager.installNativeMediaAccountTransitionDrain, close: { await replacement.retireAccountLifetime(manager: manager) })
        _ = try borrow.fence(container: seed.container)
        let renewed = try #require(di.nativeMediaLifetime)
        #expect(renewed !== original && !renewed.isClosed)
        #expect(await renewed.shutdown())
        try manager.retireNativeMediaAccountTransitionDrain(renewed)
    }

    @Test func finalTapRetainsIdentityTextAndPreparedMediaAcrossReopen() async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let media = try await VideoAudioFixture(channels: 1); defer { media.remove() }
        let original = seed.documents.appendingPathComponent("chosen.mp4")
        try FileManager.default.removeItem(at: original)
        try FileManager.default.copyItem(at: media.videoURL, to: original)
        var starts: [UUID] = [], openings = 0
        let account = ObservationReanalysisProducerTests().account()
        let access = CaptureVideoReanalysisAccess.prepared(account: account, ownership: .init(),
            configuration: .init(resume: .init(start: { ready, _, _, _, _ in
                starts.append(ready.proof.preparation.identity.analysisID)
                #expect(ready.proof.preparation.request.manifest.descriptions == ["  Exact e\u{301} 🐾\n"])
                guard case let .reservation(saved) = ready.route else { Issue.record("Expected staged reservation"); return .unavailable }
                #expect(saved.work.phase == .staged && saved.work.attemptID == nil)
                return .unavailable
            }), files: seed.files, temporaryDirectory: { media.outputDirectory }, prepareLifetime: { openings += 1 }, startup: { _ in seed.startup }),
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in true },
            containerIsCurrent: { $0 === seed.container }, documents: { seed.documents })
        let owner = CaptureAudioReanalysisHostOwner()
        let target = HistoricalReanalysisTarget(observationID: seed.source.observationID,
            analysisID: seed.source.analysisID, ownerID: seed.source.ownerID)
        let host = try owner.openVideo(target: target, container: seed.container) {
            try CaptureVideoReanalysisHost(opened: access.open(target, seed.container, UUID()))
        }
        #expect(openings == 1 && starts.isEmpty && host.analysisID == nil && host.selected == nil)
        #expect(host.present())
        host.select(try #require(host.choices.first), scope: host.presentedScope)
        host.submit(descriptions: ["  Exact e\u{301} 🐾\n"], scope: host.presentedScope)
        let child = try #require(host.analysisID)
        #expect(starts.isEmpty)
        await idle(host)
        #expect(starts == [child])
        #expect(try FileManager.default.contentsOfDirectory(atPath: seed.temporary.path).isEmpty)
        try FileManager.default.removeItem(at: original)
        let context = ModelContext(seed.container)
        try seed.parent(context).capturedMediaJSON = nil
        try context.save()
        host.close()
        let reopened = try owner.openVideo(target: target, container: seed.container) {
            Issue.record("Reopening created another candidate"); throw MerianError.invalidResponse
        }
        #expect(reopened === host && host.present() && host.analysisID == child)
        host.retry(scope: host.presentedScope); await idle(host)
        #expect(starts == [child, child] && openings == 1)
        host.submit(descriptions: ["Changed"], scope: host.presentedScope)
        await idle(host)
        #expect(starts == [child, child] && host.analysisID == child)
        #expect(await owner.invalidateAndAwait())
    }

    @Test func failedPreparationKeepsUnresolvedSnapshotInClosedOwner() async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let access = CaptureVideoReanalysisAccess.prepared(account: ObservationReanalysisProducerTests().account(), ownership: .init(),
            configuration: .init(resume: .init(start: { _, _, _, _, _ in Issue.record("Invalid video dispatched"); return .started }),
                files: seed.files, temporaryDirectory: { seed.temporary }, prepareLifetime: {}, startup: { _ in seed.startup }),
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in true },
            containerIsCurrent: { _ in true }, documents: { seed.documents })
        let di = AppDIContainer.preview
        let owner = di.preparedReanalysisHostOwner, manager = di.supabaseManager
        try di.configureNativeMediaForTesting(container: seed.container, admission: seed.startup)
        try owner.armAccountLifetime(manager: manager)
        let target = HistoricalReanalysisTarget(observationID: seed.source.observationID,
            analysisID: seed.source.analysisID, ownerID: seed.source.ownerID)
        let host = try owner.openVideo(target: target, container: seed.container) {
            try CaptureVideoReanalysisHost(opened: access.open(target, seed.container, UUID()))
        }
        #expect(host.present()); host.select(try #require(host.choices.first), scope: host.presentedScope)
        host.submit(descriptions: [], scope: host.presentedScope); await idle(host)
        let child = try #require(host.analysisID)
        let receipt = try #require(try ObservationReanalysisInputPersistence.read(child: child, container: seed.container))
        let copied = seed.documents.appendingPathComponent("ReanalysisInputs/\(receipt.slot)/input.mp4")
        try Data([9]).write(to: copied, options: .atomic)
        #expect(await owner.drainAccountLifetime(manager: manager) == false)
        #expect(await owner.drainAccountLifetime(manager: manager) == false)
        #expect(await owner.drainAccountLifetimeDisposition(manager: manager) == .retainedStorage)
        #expect(host.isRuntimeQuiescent)
        let fence = try seed.startup.acquireFence(container: seed.container)
        try seed.startup.require(container: seed.container, fence: fence)
        #expect(!host.isCurrent && !host.isPresented && !host.present())
        #expect(try Data(contentsOf: copied) == Data([9]))
        #expect(throws: (any Error).self) {
            try owner.openVideo(target: target, container: seed.container) {
                Issue.record("Closed owner replaced retained input"); throw MerianError.invalidResponse
            }
        }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        var journal = LibrarySignOutJournal(sourceUserID: seed.source.ownerID)
        journal.phase = .sourceCleared
        var data: Data? = try JSONEncoder().encode(journal)
        let store = LibrarySignOutJournalStore(dependencies: .init(read: { data }, write: { data = $0; return true }, remove: { data = nil }))
        let scope = try #require(store.recoveryScope(expected: journal, validateContext: { true }))
        #expect(await di.awaitPreparedReanalysisHostDrain(for: manager) == false)
        #expect(await di.awaitPreparedReanalysisHostDrain(for: manager, recoveryAuthority: .librarySignOut(scope)))
        #expect(try Data(contentsOf: copied) == Data([9]))
        data = nil
        #expect(await di.awaitPreparedReanalysisHostDrain(for: manager, recoveryAuthority: .librarySignOut(scope)) == false)
        #expect(await owner.drainAccountLifetimeDisposition(manager: manager) == .retainedStorage)
        let other = try ObservationReanalysisLocalVideoInputTests().seed(); defer { other.remove() }
        #expect(!owner.acknowledgeLibraryPurge(container: other.container, manager: manager))
        #expect(!owner.acknowledgeLibraryPurge(container: seed.container, manager: NSObject()))
        di.offlineQueueManager.modelContext = ModelContext(seed.container)
        #expect(await di.renewNativeMediaLifetime(for: manager, isCurrent: { true }) == false)
        #expect(di.preparedReanalysisHostOwner === owner)
        let libraryContext = di.accountDeletionLibraryContext(for: manager)
        var deletionState: AccountDeletionLocalRecoveryState?
        let proofStore = AccountDeletionSecureStoreStub().makeCapabilityStore()
        let intake = AccountDeletionLocalCleanupStore.RecoveryScope(expectedState: nil, expectedCapability: nil,
            capabilityStore: proofStore, readState: { deletionState }, validateSession: { true }, validateLibrary: libraryContext)
        #expect(await di.awaitPreparedReanalysisHostDrain(for: manager, recoveryAuthority: .accountDeletion(intake)))
        #expect(!intake.permitsLibraryPurge(in: seed.container))
        #expect(!di.acknowledgeDeletionPurge(for: manager, scope: intake))
        deletionState = .cleanupPending
        #expect(!intake.isCurrent)
        let cleanup = AccountDeletionLocalCleanupStore.RecoveryScope(expectedState: .cleanupPending, expectedCapability: nil,
            capabilityStore: proofStore, readState: { deletionState }, validateSession: { true }, validateLibrary: libraryContext)
        #expect(cleanup.permitsLibraryPurge(in: seed.container))
        #expect(!cleanup.permitsLibraryPurge(in: other.container))
        di.offlineQueueManager.modelContext = ModelContext(other.container)
        #expect(await di.renewNativeMediaLifetime(for: manager, isCurrent: { true }) == false)
        #expect(di.preparedReanalysisHostOwner === owner)
        #expect(!cleanup.isCurrent)
        #expect(await di.awaitPreparedReanalysisHostDrain(for: manager, recoveryAuthority: .accountDeletion(cleanup)) == false)
        #expect(!di.acknowledgeDeletionPurge(for: manager, scope: cleanup))
        di.offlineQueueManager.modelContext = ModelContext(seed.container)
        #expect(await di.awaitPreparedReanalysisHostDrain(for: manager, recoveryAuthority: .accountDeletion(cleanup)))
        let suite = "merian.tests.host-purge." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        var resets = 0
        #expect(await ScanLibraryPurgeService.purge(modelContext: ModelContext(seed.container), userDefaults: defaults,
            resetRuntimeState: { resets += 1 }, validateAuthorization: { cleanup.permitsLibraryPurge(in: seed.container) }, eraseReanalysis: {
                try await ObservationReanalysisFileStore(documents: seed.documents).purgeNamespace()
            }))
        #expect(resets == 1 && !FileManager.default.fileExists(atPath: copied.path))
        #expect(di.acknowledgeDeletionPurge(for: manager, scope: cleanup))
        #expect(await owner.drainAccountLifetime(manager: manager))
        #expect(await di.renewNativeMediaLifetime(for: manager, isCurrent: { true }))
        #expect(di.preparedReanalysisHostOwner !== owner)
        #expect(throws: (any Error).self) { try owner.armAccountLifetime(manager: manager) }
        #expect(!host.present())
    }
    @Test func authDrainWaitsForActualCopyExitAndLeaseRelease() async throws {
        let current = MainActorTestValue(true)
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let entered = ImageFocusEngineTests.Signal(), draining = ImageFocusEngineTests.Signal()
        let release = DispatchSemaphore(value: 0), calls = OSAllocatedUnfairLock(initialState: 0)
        defer { release.signal() }
        var io = FileIOActor.CopyIO.live
        io.write = { fd, bytes in
            let first = calls.withLock { $0 += 1; return $0 == 1 }
            if first {
                Task.detached { await entered.open() }
                guard release.wait(timeout: .now() + 10) == .success else { errno = EIO; return -1 }
            }
            return Darwin.write(fd, bytes.baseAddress, bytes.count)
        }
        let files = FileIOActor(documents: seed.documents, temporaryDirectory: seed.temporary, copyIO: io)
        var leases = 0, finished = false, finalDrain = false
        let base = ObservationReanalysisProducerTests().account()
        var account = base
        account.begin = { owner in let lease = try base.begin(owner); leases += 1; return lease }
        account.isCurrent = { _ in current.value }
        account.finish = { _ in leases -= 1 }
        let owner = CaptureAudioReanalysisHostOwner(), manager = NSObject()
        try owner.armAccountLifetime(manager: manager)
        let access = CaptureVideoReanalysisAccess.prepared(account: account, ownership: .init(),
            configuration: .init(resume: .init(start: { _, _, _, _, _ in Issue.record("Cancelled copy dispatched"); return .started }),
                files: files, temporaryDirectory: { seed.temporary }, prepareLifetime: {}, startup: { _ in seed.startup }),
            currentOwner: { current.value ? seed.source.ownerID : nil }, generation: { 1 }, sessionIsCurrent: { _ in current.value },
            containerIsCurrent: { _ in true }, documents: { seed.documents })
        let target = HistoricalReanalysisTarget(observationID: seed.source.observationID,
            analysisID: seed.source.analysisID, ownerID: seed.source.ownerID)
        let host = try owner.openVideo(target: target, container: seed.container) {
            try CaptureVideoReanalysisHost(opened: access.open(target, seed.container, UUID()))
        }
        #expect(leases == 0)
        try #require(host.present())
        host.select(try #require(host.choices.first), scope: host.presentedScope)
        host.submit(descriptions: [], scope: host.presentedScope)
        await entered.wait()
        #expect(leases == 1 && host.isBusy)
        current.value = false
        let closing = Task { @MainActor in
            let result = await SupabaseManager.drainPhotoPreparationBeforeAccountWork(preparation: {
                    await draining.open()
                    return await owner.drainAccountLifetime(manager: manager)
                }, drain: { #expect(leases == 0 && !host.isBusy); finalDrain = true })
            finished = true
            return result
        }
        await draining.wait()
        #expect(!finished && !finalDrain && leases == 1)
        var secondStarted = false, secondFinished = false
        let overlapping = Task { @MainActor in
            secondStarted = true
            let result = await owner.drainAccountLifetime(manager: manager)
            secondFinished = true
            return result
        }
        while !secondStarted { await Task.yield() }
        #expect(!finished && !secondFinished && leases == 1 && host.isBusy)
        release.signal()
        #expect(await closing.value)
        #expect(await overlapping.value)
        #expect(finalDrain && finished && leases == 0 && !host.isBusy && !host.isPresented)
        #expect(try FileManager.default.contentsOfDirectory(atPath: seed.temporary.path).isEmpty)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test(arguments: [false, true])
    func authClosureDuringCohortHandoffOrAfterDurablePreparation(afterDurable: Bool) async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let media = try await VideoAudioFixture(channels: 1); defer { media.remove() }
        let original = seed.documents.appendingPathComponent("chosen.mp4")
        try FileManager.default.removeItem(at: original)
        try FileManager.default.copyItem(at: media.videoURL, to: original)
        let owner = CaptureAudioReanalysisHostOwner()
        var current = true, leases = 0, begins = 0, triggered = false, finalDrain = false
        let base = ObservationReanalysisProducerTests().account()
        func stop() {
            guard !triggered else { return }
            triggered = true; current = false; owner.invalidate()
        }
        var account = base
        account.begin = { user in
            let lease = try base.begin(user); leases += 1; begins += 1
            // Open, copy, input preparation, then the completed cohort's producer lease.
            if !afterDurable && begins == 4 { stop() }
            return lease
        }
        account.isCurrent = { _ in current }
        account.finish = { _ in
            leases -= 1
            // Producer exits only after its transaction and complete-cohort persistence.
            if afterDurable && begins == 4 && leases == 1 { stop() }
        }
        let access = CaptureVideoReanalysisAccess.prepared(account: account, ownership: .init(),
            configuration: .init(resume: .init(start: { _, _, _, _, _ in Issue.record("Closing account dispatched"); return .started }),
                files: seed.files, temporaryDirectory: { media.outputDirectory }, prepareLifetime: {}, startup: { _ in seed.startup }),
            currentOwner: { current ? seed.source.ownerID : nil }, generation: { 1 }, sessionIsCurrent: { _ in current },
            containerIsCurrent: { _ in true }, documents: { seed.documents })
        let target = HistoricalReanalysisTarget(observationID: seed.source.observationID,
            analysisID: seed.source.analysisID, ownerID: seed.source.ownerID)
        let host = try owner.openVideo(target: target, container: seed.container) {
            try CaptureVideoReanalysisHost(opened: access.open(target, seed.container, UUID()))
        }
        #expect(host.present())
        host.select(try #require(host.choices.first), scope: host.presentedScope)
        host.submit(descriptions: ["Kept"], scope: host.presentedScope)
        let child = try #require(host.analysisID)
        // A preparation failure still ends the waiter; never leave a test waiting for an unreachable signal.
        await idle(host)
        #expect(triggered && begins == 4)
        let drained = await SupabaseManager.drainPhotoPreparationBeforeAccountWork(preparation: { await owner.invalidateAndAwait() },
            drain: { #expect(leases == 0 && !host.isBusy); finalDrain = true })
        #expect(drained)
        #expect(finalDrain && !host.isCurrent)
        #expect(try FileManager.default.contentsOfDirectory(atPath: seed.temporary.path).isEmpty)
        let context = ModelContext(seed.container)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == (afterDurable ? 1 : 0))
        if afterDurable {
            let identity = OfflineQueueWork.Reanalysis(observationID: seed.source.observationID, sourceAnalysisID: seed.source.analysisID,
                analysisID: child, ownerID: seed.source.ownerID)
            let pair = try #require(try ObservationReanalysisPersistence.pair(identity, context: context))
            let raw = try #require(pair.1.metadataJSON)
            let saved = try ObservationVideoPreparation.decode(Data(raw.utf8))
            #expect(saved.phase == .ready && saved.preparation.identity.analysisID == child)
        }
    }

    @Test func lifetimeArmingIsInertBoundOnceAndTerminalAfterDrain() async throws {
        let owner = CaptureAudioReanalysisHostOwner(), manager = NSObject(), foreign = NSObject()
        #expect(await owner.drainAccountLifetime(manager: manager))
        try owner.armAccountLifetime(manager: manager)
        try owner.armAccountLifetime(manager: manager)
        #expect(await owner.drainAccountLifetime(manager: foreign) == false)
        #expect(await owner.drainAccountLifetimeDisposition(manager: foreign) == .blocked)
        #expect(throws: (any Error).self) { try owner.armAccountLifetime(manager: foreign) }
        // A rejected foreign drain does not close the bound lifetime.
        try owner.armAccountLifetime(manager: manager)
        #expect(await owner.drainAccountLifetime(manager: manager))
        #expect(await owner.drainAccountLifetime(manager: manager))
        #expect(throws: (any Error).self) { try owner.armAccountLifetime(manager: manager) }
    }

}
