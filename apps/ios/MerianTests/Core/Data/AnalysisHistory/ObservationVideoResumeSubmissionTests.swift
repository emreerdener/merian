import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoResumeSubmissionTests {
    typealias Service = ObservationVideoResumeSubmission
    enum Failure: Error { case save }

    @Test(arguments: ["ready", "staged", "reserved", "upload", "uploadReady", "idle", "running-consumed", "held-consumed"])
    func explicitContinuationKeepsOriginalChildAndPermittedPhase(_ phase: String) async throws {
        let fixture = ObservationVideoResumeStoreTests(), seed = try await fixture.seed(phase)
        defer { seed.remove() }
        let service = Service(producer: ObservationVideoDurabilityTests().producer(seed))
        let saved = try #require(try await service.resume(seed.preparation.identity, container: seed.container, isCurrent: { true }))
        #expect(saved.proof.preparation == seed.preparation)
        switch phase {
        case "ready", "staged":
            guard case let .reservation(snapshot) = saved.route else { Issue.record("Expected initial reservation"); return }
            #expect(snapshot.work.phase == .staged && snapshot.work.attemptID == nil)
        case "reserved", "upload", "uploadReady":
            guard case let .upload(snapshot) = saved.route else { Issue.record("Expected exact upload"); return }
            #expect(snapshot.work.receipt?.state == (phase == "uploadReady" ? .ready : nil))
        default:
            guard case let .execution(snapshot) = saved.route else { Issue.record("Expected original execution"); return }
            #expect(snapshot.work.consumed == phase.contains("consumed"))
        }
        try Service.validate(saved, container: seed.container, isCurrent: { true })
        let before = try fixture.metadata(seed)
        let second = try #require(try await service.resume(seed.preparation.identity, container: seed.container, isCurrent: { true }))
        #expect(second.proof.preparation == seed.preparation)
        #expect(try fixture.metadata(seed) == before)
        #expect(try ModelContext(seed.container).fetch(FetchDescriptor<LocalAnalysisRecord>()).count == 1)
    }

    @Test(arguments: ["unknown", "uploadUnknown", "running", "held"])
    func uncertainAttemptNeverAdvancesOrRearms(_ phase: String) async throws {
        let fixture = ObservationVideoResumeStoreTests(), seed = try await fixture.seed(phase)
        defer { seed.remove() }
        let before = try fixture.metadata(seed)
        let service = Service(producer: ObservationVideoDurabilityTests().producer(seed))
        #expect(try await service.resume(seed.preparation.identity, container: seed.container, isCurrent: { true }) == nil)
        #expect(try fixture.metadata(seed) == before)
    }

    @Test(arguments: ["ready", "reserved"], [false, true])
    func throwingStageCannotReturnDispatchEvenAfterCommit(_ phase: String, commit: Bool) async throws {
        let fixture = ObservationVideoResumeStoreTests(), seed = try await fixture.seed(phase)
        defer { seed.remove() }
        let before = try fixture.metadata(seed)
        var service = Service(producer: ObservationVideoDurabilityTests().producer(seed))
        let save: @MainActor @Sendable (ModelContext) throws -> Void = { context in
            if commit { try context.save() }
            throw Failure.save
        }
        service.reservationSave = save; service.uploadSave = save
        await #expect(throws: Failure.save) {
            try await service.resume(seed.preparation.identity, container: seed.container, isCurrent: { true })
        }
        let after = try fixture.metadata(seed)
        #expect((after != before) == commit)
        // A later explicit action can observe the committed local stage; it creates no remote attempt here.
        if commit {
            let later = Service(producer: service.producer)
            let result = try #require(try await later.resume(seed.preparation.identity, container: seed.container, isCurrent: { true }))
            #expect(result.proof.preparation == seed.preparation)
            #expect(try fixture.metadata(seed) == after)
        }
    }

    @Test(arguments: ["running", "held", "unavailable", "conflict"])
    func nonExecutableReservationStatesRemainHeldAfterReopen(_ state: String) async throws {
        let fixture = ObservationVideoReservationLifecycleTests(), (seed, entry) = try await fixture.staged()
        defer { seed.remove() }
        let claim = try ObservationVideoSourceReservationStore.claim(entry, proof: seed.proof, container: seed.container, isCurrent: { true })
        if state != "running" {
            let answer: ObservationVideoReservationSettlement = state == "conflict"
                ? .conflict(.init(request: entry.work.request, ownerID: seed.source.ownerID))
                : .reply(try fixture.reply(entry, state: state))
            _ = try ObservationVideoSourceReservationStore.settle(claim, settlement: answer, proof: seed.proof,
                container: seed.container, isCurrent: { true })
        }
        let before = try ObservationVideoResumeStoreTests().metadata(seed)
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        let service = Service(producer: ObservationVideoDurabilityTests().producer(seed))
        #expect(try await service.resume(seed.preparation.identity, container: reopened, isCurrent: { true }) == nil)
        #expect(try ObservationVideoResumeStoreTests().metadata(seed, container: reopened) == before)
    }

    @Test func incompletePreparationDoesNotRegenerateFiles() async throws {
        let fixture = ObservationVideoResumeStoreTests(), seed = try await fixture.seed("pending")
        defer { seed.remove() }
        let before = try fixture.metadata(seed)
        let service = Service(producer: ObservationVideoDurabilityTests().producer(seed))
        await #expect(throws: (any Error).self) {
            try await service.resume(seed.preparation.identity, container: seed.container, isCurrent: { true })
        }
        #expect(try fixture.metadata(seed) == before)
        for file in seed.preparation.files { #expect(!FileManager.default.fileExists(atPath: seed.root.appendingPathComponent(file.path).path)) }
    }
}
