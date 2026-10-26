import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Deferred native app admission", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct SharedMediaNativeAppAdmissionTests {
    @Test func bootstrapAndSignedOutRefusalStayInertUntilStableAdmission() async throws {
        let h = try Fixture()
        #expect(h.di.nativeMediaLifetime == nil && h.di.nativeMediaOwner == nil)
        h.ready = false
        await #expect(throws: (any Error).self) { _ = try await h.open() }
        #expect(h.installs == 0 && !FileManager.default.fileExists(atPath: h.parent.path))
        h.ready = true
        let owner = try await h.open()
        #expect(owner === h.di.nativeMediaOwner && owner.isReadyForAppDispatch)
        #expect(h.installs == 1)
        await #expect(throws: SharedMediaStorageFailure.closed) { _ = try await owner.appInitializationSnapshot() }
        #expect(throws: (any Error).self) { _ = try h.admission.acquireFence(container: h.container) }
        try #require(await h.shutdown())
        #expect(h.di.nativeMediaOwner == nil && h.di.nativeMediaLifetime != nil)
        _ = try h.admission.acquireFence(container: h.container)
        await #expect(throws: (any Error).self) { _ = try await h.open() }
        #expect(h.installs == 1 && h.begins == h.finishes)
    }

    @Test func failedHookInstallFinishesLeaseAndLeavesStartupRetryable() async throws {
        let h = try Fixture()
        h.installFails = true
        await #expect(throws: (any Error).self) { _ = try await h.open() }
        #expect(h.di.nativeMediaLifetime == nil && h.begins == h.finishes)
        #expect(!FileManager.default.fileExists(atPath: h.parent.path))
        h.installFails = false
        _ = try await h.open()
        try #require(await h.shutdown())
        #expect(h.begins == h.finishes)
    }

    @Test func concurrentAdmissionAndCancelledWaiterKeepOneOwner() async throws {
        let h = try Fixture(), gate = Gate()
        let first = Task { try await h.open { try $0.configureAppOpeningForTesting(pause: { await gate.pause() }) } }
        await gate.arrived()
        let retained = try #require(h.di.nativeMediaOwner)
        #expect(!retained.isReadyForAppDispatch && h.installs == 1)
        first.cancel()
        let second = Task { try await h.open() }
        gate.release()
        await #expect(throws: CancellationError.self) { _ = try await first.value }
        let result = try await second.value
        #expect(result === retained && h.installs == 1 && result.isReadyForAppDispatch)
        try #require(await h.shutdown())
        #expect(h.begins == h.finishes)
    }

    @Test(arguments: [false, true])
    func shutdownOrStaleAccountDuringPromotionNeverPublishesReady(stale: Bool) async throws {
        let h = try Fixture(), gate = Gate()
        let opening = Task { try await h.open { try $0.configureAppOpeningForTesting(pause: { await gate.pause() }) } }
        await gate.arrived()
        let retained = try #require(h.di.nativeMediaOwner)
        #expect(!retained.isReadyForAppDispatch)
        if stale { h.current = false }
        let shutdown: Task<Bool, Never>? = stale ? nil : Task { await h.shutdown() }
        await Task.yield()
        #expect(h.di.nativeMediaOwner === retained)
        #expect(throws: (any Error).self) { _ = try h.admission.acquireFence(container: h.container) }
        gate.release()
        await #expect(throws: (any Error).self) { _ = try await opening.value }
        if let shutdown { try #require(await shutdown.value) }
        #expect(h.di.nativeMediaOwner == nil && !retained.isReadyForAppDispatch)
        #expect(h.begins == h.finishes)
        _ = try h.admission.acquireFence(container: h.container)
    }

    @Test func anotherRuntimeCannotCoalesceSameAccountIdentity() async throws {
        let h = try Fixture(), gate = Gate(), other = AuthRuntimeState()
        let opening = Task { try await h.open { try $0.configureAppOpeningForTesting(pause: { await gate.pause() }) } }
        await gate.arrived()
        let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: other)
        await #expect(throws: (any Error).self) {
            _ = try await h.di.nativeMediaOwnerForTesting(account: account, support: h.support, install: { _ in Issue.record("Duplicate install") })
        }
        await other.awaitAccountWorkDrain()
        gate.release()
        _ = try await opening.value
        try #require(await h.shutdown())
    }

    @Test func failedBootstrapNeverPublishesAndRetainsOriginalProfileForLaterProcess() async throws {
        let h = try Fixture()
        await #expect(throws: (any Error).self) {
            _ = try await h.open { try $0.configureAppOpeningForTesting(fault: { if $0 == .afterSave { throw SharedMediaStorageFailure.unavailable } }) }
        }
        #expect(h.di.nativeMediaOwner == nil && h.di.nativeMediaLifetime != nil)
        let rows = try ModelContext(h.container).fetch(FetchDescriptor<SharedMediaInventoryRecord>())
        #expect(rows.count == 1)
        let next = AppDIContainer.preview
        try next.configureNativeMediaForTesting(container: h.container, admission: h.admission)
        let owner = try await next.nativeMediaOwnerForTesting(account: h.account(), support: h.support, install: { _ in })
        #expect(owner.isReadyForAppDispatch)
        #expect(try ModelContext(h.container).fetch(FetchDescriptor<SharedMediaInventoryRecord>()).map(\.id) == rows.map(\.id))
        try #require(await next.nativeMediaLifetime?.shutdown() == true)
        #expect(h.begins == h.finishes)
    }

    @Test func failedSettlementRetainsOwnerAndFenceUntilExplicitSuccessfulShutdown() async throws {
        let h = try Fixture(), owner = try await h.open()
        let request = try await owner.prepareAppOriginal(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, kind: .picker)
        try owner.setAcquisitionFault { if $0 == .beforeCompletionSave || $0 == .beforeHeldSave { throw SharedMediaStorageFailure.unavailable } }
        let bytes = PhotoPreparationTestHarness.image()
        await #expect(throws: (any Error).self) { _ = try await owner.acquireAppOriginal(request) { bytes } }
        #expect(!(await h.shutdown()))
        #expect(h.di.nativeMediaOwner === owner && !owner.isReadyForAppDispatch)
        #expect(throws: (any Error).self) { _ = try h.admission.acquireFence(container: h.container) }
        await #expect(throws: (any Error).self) { _ = try await h.open() }
        var boundaries: [String] = []
        try owner.setAcquisitionFault { if boundaries.count < 32 { boundaries.append(String(describing: $0)) } }
        let previousTraceCount = owner.settlementTraceForTesting.count
        let retried = await h.shutdown()
        let failure = owner.shutdownFailureForTesting
        let label = (failure as? SharedMediaStorageFailure).map { String(describing: $0) }
            ?? (failure as? PhotoPreparationFailure).map { String(describing: $0) } ?? "unclassified"
        try #require(retried, "Settlement retry: \(label); boundaries: \(boundaries); phases: \(Array(owner.settlementTraceForTesting.dropFirst(previousTraceCount)))")
        #expect(h.di.nativeMediaOwner == nil && h.begins == h.finishes)
        _ = try h.admission.acquireFence(container: h.container)
    }

    @Test func promotedOwnerReceivesExactMediaAndTextThenReopensWithoutInitialization() async throws {
        let started = ContinuousClock.now
        func phase(_ value: String) { print("NATIVE_ADMISSION_PHASE \(value) \(started.duration(to: .now))") }
        phase("opening")
        let h = try Fixture(), owner = try await h.open()
        phase("opened")
        let package = UUID(), draft = UUID(), bytes = PhotoPreparationTestHarness.image()
        let request = try await owner.prepareAppOriginal(packageID: package, draftGeneration: draft, ordinal: 0, kind: .picker)
        let acquired = try await owner.acquireAppOriginal(request) { bytes }
        phase("original-acquired")
        let original = PhotoOriginalReference(ownerID: h.ownerID, packageID: package, referenceID: request.referenceID,
            assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: draft, referenceRevision: acquired.referenceRevision)
        let pair = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: .init(format: .stillImage,
            isPro: false, cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0))
        phase("pair-prepared")
        let text = "  Immutable supporting text\nwith spacing.  "
        let metadata = try await owner.prepareAppMetadata(packageID: package, draftGeneration: draft, contexts: [.init(freeText: text)])
        _ = try await owner.saveAppMetadata(metadata)
        phase("metadata-saved")
        let prepared = try await owner.stageAppReceiving(packageID: package, draftGeneration: draft, pairIDs: [pair.intent().pairID])
        phase("receiving-staged")
        let received = try await owner.receiveAppPrepared(prepared)
        phase("received")
        let slot = try #require(try await owner.discoverAppReceivingSlot(packageID: package))
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let supporting: SharedMediaNativeFrozenSupporting = try SharedMediaAcquisitionEncoding.decode(frozen.supportingBytes, maximum: Int(PhotoPreparationPolicy.metadata))
        #expect(supporting.contexts.map(\.freeText) == [text])
        #expect(try ModelContext(h.container).fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.queueNeedsAttention) == [true])
        phase("slot-verified")
        try #require(await h.shutdown())
        phase("shutdown")
        let next = AppDIContainer.preview
        try next.configureNativeMediaForTesting(container: h.container, admission: h.admission)
        let trace = SharedMediaNativeDebugHooks.InspectionTrace { value in
            print("NATIVE_ADMISSION_AUDIT \(value.phase.rawValue) completed=\(value.completed) elapsed=\(value.elapsed) checkpoints=\(value.checkpointCount) checkpointTime=\(value.checkpointTime) saturated=\(value.saturated)")
        }
        let reopened = try await next.nativeMediaOwnerForTesting(account: h.account(), support: h.support, install: { _ in },
            configure: { try $0.configureAppOpeningForTesting(trace: trace) })
        trace.finish()
        phase("reopened")
        #expect(try await reopened.discoverAppReceivingSlot(packageID: package) == slot)
        phase("reopened-slot-verified")
        #expect(try await reopened.receiveAppPrepared(prepared) == received)
        phase("replayed")
        try #require(await next.nativeMediaLifetime?.shutdown() == true)
        #expect(h.begins == h.finishes)
    }

    @MainActor private final class Fixture {
        let di = AppDIContainer.preview
        let support: URL, container: ModelContainer, admission: NativeReleaseStartupAdmission, ownerID: UUID
        let runtime = AuthRuntimeState()
        var ready = true, current = true, installFails = false
        var begins = 0, finishes = 0, installs = 0
        var parent: URL { support.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentName) }
        init() throws {
            let store = try SharedMediaNativeAppBootstrapTests.Store(startupEligible: true)
            support = store.parent.deletingLastPathComponent(); ownerID = store.ownerID
            let startup = try store.startup(); container = startup.0; admission = startup.1
            try di.configureNativeMediaForTesting(container: container, admission: admission)
        }
        func account() -> PhotoOriginalPreparationOwner.AccountAccess {
            let session = AuthTransitionSession(userID: ownerID, isAnonymous: false)
            return .init(ownerID: ownerID, begin: {
                guard self.ready else { throw PhotoPreparationFailure.accountChanged }
                self.begins += 1; return self.runtime.beginAccountWork(session: session)
            }, isCurrent: { self.current && self.runtime.accountWorkLeaseIsCurrent($0, publishedSession: session, sdkSession: session) },
            finish: { #expect(self.runtime.finishAccountWork($0)); self.finishes += 1 })
        }
        func open(configure: (SharedMediaNativeOriginalOwner) throws -> Void = { _ in }) async throws -> SharedMediaNativeOriginalOwner {
            try await di.nativeMediaOwnerForTesting(account: account(), support: support, install: { _ in
                if self.installFails { throw SharedMediaStorageFailure.closed }
                self.installs += 1
            }, configure: configure)
        }
        func shutdown() async -> Bool { await di.nativeMediaLifetime?.shutdown() ?? true }
    }

    @MainActor private final class Gate {
        private var entered = false, released = false
        private var waiter: CheckedContinuation<Void, Never>?, arrival: CheckedContinuation<Void, Never>?
        func pause() async {
            guard !released else { return }
            entered = true; arrival?.resume(); arrival = nil
            await withCheckedContinuation { waiter = $0 }
        }
        func arrived() async { if !entered { await withCheckedContinuation { arrival = $0 } } }
        func release() { released = true; waiter?.resume(); waiter = nil }
    }
}
