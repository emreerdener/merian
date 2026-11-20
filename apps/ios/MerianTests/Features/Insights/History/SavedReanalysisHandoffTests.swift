import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct SavedReanalysisHandoffTests {
    private let target = HistoricalReanalysisTarget(observationID: UUID(), analysisID: UUID(), ownerID: UUID())

    @Test func preparationDoesNotExecuteAndRepeatedDismissalsDispatchOnlyOnce() async {
        let owner = SavedReanalysisHandoff()
        var calls = 0, routes = 0
        let ticket = owner.prepare(request: .init(resolve: {
            calls += 1
            return .init { target }
        }), isCurrent: { true }, dispatch: { _ in routes += 1 }, failure: { Issue.record("Unexpected failure") })
        #expect(owner.isBusy && calls == 0)
        ticket.resume(); ticket.resume()
        await settle(owner)
        ticket.resume()
        #expect(calls == 1 && routes == 1 && !owner.isBusy)
    }

    @Test(arguments: [false, true])
    func changedPresentationBeforeOrDuringResolutionNeverDispatches(_ afterDispatch: Bool) async {
        let owner = SavedReanalysisHandoff(), entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        var current = true, calls = 0, routes = 0, failures = 0
        var release: CheckedContinuation<Void, Never>?
        let ticket = owner.prepare(request: .init(resolve: {
            calls += 1
            await withCheckedContinuation { release = $0; entered.continuation.yield() }
            return .init { target }
        }), isCurrent: { current }, dispatch: { _ in routes += 1 }, failure: { failures += 1 })
        if !afterDispatch { current = false }
        ticket.resume()
        if afterDispatch {
            for await _ in entered.stream { break }
            current = false
            release?.resume()
        }
        await settle(owner)
        #expect(calls == (afterDispatch ? 1 : 0) && routes == 0 && failures == 0)
    }

    @Test func abandonedAndOldTicketsCannotCancelOrResumeNewerWork() async {
        let owner = SavedReanalysisHandoff()
        var routes = 0
        let make = { owner.prepare(request: .init(resolve: { .init { target } }), isCurrent: { true },
            dispatch: { _ in routes += 1 }, failure: { Issue.record("Unexpected failure") }) }
        let first = make(), refused = make()
        refused.resume(); refused.cancel()
        #expect(owner.isBusy)
        first.cancel()
        let second = make()
        first.resume(); first.cancel(); refused.resume()
        #expect(owner.isBusy && routes == 0)
        second.resume()
        await settle(owner)
        #expect(routes == 1)
    }

    @Test func cancelledRunningWaiterCannotClearNewerPendingTicket() async {
        let owner = SavedReanalysisHandoff(), entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, routes = 0
        let first = owner.prepare(request: .init(resolve: {
            await withCheckedContinuation { release = $0; entered.continuation.yield() }
            return .init { target }
        }), isCurrent: { true }, dispatch: { _ in Issue.record("Cancelled result escaped") }, failure: { Issue.record("Cancelled failure escaped") })
        first.resume()
        for await _ in entered.stream { break }
        owner.cancel()
        let second = owner.prepare(request: .init(resolve: { .init { target } }), isCurrent: { true },
            dispatch: { _ in routes += 1 }, failure: { Issue.record("Unexpected failure") })
        release?.resume()
        for _ in 0..<10 { await Task.yield() }
        #expect(owner.isBusy)
        second.resume()
        await settle(owner)
        #expect(routes == 1)
    }

    @Test func changedStoredIdentificationBetweenTapAndDismissalFailsWithoutEnrollment() async throws {
        let fixture = ObservationHistoryEnrollmentTests(), container = try fixture.container()
        let observation = try #require(UUID(uuidString: fixture.support.support.observation))
        let account = fixture.support.support.owner
        var cloud = fixture.service().cloud, calls = 0, failures = 0
        cloud.enroll = { _ in calls += 1; throw MerianError.invalidResponse }
        let access = SavedIdentificationReanalysisAccess.prepared(cloud: cloud, enrollment: .init(), currentOwner: { account },
            generation: { 1 }, sessionIsCurrent: { _ in true }, containerIsCurrent: { $0 === container }, dispatch: { _ in })
        let request = try access.prepare(observation.uuidString, ObservationHistoryEnrollmentService.baseline(observation: observation, container: container), container)
        let owner = SavedReanalysisHandoff()
        let ticket = owner.prepare(request: request, isCurrent: { true }, dispatch: { _ in Issue.record("Retargeted route") }, failure: { failures += 1 })
        let context = ModelContext(container), record = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        record.commonName = "Synthetic correction after tap"; try context.save()
        ticket.resume()
        await settle(owner)
        #expect(failures == 1 && calls == 0)
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func childDisposalReleasesPrivateRequestAndAllowsAnotherTap() async {
        let owner = SavedReanalysisHandoff()
        weak var retained: NSObject?
        var ticket = SavedReanalysisTicket.unavailable
        do {
            let privateState = NSObject()
            retained = privateState
            let request = SavedIdentificationReanalysisAccess.Request(resolve: { [privateState] in
                _ = privateState
                Issue.record("Disposed child executed")
                return .init { target }
            })
            ticket = owner.prepare(request: request, isCurrent: { true }, dispatch: { _ in }, failure: {})
        }
        #expect(owner.isBusy && retained != nil)
        ticket.cancel()
        #expect(!owner.isBusy && retained == nil)
        var routes = 0
        let next = owner.prepare(request: .init(resolve: { .init { target } }), isCurrent: { true },
            dispatch: { _ in routes += 1 }, failure: { Issue.record("Unexpected failure") })
        ticket.resume(); next.resume()
        await settle(owner)
        #expect(routes == 1)
    }

    private func settle(_ owner: SavedReanalysisHandoff) async {
        for _ in 0..<1000 {
            if !owner.isBusy { return }
            await Task.yield()
        }
        Issue.record("Handoff did not settle")
    }
}
