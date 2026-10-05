import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAnalysisReviewDiscoveryTests {
    typealias Store = ObservationAnalysisReviewPersistence
    let fixture = ObservationAnalysisReviewPersistenceTests()

    @Test(arguments: ["running-no-expiry", "running-no-start", "running-short-expiry", "running-zero-attempt", "waiting-no-expiry", "pending-attempted"])
    func malformedClaimCannotWakeOrRedispatch(_ damage: String) throws {
        let container = try fixture.container(), intent = try fixture.stage(container), context = ModelContext(container)
        let job = try #require(try context.fetchOfflineJob(id: Store.jobID(intent.request.operationID, observationID: intent.request.observationID)))
        job.status = .running; job.attemptCount = 1; job.lastAttemptAt = fixture.now
        job.nextRunAt = fixture.now.addingTimeInterval(180)
        switch damage {
        case "running-no-expiry": job.nextRunAt = nil
        case "running-no-start": job.lastAttemptAt = nil
        case "running-short-expiry": job.nextRunAt = fixture.now.addingTimeInterval(10)
        case "running-zero-attempt": job.attemptCount = 0
        case "waiting-no-expiry": job.status = .waiting; job.nextRunAt = nil
        default: job.status = .pending
        }
        try context.save()
        #expect(try Store.candidates(container: container, ownerID: fixture.owner).isEmpty)
        #expect(throws: Store.IntegrityError.self) {
            try Store.claim(intent, at: fixture.now.addingTimeInterval(1000), container: container, isCurrent: { true })
        }
        #expect(try Store.restore(job).request == intent.request)
    }

    @Test func originalExpiryAndReceivedImmediateReconciliationRemainRecoverable() throws {
        let container = try fixture.container(), intent = try fixture.stage(container)
        let first = try fixture.claim(intent, in: container)
        #expect(try Store.candidates(container: container, ownerID: fixture.owner).first?.1 == first.expiresAt)
        #expect(try Store.claim(intent, at: fixture.now, container: container, isCurrent: { true }) == nil)
        let next = try fixture.claim(intent, in: container, at: first.expiresAt)
        let receipt = try Store.acknowledge(fixture.receipt(intent.request), claim: next, at: next.expiresAt,
                                          container: container, isCurrent: { true })
        #expect(try Store.candidates(container: container, ownerID: fixture.owner).first?.0.hasReceipt == true)
        let recovery = try fixture.claim(receipt, in: container, at: next.expiresAt)
        #expect(throws: (any Error).self) {
            try Store.requireDispatch(recovery, at: next.expiresAt, container: container, isCurrent: { true })
        }
    }

    @Test func scopeReadFailurePropagatesButDeletionAndHoldsDoNotWake() throws {
        let container = try fixture.container(), intent = try fixture.stage(container), context = ModelContext(container)
        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>())
        #expect(throws: CocoaError.self) {
            try Store.discover(jobs, ownerID: fixture.owner, validateScope: { _ in throw CocoaError(.fileReadUnknown) })
        }
        #expect(throws: Store.IntegrityError.self) {
            try Store.discover(jobs, ownerID: fixture.owner, validateScope: { _ in throw Store.IntegrityError.accountChanged })
        }
        #expect(try Store.discover(jobs, ownerID: UUID(), validateScope: { _ in Issue.record("Wrong owner reached private scope") }).isEmpty)
        _ = try ObservationHistoryEnrollmentIntent.stage(observationID: intent.request.observationID, ownerID: fixture.owner, context: context)
        try context.save()
        #expect(try Store.candidates(container: container, ownerID: fixture.owner).isEmpty)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        context.delete(scan); try context.save()
        #expect(try Store.candidates(container: container, ownerID: fixture.owner).isEmpty)
    }
}
