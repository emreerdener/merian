import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ProtectedInsightChatDeliveryOwnerTests {
    @Test func cancellationKeepsSettlementButAuthInvalidationWaitsForActualExit() async throws {
        let owner = ProtectedInsightChatDeliveryOwner(), entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?
        var current: ProtectedInsightChatDeliveryOwner.Predicate?, dispatch: ProtectedInsightChatDeliveryOwner.Predicate?
        var exits = 0, drained = false
        #expect(owner.start(operation: { identity, permission in
            current = identity; dispatch = permission
            await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
        }, didFinish: { exits += 1 }))
        var iterator = entered.stream.makeAsyncIterator(); _ = await iterator.next()
        owner.cancel()
        #expect(owner.isRunning && current?() == true && dispatch?() == false && exits == 0)
        #expect(!owner.start(operation: { _, _ in Issue.record("Overlapped send") }, didFinish: { exits += 100 }))
        let teardown = Task { await owner.invalidateAndAwait(); drained = true }
        await Task.yield()
        #expect(owner.isRunning && current?() == false && !drained)
        try #require(release).resume(); await teardown.value
        #expect(!owner.isRunning && drained && exits == 1 && current?() == false)
    }

    @Test func authInvalidationBlocksTheEmptySlotBeforeItsAwait() async throws {
        let owner = ProtectedInsightChatDeliveryOwner(), entered = AsyncStream<Void>.makeStream(), exited = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); exited.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?
        let started = owner.start(operation: { _, _ in
            await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
        }, didFinish: { exited.continuation.yield(()) })
        #expect(started)
        var iterator = entered.stream.makeAsyncIterator(); _ = await iterator.next()
        owner.invalidate(); try #require(release).resume()
        var exitIterator = exited.stream.makeAsyncIterator(); _ = await exitIterator.next()
        #expect(!owner.isRunning)
        let denied = owner.start(operation: { _, _ in Issue.record("Admitted during Auth gap") }, didFinish: {})
        #expect(!denied)
        await owner.invalidateAndAwait()
        let resumed = owner.start(operation: { _, _ in }, didFinish: {})
        #expect(resumed)
        await owner.invalidateAndAwait()
    }

    @Test func overlappingAuthDrainsKeepAdmissionClosedThroughActualExit() async throws {
        let owner = ProtectedInsightChatDeliveryOwner(), entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, exits = 0
        let started = owner.start(operation: { _, _ in
            await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
        }, didFinish: {
            exits += 1
            let reentered = owner.start(operation: { _, _ in Issue.record("Admitted during drains") }, didFinish: {})
            #expect(!reentered)
        })
        #expect(started)
        var iterator = entered.stream.makeAsyncIterator(); _ = await iterator.next()
        let first = Task { await owner.invalidateAndAwait() }
        let second = Task { await owner.invalidateAndAwait() }
        await Task.yield()
        try #require(release).resume()
        await first.value; await second.value
        #expect(exits == 1 && !owner.isRunning)
        let resumed = owner.start(operation: { _, _ in }, didFinish: {})
        #expect(resumed)
        await owner.invalidateAndAwait()
    }

    @Test func queueRetainsSendAndRefreshesOnlyAfterLeaseRelease() async throws {
        let fixture = ProtectedInsightChatClaimsTests(), (container, intent) = try await fixture.seed()
        let manager = OfflineQueueManager.shared, previous = manager.modelContext, wasOnline = manager.isOnline
        #expect(!manager.protectedChatDeliveryOwner.isRunning)
        manager.modelContext = ModelContext(container); manager.isOnline = true
        defer { manager.modelContext = previous; manager.isOnline = wasOnline }
        let entered = AsyncStream<Void>.makeStream(), exited = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); exited.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, finishedLease = false
        let cloud = fixture.support.source.support.client(fetch: { _ in throw MerianError.invalidResponse }, finish: {
            finishedLease = true; exited.continuation.yield(())
        })
        let service = ProtectedInsightChatDeliveryService(cloud: cloud, submit: { request, _, _, dispatch, response in
            try dispatch()
            await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
            try response()
            return try .init(data: fixture.receipt(intent), request: request)
        }, now: { fixture.start })
        let generation = manager.protectedChatDeliveryGeneration
        let started = manager.requestProtectedChatDelivery(intent, admission: .initial, service: service, currentOwnerID: { intent.ownerID })
        #expect(started)
        var iterator = entered.stream.makeAsyncIterator(); _ = await iterator.next()
        let duplicated = manager.requestProtectedChatDelivery(intent, admission: .initial, service: service, currentOwnerID: { intent.ownerID })
        #expect(!duplicated)
        manager.isOnline = false; manager.protectedChatDeliveryOwner.cancel()
        #expect(!finishedLease && manager.protectedChatDeliveryGeneration == generation)
        try #require(release).resume()
        var exitIterator = exited.stream.makeAsyncIterator(); _ = await exitIterator.next()
        // The service releases its lease synchronously before the retained task advances the epoch.
        #expect(finishedLease && !manager.protectedChatDeliveryOwner.isRunning)
        #expect(manager.protectedChatDeliveryGeneration == generation &+ 1)
        #expect(try ProtectedInsightChatPersistence.read(intent, container: container, isCurrent: { true }).isComplete)
    }

    @Test func completionGenerationRejectsAnotherAccountOrContext() async throws {
        let fixture = ProtectedInsightChatClaimsTests(), (container, intent) = try await fixture.seed()
        let manager = OfflineQueueManager.shared, previous = manager.modelContext
        let context = ModelContext(container), other = ModelContext(container)
        manager.modelContext = context; defer { manager.modelContext = previous }
        let generation = manager.protectedChatDeliveryGeneration
        manager.protectedChatDeliveryDidFinish(ownerID: intent.ownerID, context: context, currentOwnerID: UUID())
        manager.modelContext = other
        manager.protectedChatDeliveryDidFinish(ownerID: intent.ownerID, context: context, currentOwnerID: intent.ownerID)
        #expect(manager.protectedChatDeliveryGeneration == generation)
    }

    @Test func bothAuthBarriersAwaitAndConnectivityCancelsWithoutSchedulerAdmission() throws {
        let root = "apps/ios/Merian/Core/Data/OfflineSync/"
        for path in ["Services/OfflineQueueManager+ReanalysisExecution.swift", "Services/BackgroundTransfer/OfflineQueueManager+BackgroundAccountWork.swift"] {
            let source = try DatabaseActorTestSupport.loadRepositorySource(at: root + path)
            let invalidation = try #require(source.range(of: "protectedChatDeliveryOwner.invalidate()"))
            let wait = try #require(source.range(of: "await protectedChatDeliveryOwner.invalidateAndAwait()"))
            #expect(invalidation.lowerBound < wait.lowerBound)
        }
        let manager = try DatabaseActorTestSupport.loadRepositorySource(at: root + "OfflineQueueManager.swift")
        #expect(manager.components(separatedBy: "self.protectedChatDeliveryOwner.cancel()").count == 3)
        let scheduler = try DatabaseActorTestSupport.loadRepositorySource(at: root + "OfflineJobScheduler.swift")
        #expect(scheduler.contains("kind != .protectedInsightChatSync"))
        #expect(!scheduler.contains("requestProtectedChatDelivery"))
    }
}
