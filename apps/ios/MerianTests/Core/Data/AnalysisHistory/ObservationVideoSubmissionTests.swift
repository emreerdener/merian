import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoSubmissionTests {
    typealias Seed = ObservationVideoDurabilityTests.Seed
    typealias Reservation = ObservationVideoSourceReservationStore
    typealias Upload = ObservationVideoUploadLifecycleStore
    typealias Execution = ObservationVideoExecutionStore

    @MainActor final class Boundary {
        let seed: Seed
        let entry: Reservation.Snapshot
        let queue = OfflineQueueManager.shared
        let exits = AsyncStream<Void>.makeStream()
        var current = true
        var begins = 0
        var finishes = 0
        var events: [String] = []
        var hook: (String) throws -> Void = { _ in }
        init(_ seed: Seed, _ entry: Reservation.Snapshot) { self.seed = seed; self.entry = entry }
        var key: ObservationVideoReservationOwner.Key { ObservationVideoReservationDeliveryTests().key(entry) }
        var account: ObservationHistoryCloudClient {
            .init(begin: { [self] owner in
                #expect(owner == seed.source.ownerID && begins == finishes)
                begins += 1; return .init(id: UUID(), session: key.session)
            }, isCurrent: { [self] in current && $0.session == key.session }, finish: { [self] _ in
                finishes += 1; exits.continuation.yield(())
            }, fetch: { _ in throw MerianError.invalidResponse })
        }
        func hit(_ event: String) throws { events.append(event); try hook(event) }
        var submission: ObservationVideoSubmissionService {
            .init(reservation: .init(verifyFiles: { [self] preparation, validate in
                _ = try await ObservationReanalysisFileStore(documents: seed.root).readVideo(preparation: preparation,
                    validateBeforeRead: validate, validateBeforeReturn: validate)
            }, reserve: { [self] candidate, owner, before, after in
                try before(); #expect(candidate == entry.work.request && owner == seed.source.ownerID)
                try hit("reserve"); try after()
                return try ObservationVideoReservationLifecycleTests().reply(entry)
            }), upload: .init(prepare: ObservationVideoUploadDeliveryTests().prepare(seed).prepare,
                upload: { [self] wire, owner, previous, before, after in
                    try before(); #expect(!queue.videoReservationOwner.isRunning && begins == 2 && finishes == 1)
                    let saved = try Upload.read(proof: seed.proof, container: seed.container, isCurrent: { true })
                    #expect(owner == seed.source.ownerID && wire.candidate == entry.work.request && previous == saved.work.receipt)
                    try hit("upload"); try after()
                    return try ObservationVideoUploadLifecycleTests().receipt(saved)
                }), authorize: { [self] owner, validate in
                    try validate(); #expect(owner == seed.source.ownerID)
                    try hit("bind"); try validate()
                    return .init(recipient: .gemini, validate: {})
                })
        }
        var execution: ObservationVideoExecutionService {
            .init(dependencies: .init(authorize: { [self] _, validate in
                try validate(); #expect(!queue.videoReservationOwner.isRunning && !queue.videoUploadOwner.isRunning)
                #expect(begins == finishes + 1)
                try hit("authorize"); return .init(recipient: .gemini, validate: {})
            }, analyze: { [self] permit, _, before, after in
                try before(); #expect(permit.snapshot.work.consumed)
                try hit("analyze"); try after()
                return .init(observationID: seed.source.observationID, analysisID: seed.preparation.identity.analysisID, state: .complete)
            }, outcome: { [self] _, before, after in
                try before(); try hit("outcome"); try after()
                return try ObservationVideoCompletionTests().result(seed.preparation.request)
            }))
        }
        var valid: @MainActor @Sendable (AuthTransitionSession, UInt64) -> Bool {
            { [self] in current && $0 == key.session && $1 == key.generation }
        }
        func drain(_ leases: Int) async {
            var iterator = exits.stream.makeAsyncIterator()
            for _ in 0..<leases { _ = await iterator.next() }
            await queue.videoReservationOwner.invalidateAndAwait()
            await queue.videoUploadOwner.invalidateAndAwait()
            await queue.videoExecutionOwner.invalidateAndAwait()
            #expect(begins == leases && finishes == leases)
        }
    }

    @Test(arguments: ["complete", "reservationUnknown", "uploadUnknown", "account", "cancel", "consent", "executionUnknown"])
    func explicitChainPreservesOneCandidateAndStopsAtUncertainBoundaries(_ mode: String) async throws {
        let (seed, entry) = try await ObservationVideoReservationLifecycleTests().staged()
        defer { seed.remove() }
        let proof = try seed.proof, boundary = Boundary(seed, entry), queue = boundary.queue
        let oldContext = queue.modelContext, oldOnline = queue.isOnline
        queue.modelContext = ModelContext(seed.container); queue.isOnline = true
        defer { queue.modelContext = oldContext; queue.isOnline = oldOnline; boundary.exits.continuation.finish() }
        boundary.hook = { event in
            if (mode == "reservationUnknown" && event == "reserve") || (mode == "uploadUnknown" && event == "upload") ||
                (mode == "executionUnknown" && event == "analyze") { throw URLError(.timedOut) }
            if mode == "account" && event == "reserve" { boundary.current = false }
            if mode == "cancel" && event == "reserve" { queue.videoReservationOwner.cancel() }
            if mode == "consent" && event == "bind" { throw MerianError.aiConsentRequired }
        }
        let erasure = ObservationReanalysisErasureOwner(files: .init(documents: seed.root))
        func start() -> ObservationVideoReservationOwner.Admission {
            queue.requestVideoSourceSubmission(boundary.key, proof: proof, account: boundary.account,
                submission: boundary.submission, execution: boundary.execution, erasure: erasure,
                isCurrentAccount: boundary.valid, didChange: {})
        }
        #expect(start() == .started)
        #expect(start() == .coalesced)
        let leases = ["complete", "executionUnknown"].contains(mode) ? 3 : ["uploadUnknown", "consent"].contains(mode) ? 2 : 1
        await boundary.drain(leases)
        #expect(boundary.events.filter { $0 == "reserve" }.count == 1)
        #expect(boundary.events.filter { $0 == "analyze" }.count == (leases == 3 ? 1 : 0))
        let context = ModelContext(seed.container)
        #expect(try context.fetch(FetchDescriptor<LocalAnalysisRecord>()).count == (mode == "complete" ? 2 : 1))
        if mode == "complete" {
            #expect(boundary.events == ["reserve"] + Array(repeating: "upload", count: seed.preparation.files.count) + ["bind", "authorize", "analyze", "outcome"])
        } else if leases == 1 {
            let held = try Reservation.read(proof: proof, container: seed.container, isCurrent: { true })
            #expect(held.work.phase == (mode == "reservationUnknown" ? .unknown : mode == "account" ? .running : .observed))
        } else if leases == 2 {
            let held = try Upload.read(proof: proof, container: seed.container, isCurrent: { true })
            #expect(mode == "consent" ? held.work.receipt?.state == .ready : held.work.attempts.last?.phase == .unknown)
            if mode == "consent" {
                let priorUploads = boundary.events.filter { $0 == "upload" }.count
                boundary.hook = { _ in }
                let uploadKey = ObservationVideoUploadOwner.Key(snapshot: held, session: boundary.key.session,
                    generation: 1, container: boundary.key.container)
                #expect(queue.requestVideoUploadSubmission(uploadKey, proof: proof, account: boundary.account,
                    submission: boundary.submission, execution: boundary.execution, erasure: erasure,
                    isCurrentAccount: boundary.valid, didChange: {}) == .unavailable)
                let bindingKey = ObservationVideoUploadOwner.Key(snapshot: held, session: boundary.key.session,
                    generation: 1, container: boundary.key.container, route: .bindReady)
                #expect(queue.requestVideoUploadSubmission(bindingKey, proof: proof, account: boundary.account,
                    submission: boundary.submission, execution: boundary.execution, erasure: erasure,
                    isCurrentAccount: boundary.valid, didChange: {}) == .started)
                var iterator = boundary.exits.stream.makeAsyncIterator()
                _ = await iterator.next(); _ = await iterator.next()
                await queue.videoUploadOwner.invalidateAndAwait(); await queue.videoExecutionOwner.invalidateAndAwait()
                #expect(boundary.events.filter { $0 == "upload" }.count == priorUploads)
                #expect(boundary.events.filter { $0 == "analyze" }.count == 1 && boundary.events.last == "outcome")
            }
        } else {
            let held = try Execution.read(proof: proof, container: seed.container, isCurrent: { true })
            #expect(held.work.consumed && held.work.phase == .held)
            #expect(!boundary.events.contains("outcome"))
            // Only a later explicit exact-outcome request may finish the same child.
            boundary.hook = { _ in }
            #expect(queue.requestVideoExecution(.init(snapshot: held, session: boundary.key.session, generation: 1,
                container: boundary.key.container), proof: proof, account: boundary.account, service: boundary.execution,
                erasure: erasure, isCurrentAccount: boundary.valid, didComplete: {}) == .started)
            var iterator = boundary.exits.stream.makeAsyncIterator(); _ = await iterator.next()
            await queue.videoExecutionOwner.invalidateAndAwait()
            #expect(boundary.events.filter { $0 == "analyze" }.count == 1 && boundary.events.last == "outcome")
            #expect(try ModelContext(seed.container).fetch(FetchDescriptor<LocalAnalysisRecord>()).count == 2)
        }
        // A stale initial snapshot never rearms the original reservation.
        boundary.current = true
        #expect(start() == .started)
        var iterator = boundary.exits.stream.makeAsyncIterator(); _ = await iterator.next()
        await queue.videoReservationOwner.invalidateAndAwait()
        #expect(boundary.events.filter { $0 == "reserve" }.count == 1)
    }

    @Test(arguments: [false, true], [false, true])
    func throwingHandoffSaveNeverAdvances(uploadStage: Bool, committed: Bool) async throws {
        let (seed, entry) = try await ObservationVideoReservationLifecycleTests().staged()
        defer { seed.remove() }
        let boundary = Boundary(seed, entry), queue = boundary.queue, proof = try seed.proof
        let oldContext = queue.modelContext, oldOnline = queue.isOnline
        queue.modelContext = ModelContext(seed.container); queue.isOnline = true
        defer { queue.modelContext = oldContext; queue.isOnline = oldOnline; boundary.exits.continuation.finish() }
        var submission = boundary.submission
        let save: (ModelContext) throws -> Void = { if committed { try $0.save() }; throw CocoaError(.fileWriteUnknown) }
        if uploadStage { submission.uploadStageSave = save } else { submission.executionStageSave = save }
        #expect(queue.requestVideoSourceSubmission(boundary.key, proof: proof, account: boundary.account,
            submission: submission, execution: boundary.execution,
            erasure: .init(files: .init(documents: seed.root)), isCurrentAccount: boundary.valid, didChange: {}) == .started)
        await boundary.drain(uploadStage ? 1 : 2)
        #expect(!boundary.events.contains("analyze") && !boundary.events.contains("authorize"))
        if uploadStage { #expect(boundary.events == ["reserve"]) }
        if !uploadStage && committed {
            #expect(try Execution.read(proof: proof, container: seed.container, isCurrent: { true }).work.phase == .idle)
        }
    }
}
