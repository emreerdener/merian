import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized)
struct IdentificationHistoryPublicationAccessTests {
    let fixture = ObservationPublicationConsentServiceTests()

    @Test func inertCompositionInjectsExactConsentAndSavedStatus() async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let owner = ObservationPublicationPreparationOwner()
        var fetches = 0, wakes = 0, epoch: UInt64 = 4
        let cloud = fixture.service(snapshot).cloud
        let bundle = PreparedHistoryReanalysisComposition(routes: AppDIContainer.preview.appRouteCoordinator, cloud: cloud,
            currentOwner: { fixture.owner }, generation: { 1 }, sessionIsCurrent: { $0.userID == fixture.owner },
            preparationOwner: ObservationReanalysisPreparationOwner(), enrollmentOwner: ObservationHistoryEnrollmentOwner(),
            containerIsCurrent: { $0 === container }, submitted: { _ in }, cleanup: {},
            publication: .init(owner: owner, fetch: { request, expected in
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
        let config = IdentificationHistoryPublicationAccess.Configuration(owner: owner, fetch: { _, _ in
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
        let config = IdentificationHistoryPublicationAccess.Configuration(owner: owner, fetch: { _, _ in
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
