import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized)
struct IdentificationHistoryPublicationAccessTests {
    let fixture = ObservationPublicationConsentServiceTests()

    @Test(arguments: ["found", "absent", "failed", "wrongObservation"])
    func heldLocalLoserAndRemoteWinnerRemainIndependent(_ outcome: String) async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let consent = fixture.service(snapshot), prepared = try await fixture.prepare(consent, container)
        let accepted = try prepared.accepting(mediaIDs: [fixture.secondPhoto])
        let intent = try consent.stage(accepted, container: container, isCurrent: { true })
        let claim = try #require(try ObservationPublicationPersistence.claim(intent, at: Date(), container: container, isCurrent: { true }))
        try ObservationPublicationPersistence.retry(claim, at: Date(), needsAttention: true, container: container, isCurrent: { true })
        let context = ModelContext(container), job = try #require(try context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.lastHTTPStatus = 409; try context.save()
        let metadata = job.metadataJSON, remote = try receipt(observation: outcome == "wrongObservation" ? UUID() : fixture.observation)
        #expect(remote.operationID != intent.identity.operationID && remote.analysisID != ticket.analysisID)
        let config = IdentificationHistoryPublicationAccess.Configuration(owner: .init(), recoveryOwner: .init(), fetchTarget: { request, owner in
            #expect(request.observationID == fixture.observation && owner == fixture.owner)
            if outcome == "failed" { throw ObservationHistoryError.unavailable }
            return outcome == "absent" ? nil : remote
        }, fetch: { _, _ in Issue.record("Recovery cannot preflight consent"); return snapshot },
            wake: { Issue.record("Recovery cannot wake delivery") }, generation: { 0 })
        let scope = try IdentificationHistorySession(observation: fixture.observation.uuidString, container: container,
            cloud: consent.cloud, publication: config, currentGeneration: { 1 }, sessionIsCurrent: { _ in true })
        defer { scope.close() }
        let access = try #require(scope.dependencies.publicationConsent)
        if outcome == "wrongObservation" {
            await #expect(throws: MerianError.invalidResponse) { try await access.recoverTarget(ticket) }
        } else if outcome == "failed" {
            await #expect(throws: ObservationHistoryError.unavailable) { try await access.recoverTarget(ticket) }
        } else {
            let result = try await access.recoverTarget(ticket)
            #expect(result.local?.operationID == intent.identity.operationID && result.local?.phase == .needsAttention)
            #expect(result.remote == (outcome == "found" ? .found(remote) : .absent))
        }
        let fresh = ModelContext(container), saved = try #require(try fresh.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        #expect(saved.metadataJSON == metadata && saved.status == .needsAttention && saved.lastHTTPStatus == 409)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }

