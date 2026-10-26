import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native account lifetime", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct SharedMediaNativeAccountLifetimeTests {
    @Test func configurationIsInertAndUnarmedTransitionIsTerminal() async throws {
        let h = try Fixture()
        #expect(h.begins == 0 && h.finishes == 0)
        #expect(!FileManager.default.fileExists(atPath: h.parent.path))
        #expect(await h.drain.shutdown())
        #expect(throws: SharedMediaStorageFailure.closed) { _ = try h.discover() }
        #expect(h.begins == 0 && h.finishes == 0)
        #expect(!FileManager.default.fileExists(atPath: h.parent.path))
    }

    @Test(arguments: ["begin", "owner", "stale"])
    func invalidAccountRefusesBeforeFilesystem(reason: String) async throws {
        let h = try Fixture()
        h.beginFails = reason == "begin"; h.current = reason != "stale"
        let account = h.account(ownerID: reason == "owner" ? UUID() : h.ownerID)
        #expect(throws: (any Error).self) { _ = try h.drain.qualificationDiscover(account: account, support: h.support) }
        #expect(h.begins == 1 && h.finishes == (reason == "begin" ? 0 : 1))
        #expect(!FileManager.default.fileExists(atPath: h.parent.path))
        #expect(throws: SharedMediaStorageFailure.closed) { _ = try h.discover() }
        #expect(await h.drain.shutdown())
        await h.runtime.awaitAccountWorkDrain()
    }

    @Test func cancellationBeforeDiscoveryNeverAdmitsLease() async throws {
        let h = try Fixture()
        let task = Task { @MainActor in try h.discover() }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled discovery succeeded") } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(h.begins == 0 && h.finishes == 0)
        #expect(!FileManager.default.fileExists(atPath: h.parent.path))
        #expect(await h.drain.shutdown())
    }

    @Test(arguments: [false, true])
    func cancellationOrAccountChangeAfterFilesystemReleasesFence(cancel: Bool) async throws {
        let h = try Fixture()
        let task = Task { @MainActor in
            try h.drain.qualificationDiscover(account: h.account(), support: h.support, fault: { _ in
                if cancel { withUnsafeCurrentTask { $0?.cancel() } } else { h.current = false }
            })
        }
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(h.begins == 1 && h.finishes == 1)
        _ = try h.admission.acquireFence(container: h.container)
        #expect(throws: SharedMediaStorageFailure.closed) { _ = try h.discover() }
        #expect(await h.drain.shutdown())
        await h.runtime.awaitAccountWorkDrain()
    }

    @Test func discoveryFailureFinishesOriginalLeaseOnceAndDoesNotRepair() async throws {
        let h = try Fixture()
        try FileManager.default.createDirectory(at: h.parent, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { _ = try h.discover() }
        #expect(h.begins == 1 && h.finishes == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.parent.path).isEmpty)
        #expect(await h.drain.shutdown())
        #expect(await h.drain.shutdown())
        #expect(h.finishes == 1)
        await h.runtime.awaitAccountWorkDrain()
    }

    @Test func discoveryRetainsLeaseAndProvisionalFenceUntilShutdown() async throws {
        let h = try Fixture(), discovery = try h.discover()
        #expect(h.begins == 1 && h.finishes == 0)
        #expect(discovery.existingProfile == nil)
        #expect(throws: (any Error).self) { _ = try h.admission.acquireFence(container: h.container) }
        #expect(throws: SharedMediaStorageFailure.closed) { _ = try h.discover() }
        #expect(await SupabaseManager.drainPhotoPreparationBeforeAccountWork(preparation: nil,
            native: { await h.drain.shutdown() }, drain: { await h.runtime.awaitAccountWorkDrain() }))
        #expect(h.finishes == 1)
        _ = try h.admission.acquireFence(container: h.container)
        #expect(await h.drain.shutdown())
        #expect(h.finishes == 1)
    }

    @Test func sameOwnerInDifferentRuntimeCannotAttachAndStaleLeaseCannotDispatch() async throws {
        let h = try Fixture()
        let discovery = try h.discover()
        let replacement = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: AuthRuntimeState())
        #expect(throws: PhotoPreparationFailure.accountChanged) {
            _ = try SharedMediaNativeOriginalOwner.appInitialization(account: replacement, drain: h.drain)
        }
        let registration = try h.drain.register(account: h.account()) { true }
        #expect(h.drain.isCurrent(registration, container: h.container, discovery: discovery))
        #expect(!h.drain.isCurrent(registration, container: try ModelContainerFactory.makeInMemoryContainer()))
        #expect(!h.drain.isCurrent(registration, container: h.container))
        h.current = false
        #expect(!h.drain.isCurrent(registration))
        #expect(await h.drain.shutdown())
        #expect(h.finishes == 1)
        await h.runtime.awaitAccountWorkDrain()
    }

    @Test func registrationRequiresDiscoveryAndSameOwner() async throws {
        let h = try Fixture()
        #expect(throws: (any Error).self) { _ = try SharedMediaNativeOriginalOwner.appInitialization(account: h.account(), drain: h.drain) }
        _ = try h.discover()
        #expect(throws: PhotoPreparationFailure.accountChanged) {
            _ = try SharedMediaNativeOriginalOwner.appInitialization(account: h.account(ownerID: UUID()), drain: h.drain)
        }
        #expect(await h.drain.shutdown())
        #expect(h.finishes == 1)
    }

    @Test func wrongContainerRefusesBeforeOwnerWork() async throws {
        let h = try Fixture(), discovery = try h.discover()
        let owner = try SharedMediaNativeOriginalOwner.appInitialization(account: h.account(), drain: h.drain)
        let other = try ModelContainerFactory.makeInMemoryContainer()
        await #expect(throws: SharedMediaStorageFailure.closed) {
            _ = try await owner.initializeApp(container: other, parent: discovery.parent,
                inventoryID: discovery.inventoryID, discovery: discovery)
        }
        #expect(h.begins == 1)
        #expect(await h.drain.shutdown())
        #expect(h.finishes == 1)
    }

    @Test func realOwnerOperationAndLifetimeFinishBeforeFinalAuthDrain() async throws {
        let h = try Fixture(), discovery = try h.discover()
        let owner = try SharedMediaNativeOriginalOwner.appInitialization(account: h.account(), drain: h.drain)
        _ = try await owner.initializeApp(container: h.container, parent: discovery.parent,
            inventoryID: discovery.inventoryID, discovery: discovery)
        #expect(h.begins == 2 && h.finishes == 1)
        var order: [String] = []
        let drained = await SupabaseManager.drainPhotoPreparationBeforeAccountWork(preparation: {
            #expect(h.finishes == 2); order.append("photo"); return true
        }, native: {
            order.append("native"); return await h.drain.shutdown()
        }, drain: { await h.runtime.awaitAccountWorkDrain(); order.append("auth") })
        #expect(drained)
        #expect(order == ["native", "photo", "auth"])
        #expect(h.finishes == 2)
        await #expect(throws: (any Error).self) { _ = try await owner.snapshot() }
    }

    @Test func failedShutdownKeepsLeaseAndSealsUntilExplicitRetry() async throws {
        let h = try Fixture()
        _ = try h.discover()
        var attempts = 0
        let registration = try h.drain.register(account: h.account()) {
            attempts += 1
            #expect(h.finishes == 0)
            // Provisional discovery is invalidated before entering owner teardown.
            do { _ = try h.admission.acquireFence(container: h.container) } catch { Issue.record("Provisional fence retained") }
            return attempts == 2
        }
        #expect(!(await SupabaseManager.drainPhotoPreparationBeforeAccountWork(preparation: {
            Issue.record("Photo drain followed failed native shutdown"); return true
        }, native: { await h.drain.shutdown() }, drain: { Issue.record("Auth drained failed native shutdown") })))
        #expect(attempts == 1 && h.finishes == 0)
        #expect(!h.drain.isCurrent(registration))
        #expect(throws: SharedMediaStorageFailure.closed) { _ = try h.discover() }
        h.current = false // Recovery must finish the original lease, even after session change.
        #expect(await h.drain.shutdown())
        #expect(attempts == 2 && h.finishes == 1)
        await h.runtime.awaitAccountWorkDrain()
    }

    @Test func cancelledConcurrentWaiterDoesNotCancelSharedTeardown() async throws {
        let h = try Fixture(), gate = Gate()
        _ = try h.discover()
        var callbacks = 0
        _ = try h.drain.register(account: h.account()) {
            callbacks += 1
            await gate.pause()
            #expect(!Task.isCancelled)
            return true
        }
        let first = Task { await h.drain.shutdown() }
        await gate.arrived()
        first.cancel()
        let second = Task { await h.drain.shutdown() }
        #expect(h.finishes == 0)
        gate.release()
        #expect(await first.value)
        #expect(await second.value)
        #expect(callbacks == 1 && h.finishes == 1)
        await h.runtime.awaitAccountWorkDrain()
    }

    @Test func ordinaryAppGateCannotConfigureLifetime() throws {
        #expect(!PreparedHistoryReanalysisComposition.isAppInstallationQualified)
        var invoked = false
        #expect(PreparedHistoryReanalysisComposition.appInstallation { invoked = true; preconditionFailure("Gate opened") } == nil)
        #expect(!invoked)
        let h = try Fixture(), dependencies = AppDIContainer.shared
        try dependencies.configureNativeMediaLifetime(container: h.container, admission: h.admission)
        try dependencies.configureNativeMediaLifetime(container: h.container, admission: h.admission)
        #expect(dependencies.nativeMediaLifetime == nil)
        #expect(h.begins == 0 && !FileManager.default.fileExists(atPath: h.parent.path))
        let app = try DatabaseActorTestSupport.loadRepositorySource(at: "apps/ios/Merian/App/MerianApp.swift")
        #expect(app.contains("dependencies.configureNativeMediaLifetime(container: bootstrapOutcome.container,"))
    }

    @MainActor private final class Fixture {
        let support: URL, container: ModelContainer, admission: NativeReleaseStartupAdmission, ownerID: UUID
        let runtime = AuthRuntimeState()
        let drain: SharedMediaNativeOriginalDrain
        var begins = 0, finishes = 0
        var beginFails = false, current = true
        var parent: URL { support.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentName) }
        init() throws {
            let store = try SharedMediaNativeAppBootstrapTests.Store(startupEligible: true)
            support = store.parent.deletingLastPathComponent(); ownerID = store.ownerID
            let startup = try store.startup(); container = startup.0; admission = startup.1
            drain = .init(container: container, admission: admission)
        }
        func account(ownerID: UUID? = nil) -> PhotoOriginalPreparationOwner.AccountAccess {
            let session = AuthTransitionSession(userID: self.ownerID, isAnonymous: false)
            return .init(ownerID: ownerID ?? self.ownerID, begin: {
                self.begins += 1
                if self.beginFails { throw PhotoPreparationFailure.accountChanged }
                return self.runtime.beginAccountWork(session: session)
            }, isCurrent: { self.current && self.runtime.accountWorkLeaseIsCurrent($0, publishedSession: session, sdkSession: session) }, finish: {
                #expect(self.runtime.finishAccountWork($0)); self.finishes += 1
            })
        }
        func discover() throws -> SharedMediaNativeBootstrapDiscovery {
            try drain.qualificationDiscover(account: account(), support: support)
        }
    }

    @MainActor private final class Gate {
        private var entered = false
        private var waiting: CheckedContinuation<Void, Never>?, arrival: CheckedContinuation<Void, Never>?
        func pause() async {
            entered = true; arrival?.resume(); arrival = nil
            await withCheckedContinuation { waiting = $0 }
        }
        func arrived() async {
            if !entered { await withCheckedContinuation { arrival = $0 } }
        }
        func release() { waiting?.resume(); waiting = nil }
    }
}
