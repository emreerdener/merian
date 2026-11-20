import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct SavedIdentificationReanalysisTests {
    let fixture = ObservationHistoryEnrollmentTests()
    var observation: UUID { UUID(uuidString: fixture.support.support.observation)! }
    var owner: UUID { fixture.support.support.owner }

    @Test func explicitLegacyTapEnrollsOnceAndReturnsExactImportedSourceWithoutChangingDisplay() async throws {
        let container = try fixture.container(), routes = AppRouteCoordinator()
        var cloud = fixture.service().cloud, calls = 0
        let enroll = cloud.enroll
        cloud.enroll = { id in calls += 1; return try await enroll(id) }
        let access = make(cloud: cloud, container: container, routes: routes)
        let baseline = try ObservationHistoryEnrollmentService.baseline(observation: observation, container: container)
        let request = try access.prepare(observation.uuidString, baseline, container)
        #expect(calls == 0 && routes.pendingRequests.isEmpty)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        let action = try await request.resolve()
        let target = try action.resolve()
        #expect(target.analysisID.uuidString.lowercased() == fixture.support.analysisID && target.ownerID == owner)
        #expect(calls == 1 && routes.pendingRequests.isEmpty)
        let current = try ObservationHistoryStateSyncService.displayBaseline(observation: observation, container: container)
        #expect(current.retainsIdentification(of: baseline))
        let source = try ObservationReanalysisSource.capture(observationID: observation, analysisID: target.analysisID, ownerID: owner, container: container)
        #expect(source.photos.isEmpty && source.evidence.isEmpty)
        access.dispatch(target)
        #expect(routes.pendingRequests.first?.route == .historicalReanalysis(target))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test func enrolledTapUsesSavedSourceWithoutEnrollmentOrInferenceConsent() async throws {
        let seed = try ObservationReanalysisSourceTests().seed(), routes = AppRouteCoordinator()
        let seedOwner = ObservationReanalysisSourceTests().fixture.owner
        var cloud = ObservationReanalysisProducerTests().account()
        cloud.enroll = { _ in Issue.record("Already enrolled tap requested enrollment"); throw MerianError.invalidResponse }
        let access = SavedIdentificationReanalysisAccess.prepared(cloud: cloud, enrollment: .init(), currentOwner: { seedOwner },
            generation: { 1 }, sessionIsCurrent: { _ in true }, containerIsCurrent: { $0 === seed.container },
            dispatch: { routes.request(.historicalReanalysis($0), source: .internalUserAction) })
        let baseline = try ObservationHistoryStateSyncService.displayBaseline(observation: seed.observationID, container: seed.container)
        let request = try access.prepare(seed.observationID.uuidString, baseline, seed.container)
        let action = try await request.resolve(), target = try action.resolve()
        #expect(target.analysisID == seed.result.analysisID)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func staleDisplayedCorrectionFailsBeforeEnrollment() throws {
        let container = try fixture.container()
        let baseline = try ObservationHistoryEnrollmentService.baseline(observation: observation, container: container)
        let context = ModelContext(container), scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        scan.commonName = "Different synthetic correction"; try context.save()
        let access = make(cloud: fixture.service().cloud, container: container)
        #expect(throws: ObservationHistoryEnrollmentService.AdmissionError.localStateChanged) {
            try access.prepare(observation.uuidString, baseline, container)
        }
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test(arguments: ["owner", "generation", "session", "container"])
    func staleAccountEnvironmentCannotAdmitOrReturnPrivateResult(_ reason: String) async throws {
        let container = try fixture.container()
        var currentOwner = owner, generation: UInt64 = 1, session = true, activeContainer = container
        let cloud = fixture.service(duringEnroll: {
            switch reason {
            case "owner": currentOwner = UUID()
            case "generation": generation += 2
            case "session": session = false
            default: activeContainer = try fixture.container()
            }
        }).cloud
        let access = SavedIdentificationReanalysisAccess.prepared(cloud: cloud, enrollment: .init(), currentOwner: { currentOwner },
            generation: { generation }, sessionIsCurrent: { _ in session }, containerIsCurrent: { $0 === activeContainer }, dispatch: { _ in Issue.record("Stale dispatch") })
        let baseline = try ObservationHistoryEnrollmentService.baseline(observation: observation, container: container)
        let request = try access.prepare(observation.uuidString, baseline, container)
        await #expect(throws: ObservationHistoryError.accountChanged) { try await request.resolve() }
        try fixture.expectUnenrolled(container)
        #expect(try ObservationHistoryEnrollmentIntent.holds(observation.uuidString, context: ModelContext(container)))
    }

    @Test(arguments: ["selection", "revision", "source", "deletion", "pending-review"])
    func resolvedActionCannotRetargetAfterParentOrSourceChanges(_ reason: String) async throws {
        let container = try fixture.container()
        let access = make(cloud: fixture.service().cloud, container: container)
        let request = try access.prepare(observation.uuidString,
            ObservationHistoryEnrollmentService.baseline(observation: observation, container: container), container)
        let action = try await request.resolve()
        let context = ModelContext(container), scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        switch reason {
        case "selection": scan.selectedAnalysisID = UUID().uuidString.lowercased()
        case "revision": scan.observationStateRevision = try #require(scan.observationStateRevision) + 1
        case "source": context.delete(try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first))
        case "pending-review": context.insert(OfflineJobRecord(id: "fixture-pending-review", kind: .identificationReviewSync, subjectId: scan.id))
        default: context.delete(scan)
        }
        try context.save()
        #expect(throws: (any Error).self) { try action.resolve() }
    }

    @Test func cancelledWaiterCannotRouteButCommittedEnrollmentSurvives() async throws {
        let container = try fixture.container(), entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?
        var cloud = fixture.service().cloud
        cloud.enroll = { _ in
            await withCheckedContinuation { release = $0; entered.continuation.yield() }
            return try fixture.receipt()
        }
        let access = make(cloud: cloud, container: container)
        let request = try access.prepare(observation.uuidString,
            ObservationHistoryEnrollmentService.baseline(observation: observation, container: container), container)
        let task = Task { try await request.resolve() }
        for await _ in entered.stream { break }
        task.cancel(); release?.resume()
        await #expect(throws: CancellationError.self) { try await task.value }
        let source = try ObservationReanalysisSource.capture(observationID: observation, ownerID: owner, container: container)
        #expect(source.analysisID.uuidString.lowercased() == fixture.support.analysisID)
    }

    private func make(cloud: ObservationHistoryCloudClient, container: ModelContainer,
                      routes: AppRouteCoordinator? = nil) -> SavedIdentificationReanalysisAccess {
        let routes = routes ?? AppRouteCoordinator()
        return .prepared(cloud: cloud, enrollment: .init(), currentOwner: { self.owner }, generation: { 1 },
            sessionIsCurrent: { $0.userID == self.owner }, containerIsCurrent: { $0 === container },
            dispatch: { routes.request(.historicalReanalysis($0), source: .internalUserAction) })
    }
}
