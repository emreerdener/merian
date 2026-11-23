import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationCompositionExecutionTests {
    typealias Seed = ObservationCompositionPreparationTests.Seed
    typealias Reservation = CompositionSourceReservationStore
    typealias Upload = CompositionUploadLifecycleStore
    typealias Execution = ObservationCompositionExecutionStore
    var authorization: IdentificationDispatchAuthorization { .init(recipient: .gemini, validate: {}) }

    func staged() async throws -> (Seed, Reservation.Snapshot) {
        let helper = ObservationCompositionPreparationTests(), seed = try helper.seed()
        _ = try await helper.producer(seed).prepare(seed.preparation, source: seed.source, payload: seed.payload,
            container: seed.container, isCurrent: { true })
        return (seed, try Reservation.stage(.init(composition: seed.preparation.request), proof: seed.proof,
            container: seed.container, isCurrent: { true }))
    }
    func reservedReply(_ snapshot: Reservation.Snapshot) throws -> CompositionSourceReservationReply {
        var fields = snapshot.work.request.identity.fields
        fields["owner_id"] = snapshot.work.preparation.identity.ownerID.uuidString.lowercased()
        fields["state"] = "reserved"
        return try .init(data: JSONSerialization.data(withJSONObject: fields), identity: snapshot.work.request.identity,
            ownerID: snapshot.work.preparation.identity.ownerID)
    }
    func uploaded() async throws -> (Seed, Upload.Snapshot) {
        let (seed, staged) = try await staged()
        let claim = try Reservation.claim(staged, proof: seed.proof, container: seed.container, isCurrent: { true })
        let reserved = try Reservation.settle(claim, settlement: .reply(reservedReply(staged)), proof: seed.proof,
            container: seed.container, isCurrent: { true })
        _ = try ObservationCompositionUploadStore.stage(reserved, proof: seed.proof, container: seed.container, isCurrent: { true })
        var upload = try Upload.read(proof: seed.proof, container: seed.container, isCurrent: { true })
        for _ in seed.preparation.files {
            let claim = try Upload.claim(upload, proof: seed.proof, container: seed.container, isCurrent: { true })
            upload = try Upload.settle(claim, receipt: receipt(claim), proof: seed.proof, container: seed.container, isCurrent: { true })
        }
        return (seed, upload)
    }
    func receipt(_ claim: Upload.Claim) throws -> ObservationCompositionEvidenceReceipt {
        let work = claim.snapshot.work, request = work.staged.request
        var row = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        var items = try #require(row["items"] as? [[String: Any]])
        let target = try #require(work.attempts.last).mediaID
        for index in items.indices {
            let previous = work.receipt?.items[index]
            items[index]["object_id"] = (previous?.objectID ?? UUID()).uuidString.lowercased()
            items[index]["ready_at"] = previous?.readyAt.map { $0 as Any }
                ?? (request.inventory.items[index].artifact.mediaID == target ? "2026-11-14T01:00:00.000Z" as Any : NSNull())
        }
        row["items"] = items
        row["owner_id"] = work.staged.reservation.preparation.identity.ownerID.uuidString.lowercased()
        row["expires_at"] = "2099-11-14T01:00:00.000Z"
        row["state"] = items.allSatisfy { $0["ready_at"] is String } ? "ready" : "allocated"
        return try .init(data: JSONSerialization.data(withJSONObject: row), request: request,
            ownerID: work.staged.reservation.preparation.identity.ownerID, previous: work.receipt)
    }

    @Test func unknownReservationNeverReclaimsButKnownReplySettlesAfterCancellation() async throws {
        let (seed, saved) = try await staged(); defer { seed.removeFiles() }
        let claim = try Reservation.claim(saved, proof: seed.proof, container: seed.container, isCurrent: { true })
        let held = try Reservation.hold(claim, proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Reservation.claim(held, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        let reply = try reservedReply(saved)
        let proof = try seed.proof
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try Reservation.settle(claim, settlement: .reply(reply), proof: proof, container: seed.container, isCurrent: { true })
        }
        let settled = try await task.value
        #expect(settled.work.reply?.data == reply.data)
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.database, seed: false)
        #expect(try Reservation.read(proof: proof, container: reopened, isCurrent: { true }).work == settled.work)
        #expect(throws: (any Error).self) { try Reservation.settle(claim, settlement: .reply(reply), proof: proof, container: reopened, isCurrent: { false }) }
    }

    @Test func orderedUploadsBindOneImmutableExecutionAndRestartCannotRearm() async throws {
        let (seed, uploaded) = try await uploaded(); defer { seed.removeFiles() }
        #expect(uploaded.work.receipt?.state == .ready)
        #expect(uploaded.work.attempts.count == 2)
        #expect(uploaded.work.staged.request.inventory.items.map(\.nodeIndex) == [0, 2])
        let saved = try Execution.stage(uploaded, proof: seed.proof, authorization: authorization, container: seed.container, isCurrent: { true })
        let claim = try Execution.claim(saved, proof: seed.proof, container: seed.container, isCurrent: { true })
        let permit = try Execution.consume(claim, proof: seed.proof, authorization: authorization, container: seed.container, isCurrent: { true })
        let held = try Execution.hold(permit.snapshot, proof: seed.proof, container: seed.container, isCurrent: { true })
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.database, seed: false)
        let recovered = try await ObservationCompositionResumeStore().read(seed.preparation.identity, container: reopened, isCurrent: { true })
        guard case let .execution(execution) = recovered.state else { Issue.record("Lost consumed execution"); return }
        #expect(execution.work == held.work && execution.work.consumed)
        #expect(throws: (any Error).self) { try Execution.claim(execution, proof: seed.proof, container: reopened, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try Execution.consume(claim, proof: seed.proof, authorization: authorization, container: reopened, isCurrent: { true }) }
        // A snapshot belongs to its original container; restart uses the durable
        // execution reader above rather than replaying an upload capability.
        #expect(throws: (any Error).self) {
            try Execution.stage(uploaded, proof: seed.proof, authorization: authorization, container: reopened, isCurrent: { true })
        }
        #expect(try Execution.stage(uploaded, proof: seed.proof, authorization: .init(recipient: .recoveryOnly, validate: { Issue.record("Reauthorized") }), container: seed.container, isCurrent: { true }).work == held.work)
    }

    @Test(arguments: [false, true]) func uncertainConsumeRetainsOriginalAttempt(commits: Bool) async throws {
        let (seed, uploaded) = try await uploaded(); defer { seed.removeFiles() }
        let saved = try Execution.stage(uploaded, proof: seed.proof, authorization: authorization, container: seed.container, isCurrent: { true })
        let claim = try Execution.claim(saved, proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) {
            try Execution.consume(claim, proof: seed.proof, authorization: authorization, container: seed.container, isCurrent: { true }, save: {
                if commits { try $0.save() }
                throw CocoaError(.fileWriteUnknown)
            })
        }
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.database, seed: false)
        let work = try Execution.read(proof: seed.proof, container: reopened, isCurrent: { true }).work
        #expect(work.consumed == commits && work.attemptID == claim.snapshot.work.attemptID)
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
    }
}
