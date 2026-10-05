import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct ReanalysisAdmissionRuntimeTests {
    typealias Runtime = ObservationReanalysisAdmissionRuntime
    typealias Store = ObservationReanalysisAdmissionStore
    let fixture = ObservationReanalysisRecoveryTests()

    func idle(_ runtime: Runtime) async throws {
        let deadline = Date().addingTimeInterval(5)
        while runtime.isRunning, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(!runtime.isRunning)
    }

    @Test func preLockFailuresHaveFiniteVolatileBudgetAndNeverRewriteSubmission() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        var now = Date(timeIntervalSince1970: 2_000_000_000), calls = 0
        let owner = ObservationReanalysisPreparationOwner(), account = fixture.producerFixture.account()
        let executor = ObservationReanalysisAdmissionExecutor(files: .init(documents: seed.root), ownership: owner, account: account, now: { now })
        let initial = try Store.read(seed.pending.draft.identity, container: seed.container, isCurrent: { true })
        let runtime = Runtime(preparation: owner, dependencies: .init(scope: { .init(ownerID: seed.source.ownerID, container: seed.container) },
            consentGranted: { false }, networkAllowed: { false }, execute: {
                calls += 1
                return try await executor.execute($0, container: $1, consentGranted: $2, canPreflight: $3, isCurrent: $4)
            }, didAdmit: {}, account: account, now: { now }, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }))
        for attempt in 1...3 {
            runtime.request(); try await idle(runtime)
            #expect(calls == attempt)
            #expect((runtime.scheduledWakeDate != nil) == (attempt < 3))
            #expect(try Store.read(initial.identity, container: seed.container, isCurrent: { true }) == initial)
            now = now.addingTimeInterval(20)
        }
        runtime.request(); try await idle(runtime); #expect(calls == 3 && runtime.scheduledWakeDate == nil)
        runtime.request(.foreground); try await idle(runtime); #expect(calls == 4)
        await runtime.cancelAndAwait()
    }

    @Test func localRecoveryWorksOfflineButReadyAdmissionHasNoConsentOffWake() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await fixture.publish(seed)
        let owner = ObservationReanalysisPreparationOwner(), account = fixture.producerFixture.account()
        let executor = ObservationReanalysisAdmissionExecutor(files: .init(documents: seed.root), ownership: owner, account: account)
        let runtime = Runtime(preparation: owner, dependencies: .init(scope: { .init(ownerID: seed.source.ownerID, container: seed.container) },
            consentGranted: { false }, networkAllowed: { false }, execute: {
                try await executor.execute($0, container: $1, consentGranted: $2, canPreflight: $3, isCurrent: $4)
            }, didAdmit: { Issue.record("Local recovery cannot admit inference") }, account: account))
        runtime.request(.foreground); try await idle(runtime)
        let ready = try Store.read(seed.pending.draft.identity, container: seed.container, isCurrent: { true })
        #expect(ready.work.phase == .admissionPending && runtime.scheduledWakeDate == nil)
        runtime.request(); try await idle(runtime); #expect(runtime.scheduledWakeDate == nil)
        await runtime.cancelAndAwait()
    }

    @Test func onlyExplicitMatchingGrantRearmsConsentHold() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await fixture.publish(seed); _ = try await fixture.recover(seed)
        var now = Date(timeIntervalSince1970: 2_000_000_000), admitted = 0
        let identity = seed.pending.draft.identity
        let initial = try Store.read(identity, container: seed.container, isCurrent: { true })
        let claim = try Store.claim(initial, admission: .initial, now: now, container: seed.container, isCurrent: { true })
        try Store.settle(claim, as: .held(.consentRequired), now: now, container: seed.container, isCurrent: { true })
        let account = fixture.producerFixture.account(), owner = ObservationReanalysisPreparationOwner()
        let executor = ObservationReanalysisAdmissionExecutor(files: .init(documents: seed.root), ownership: owner,
            admission: .init(account: account, preflight: { _, _, validate in .init(recipient: .gemini, validate: validate) }), account: account, now: { now })
        let runtime = Runtime(preparation: owner, dependencies: .init(scope: { .init(ownerID: identity.ownerID, container: seed.container) },
            consentGranted: { true }, networkAllowed: { true }, execute: {
                try await executor.execute($0, container: $1, consentGranted: $2, canPreflight: $3, isCurrent: $4)
            }, didAdmit: { admitted += 1 }, account: account, now: { now }, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }))
        runtime.request(); try await idle(runtime); #expect(runtime.scheduledWakeDate == nil)
        runtime.request(.consentGranted(UUID())); try await idle(runtime); #expect(runtime.scheduledWakeDate == nil)
        runtime.request(.consentGranted(identity.ownerID)); try await idle(runtime)
        #expect(runtime.scheduledWakeDate == now.addingTimeInterval(1))
        now = now.addingTimeInterval(2); runtime.request(); try await idle(runtime)
        #expect(admitted == 1 && runtime.scheduledWakeDate == nil)
        await runtime.cancelAndAwait()
    }

    @Test func activeProducerIsSkippedUntilExplicitSubmissionWake() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let owner = ObservationReanalysisPreparationOwner(), entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, calls = 0
        let producer = Task {
            try await owner.perform(seed.pending.draft.identity) { _ in
                await withCheckedContinuation { release = $0; entered.continuation.yield() }
            }
        }
        for await _ in entered.stream { break }
        let runtime = Runtime(preparation: owner, dependencies: .init(scope: { .init(ownerID: seed.source.ownerID, container: seed.container) },
            consentGranted: { false }, networkAllowed: { false }, execute: { _, _, _, _, _ in calls += 1; return .unclaimed },
            didAdmit: {}, account: fixture.producerFixture.account(), sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }))
        runtime.request(); try await idle(runtime); #expect(calls == 0 && runtime.scheduledWakeDate == nil)
        try #require(release).resume(); try await producer.value
        runtime.request(.submitted(seed.pending.draft.identity.analysisID)); try await idle(runtime); #expect(calls == 1)
        await runtime.cancelAndAwait()
    }

    @Test func authDrainRetainsUncooperativePassAndBlocksResurrection() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let entered = AsyncStream<Void>.makeStream(); defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, admitted = 0, finishedLeases = 0, drained = false
        let runtime = Runtime(preparation: .init(), dependencies: .init(scope: { .init(ownerID: seed.source.ownerID, container: seed.container) },
            consentGranted: { true }, networkAllowed: { true }, execute: { _, _, _, _, _ in
                await withCheckedContinuation { release = $0; entered.continuation.yield() }
                return .admitted
            }, didAdmit: { admitted += 1 }, account: fixture.producerFixture.account(finish: { finishedLeases += 1 })))
        runtime.request()
        for await _ in entered.stream { break }
        let drain = Task { await runtime.cancelAndAwait(); drained = true }
        await Task.yield()
        runtime.request(.foreground)
        #expect(!drained && runtime.isRunning && finishedLeases == 0)
        try #require(release).resume(); await drain.value
        #expect(drained && !runtime.isRunning && finishedLeases == 1 && admitted == 0 && runtime.scheduledWakeDate == nil)
    }

    @Test func leaseFailureUsesSameFiniteDiscoveryBudget() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        var now = Date(timeIntervalSince1970: 2_000_000_000), begins = 0
        var account = fixture.producerFixture.account()
        account.begin = { _ in begins += 1; throw ObservationHistoryError.unavailable }
        let runtime = Runtime(preparation: .init(), dependencies: .init(scope: { .init(ownerID: seed.source.ownerID, container: seed.container) },
            consentGranted: { false }, networkAllowed: { false }, execute: { _, _, _, _, _ in Issue.record("No lease"); return .unclaimed },
            didAdmit: {}, account: account, now: { now }, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }))
        for _ in 0..<4 { runtime.request(); try await idle(runtime); now = now.addingTimeInterval(20) }
        #expect(begins == 3 && runtime.scheduledWakeDate == nil)
        await runtime.cancelAndAwait()
    }

    @Test(arguments: [false, true])
    func explicitEventsReopenExhaustedDiscovery(grant: Bool) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        if grant { try await fixture.publish(seed); _ = try await fixture.recover(seed) }
        var now = Date(timeIntervalSince1970: 2_000_000_000), failing = true, calls = 0, begins = 0
        let identity = seed.pending.draft.identity
        if grant {
            let initial = try Store.read(identity, container: seed.container, isCurrent: { true })
            let claim = try Store.claim(initial, admission: .initial, now: now, container: seed.container, isCurrent: { true })
            try Store.settle(claim, as: .held(.consentRequired), now: now, container: seed.container, isCurrent: { true })
        }
        var account = fixture.producerFixture.account()
        let begin = account.begin
        account.begin = { owner in
            begins += 1
            if failing { throw ObservationHistoryError.unavailable }
            return try begin(owner)
        }
        let runtime = Runtime(preparation: .init(), dependencies: .init(scope: { .init(ownerID: identity.ownerID, container: seed.container) },
            consentGranted: { true }, networkAllowed: { true }, execute: { _, _, _, _, _ in calls += 1; return .unclaimed },
            didAdmit: {}, account: account, now: { now }, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }))
        for _ in 0..<3 { runtime.request(); try await idle(runtime); now = now.addingTimeInterval(20) }
        #expect(begins == 3)
        failing = false
        runtime.request(); try await idle(runtime); #expect(begins == 3)
        runtime.request(grant ? .consentGranted(identity.ownerID) : .submitted(identity.analysisID)); try await idle(runtime)
        #expect(begins == 4)
        if grant {
            let saved = try Store.read(identity, container: seed.container, isCurrent: { true })
            #expect(saved.work.state == .waiting && saved.work.hold == nil && calls == 0)
        } else { #expect(calls == 1) }
        await runtime.cancelAndAwait()
    }

}
