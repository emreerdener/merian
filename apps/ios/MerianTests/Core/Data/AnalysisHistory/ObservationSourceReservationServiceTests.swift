import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationSourceReservationServiceTests {
    typealias Owner = ObservationSourceReservationOwner
    typealias Store = ObservationSourceReservationStore
    typealias Service = ObservationSourceReservationService
    let fixture = ObservationSourceStoreTests()
    let owners = ObservationSourceReservationOwnerTests()

    func run(_ key: Owner.Key, seed: ObservationReanalysisRecoveryTests.Seed,
             owner: Owner, service: Service, isCurrent: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> Service.Outcome {
        let proof = try ObservationSourceReservationStore.Proof.photo(seed.pending.verified(source: seed.source))
        var leaseExited = false
        let account = owners.account(key) { leaseExited = true }
        return await withCheckedContinuation { continuation in
            var outcome = Service.Outcome.unavailable
            let result = owner.start(key, account: account, isCurrent: isCurrent, operation: { scope in
                outcome = await service.run(key.snapshot, admission: key.admission, proof: proof, container: seed.container, scope: scope)
            }, didFinish: {
                #expect(leaseExited && !owner.isRunning)
                continuation.resume(returning: outcome)
            })
            if result != .started { continuation.resume(returning: .unavailable) }
        }
    }

    @Test(arguments: ["reserved", "held", "unavailable"])
    func exactKnownObservationsSurviveDispatchCancellation(state: String) async throws {
        let seed = try fixture.fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let key = try await owners.key(seed), owner = Owner(), response = try fixture.reply(key.snapshot, state: state)
        let outcome = try await run(key, seed: seed, owner: owner, service: .init(reserve: { candidate, account, before, after in
            #expect(candidate == key.snapshot.work.request && account == key.session.userID)
            try before(); owner.cancel(); try after(); return response
        }))
        #expect(outcome == .observed)
        let saved = try Store.read(key.snapshot.identity, container: seed.container, isCurrent: { true })
        #expect(saved.work.reply?.data == response.data && saved.work.request == key.snapshot.work.request)
        #expect(saved.work.state == .observed && saved.work.generation == 1)
    }

    @Test func exactConflictSurvivesCancellationAndCannotRearm() async throws {
        let seed = try fixture.fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let key = try await owners.key(seed), owner = Owner()
        let outcome = try await run(key, seed: seed, owner: owner, service: .init(reserve: { request, account, before, after in
            try before(); owner.cancel(); try after()
            throw ObservationSourceReservationConflict(request: request, ownerID: account)
        }))
        #expect(outcome == .held)
        let saved = try Store.read(key.snapshot.identity, container: seed.container, isCurrent: { true })
        #expect(saved.work.state == .conflict && saved.work.generation == 1)
        #expect(saved.work.request == key.snapshot.work.request)
        let recovery = Owner.Key(snapshot: saved, admission: .explicitRecovery, session: key.session, generation: key.generation, container: key.container)
        let retried = try await run(recovery, seed: seed, owner: owner, service: .init(reserve: { _, _, _, _ in
            Issue.record("Conflict cannot rearm"); throw MerianError.invalidResponse
        }))
        #expect(retried == .unavailable)
    }

    @Test(arguments: ["auth", "claim", "deletion", "afterAuth"])
    func changedAuthorityCannotAcknowledgeOrDispatch(change: String) async throws {
        let seed = try fixture.fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let key = try await owners.key(seed), owner = Owner(), proof = try ObservationSourceReservationStore.Proof.photo(seed.pending.verified(source: seed.source))
        var current = true, dispatched = false
        let outcome = try await run(key, seed: seed, owner: owner, service: .init(reserve: { _, _, before, after in
            if change == "afterAuth" { current = false }
            try before(); dispatched = true
            if change == "auth" { owner.invalidate() }
            if change == "claim" {
                let running = try Store.read(key.snapshot.identity, container: seed.container, isCurrent: { true })
                _ = try Store.claim(running, admission: .explicitRecovery, proof: proof, container: seed.container, isCurrent: { true })
            }
            if change == "deletion" {
                let context = ModelContext(seed.container)
                context.insert(PendingCloudDeletionTask(scanId: key.snapshot.identity.observationID.uuidString.lowercased()))
                try context.save()
            }
            try after(); return try fixture.reply(key.snapshot)
        }), isCurrent: { current })
        #expect(outcome == .unavailable)
        #expect(dispatched == (change != "afterAuth"))
        if change != "deletion" {
            #expect(try Store.read(key.snapshot.identity, container: seed.container, isCurrent: { true }).work.reply == nil)
        }
        await owner.invalidateAndAwait()
    }

    @Test(arguments: [false, true])
    func failedClaimSaveNeverSendsEvenIfCommitted(committed: Bool) async throws {
        let seed = try fixture.fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let key = try await owners.key(seed)
        var service = Service(reserve: { _, _, _, _ in Issue.record("No persisted claim returned"); throw MerianError.invalidResponse })
        service.claimSave = { context in
            if committed { try context.save() }
            throw MerianError.invalidResponse
        }
        #expect(try await run(key, seed: seed, owner: Owner(), service: service) == .unavailable)
        let saved = try Store.read(key.snapshot.identity, container: seed.container, isCurrent: { true })
        #expect(saved.work.state == (committed ? .running : .staged))
        #expect(saved.work.request == key.snapshot.work.request)
    }

    @Test func uncertainReplyRequiresExplicitExactCandidateRecovery() async throws {
        let seed = try fixture.fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let key = try await owners.key(seed), owner = Owner()
        #expect(try await run(key, seed: seed, owner: owner, service: .init(reserve: { _, _, before, _ in
            try before(); throw MerianError.invalidResponse
        })) == .held)
        let held = try Store.read(key.snapshot.identity, container: seed.container, isCurrent: { true })
        #expect(held.work.state == .unknown)
        let recovery = Owner.Key(snapshot: held, admission: .explicitRecovery, session: key.session, generation: key.generation, container: key.container)
        let recovered = try await run(recovery, seed: seed, owner: owner, service: .init(reserve: { candidate, _, before, after in
            #expect(candidate == key.snapshot.work.request)
            try before(); try after(); return try fixture.reply(held)
        }))
        #expect(recovered == .observed)
        let observed = try Store.read(held.identity, container: seed.container, isCurrent: { true })
        #expect(observed.work.generation == 2 && observed.work.reply?.state == .reserved)
        let replay = Owner.Key(snapshot: observed, admission: .explicitRecovery, session: key.session, generation: key.generation, container: key.container)
        #expect(try await run(replay, seed: seed, owner: owner, service: .init(reserve: { _, _, _, _ in
            Issue.record("Reserved result cannot rearm"); throw MerianError.invalidResponse
        })) == .unavailable)
    }
}