    @Test(arguments: [false, true], ["deletion", "owner", "enrollment", "metadata"])
    func localScopeFailuresBeforeOrAfterReadNeverLookVacant(afterFetch: Bool, mutation: String) async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let consent = fixture.service(snapshot), prepared = try await fixture.prepare(consent, container)
        _ = try consent.stage(prepared.accepting(mediaIDs: [fixture.secondPhoto]), container: container, isCurrent: { true })
        func damage() throws {
            let context = ModelContext(container), scan = try #require(try context.fetch(FetchDescriptor<LocalScanRecord>()).first)
            switch mutation {
            case "deletion": context.delete(scan)
            case "owner": scan.analysisOwnerAccountID = UUID().uuidString.lowercased()
            case "enrollment": _ = try ObservationHistoryEnrollmentIntent.stage(observationID: fixture.observation, ownerID: fixture.owner, context: context)
            default: try #require(try context.fetch(FetchDescriptor<OfflineJobRecord>()).first).metadataJSON = "damaged"
            }
            try context.save()
        }
        var calls = 0, begins = 0, finishes = 0, cloud = consent.cloud
        let begin = cloud.begin
        cloud.begin = { expected in
            guard expected == fixture.owner else { throw ObservationHistoryError.accountChanged }
            let lease = try begin(expected); begins += 1; return lease
        }
        cloud.finish = { _ in finishes += 1 }
        let config = IdentificationHistoryPublicationAccess.Configuration(owner: .init(), recoveryOwner: .init(), fetchTarget: { _, _ in
            calls += 1
            if afterFetch { try damage() }
            return nil
        }, fetch: { _, _ in snapshot }, wake: { Issue.record("No recovery writes") }, generation: { 0 })
        let scope = try IdentificationHistorySession(observation: fixture.observation.uuidString, container: container,
            cloud: cloud, publication: config, currentGeneration: { 1 }, sessionIsCurrent: { _ in true })
        defer { scope.close() }
        let access = try #require(scope.dependencies.publicationConsent)
        if !afterFetch { try damage() }
        await #expect(throws: (any Error).self) { try await access.recoverTarget(ticket) }
        #expect(calls == (afterFetch ? 1 : 0) && finishes == begins)
    }

    @Test func closingOneRecoveryWaiterDoesNotPoisonAnotherPresentation() async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let owner = ObservationPublicationRecoveryOwner(), entered = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?, calls = 0
        defer { release?.resume(); entered.continuation.finish(); owner.cancelAll() }
        let config = IdentificationHistoryPublicationAccess.Configuration(owner: .init(), recoveryOwner: owner, fetchTarget: { _, _ in
            calls += 1; await withCheckedContinuation { release = $0; entered.continuation.yield() }; return nil
        }, fetch: { _, _ in snapshot }, wake: { Issue.record("No recovery writes") }, generation: { 0 })
        func session() throws -> IdentificationHistorySession {
            try .init(observation: fixture.observation.uuidString, container: container, cloud: fixture.service(snapshot).cloud,
                publication: config, currentGeneration: { 1 }, sessionIsCurrent: { _ in true })
        }
        let first = try session(), second = try session()
        defer { first.close(); second.close() }
        let a = try #require(first.dependencies.publicationConsent), b = try #require(second.dependencies.publicationConsent)
        let firstTask = Task { try await a.recoverTarget(ticket) }
        for await _ in entered.stream { break }
        let joined = AsyncStream<Void>.makeStream(); defer { joined.continuation.finish() }
        let secondTask = Task { joined.continuation.yield(); return try await b.recoverTarget(ticket) }
        for await _ in joined.stream { break }
        first.close(); let continuation = release; release = nil; continuation?.resume()
        await #expect(throws: ObservationHistoryError.accountChanged) { try await firstTask.value }
        #expect(try await secondTask.value.remote == .absent)
        #expect(calls == 1 && owner.activeCount == 0)
    }

    private func receipt(observation: UUID) throws -> ObservationPublicationReceipt {
        let identity = ObservationPublicationStatusRequest(operationID: UUID(), observationID: observation, analysisID: UUID())
        let row: [String: Any] = ["schema_version": 1, "operation_id": identity.operationID.uuidString.lowercased(),
            "observation_id": observation.uuidString.lowercased(), "analysis_id": identity.analysisID.uuidString.lowercased(), "status": "processing"]
        return try .decodeStatus(JSONSerialization.data(withJSONObject: row), request: identity)
    }

    @Test func inertCompositionInjectsExactConsentAndSavedStatus() async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let owner = ObservationPublicationPreparationOwner()
        var fetches = 0, wakes = 0, epoch: UInt64 = 4
        let cloud = fixture.service(snapshot).cloud
        let bundle = PreparedHistoryReanalysisComposition(routes: AppDIContainer.preview.appRouteCoordinator, cloud: cloud,
            currentOwner: { fixture.owner }, generation: { 1 }, sessionIsCurrent: { $0.userID == fixture.owner },
            preparationOwner: ObservationReanalysisPreparationOwner(), enrollmentOwner: ObservationHistoryEnrollmentOwner(),
            containerIsCurrent: { $0 === container }, submitted: { _ in }, cleanup: {},
            publication: .init(owner: owner, recoveryOwner: ObservationPublicationRecoveryOwner(), fetchTarget: { _, _ in nil }, fetch: { request, expected in
                fetches += 1
                #expect(expected == fixture.owner && request.observationID == fixture.observation && request.analysisID == fixture.analysis)
                return snapshot
            }, wake: {
                wakes += 1
                #expect((try? ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>())) == 1)
            }, generation: { epoch }))
        #expect(fetches == 0 && owner.activeCount == 0)
        let dependencies = try bundle.history.open(fixture.observation.uuidString, container)
        defer { dependencies.close() }
        let access = try #require(dependencies.publicationConsent)
        #expect(fetches == 0 && access.generation() == 4)
        let prepared = try await access.prepare(ticket)
        #expect(fetches == 1 && owner.activeCount == 0 && wakes == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        let acceptance = try prepared.accepting(mediaIDs: [fixture.secondPhoto])
        #expect(try access.status(ticket, acceptance.request.operationID) == nil)
        try access.stage(acceptance)
        let status = try #require(try access.status(ticket, acceptance.request.operationID))
        #expect(status.phase == .pending && status.analysisID == fixture.analysis && wakes == 1)
        epoch = 5; #expect(access.generation() == 5)
        dependencies.close()
        #expect(throws: ObservationHistoryError.accountChanged) { try access.stage(acceptance) }
        #expect(throws: ObservationHistoryError.accountChanged) { try access.status(ticket, acceptance.request.operationID) }
    }

    @Test func closingOneSessionDoesNotPoisonJoinedPresentation() async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let owner = ObservationPublicationPreparationOwner(), entered = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?, fetches = 0
        defer { release?.resume(); entered.continuation.finish(); owner.cancelAll() }
        let config = IdentificationHistoryPublicationAccess.Configuration(owner: owner, recoveryOwner: ObservationPublicationRecoveryOwner(), fetchTarget: { _, _ in nil }, fetch: { _, _ in
            fetches += 1
            await withCheckedContinuation { release = $0; entered.continuation.yield() }
            return snapshot
        }, wake: {}, generation: { 0 })
        func session() throws -> IdentificationHistorySession {
            try .init(observation: fixture.observation.uuidString, container: container, cloud: fixture.service(snapshot).cloud,
                publication: config, currentGeneration: { 1 }, sessionIsCurrent: { $0.userID == fixture.owner })
        }
        let first = try session(), second = try session()
        defer { first.close(); second.close() }
        let firstAccess = try #require(first.dependencies.publicationConsent), secondAccess = try #require(second.dependencies.publicationConsent)
        let firstTask = Task { try await firstAccess.prepare(ticket) }
        for await _ in entered.stream { break }
        let joined = AsyncStream<Void>.makeStream(); defer { joined.continuation.finish() }
        let secondTask = Task { joined.continuation.yield(); return try await secondAccess.prepare(ticket) }
        for await _ in joined.stream { break }
        first.close()
        let continuation = release; release = nil; continuation?.resume()
        await #expect(throws: ObservationHistoryError.accountChanged) { try await firstTask.value }
        #expect(try await secondTask.value.ownerID == fixture.owner)
        #expect(fetches == 1 && owner.activeCount == 0)
    }

    @Test func commonAccountLossWithholdsConsentAndOrdinarySessionHasNoAccess() async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let owner = ObservationPublicationPreparationOwner()
        var current = true
        let config = IdentificationHistoryPublicationAccess.Configuration(owner: owner, recoveryOwner: ObservationPublicationRecoveryOwner(), fetchTarget: { _, _ in nil }, fetch: { _, _ in
            current = false; return snapshot
        }, wake: { Issue.record("Preparation must not wake delivery") }, generation: { 0 })
        let cloud = fixture.service(snapshot).cloud
        let ordinary = try IdentificationHistorySession(observation: fixture.observation.uuidString, container: container,
            cloud: cloud, currentGeneration: { 1 }, sessionIsCurrent: { _ in true })
        defer { ordinary.close() }
        #expect(ordinary.dependencies.publicationConsent == nil)
        let scope = try IdentificationHistorySession(observation: fixture.observation.uuidString, container: container,
            cloud: cloud, publication: config, currentGeneration: { 1 }, sessionIsCurrent: { _ in current })
        defer { scope.close() }
        let access = try #require(scope.dependencies.publicationConsent)
        await #expect(throws: ObservationHistoryError.accountChanged) { try await access.prepare(ticket) }
        #expect(owner.activeCount == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }
}
