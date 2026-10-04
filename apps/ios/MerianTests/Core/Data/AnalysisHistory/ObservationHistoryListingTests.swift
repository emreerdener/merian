import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized)
struct ObservationHistoryListingTests {
    let support = ObservationHistorySyncTests()
    @Test func idleHistorySessionNeverBlocksAccountWorkDrain() async throws {
        let container = try support.container(), runtime = AuthRuntimeState()
        let identity = AuthTransitionSession(userID: support.owner, isAnonymous: false)
        var active = true, leases = 0
        var cloud = support.client(fetch: { _ in Data() })
        cloud.begin = { owner in
            #expect(owner == identity.userID); leases += 1
            return runtime.beginAccountWork(session: identity)
        }
        cloud.finish = { lease in leases -= 1; _ = runtime.finishAccountWork(lease) }
        cloud.isCurrent = { runtime.accountWorkLeaseIsCurrent($0, publishedSession: identity, sdkSession: identity) }
        let session = try IdentificationHistorySession(observation: support.observation, container: container,
            cloud: cloud, currentGeneration: { runtime.sessionGeneration }, sessionIsCurrent: { $0 == identity && active })
        try #require(leases == 0)
        await runtime.awaitAccountWorkDrain()
        #expect(session.isCurrent())
        active = false; #expect(!session.isCurrent())
        active = true; runtime.advanceSessionGeneration()
        #expect(!session.isCurrent())
        session.close(); #expect(leases == 0)
    }
    @Test func pageKeepsServerOrderingAndBoundedAvailabilityDoesNotSelect() async throws {
        let container = try support.container()
        var page = try support.fixture()
        let first = try #require((page["items"] as? [[String: Any]])?.first)
        let snapshot = try #require(first["snapshot"] as? String)
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(snapshot.utf8)) as? [String: Any])
        let id = UUID(); envelope["analysis_id"] = id.uuidString.lowercased(); envelope["ordinal"] = 2
        let bytes = try support.bytes(envelope)
        page["items"] = [["ordinal": 2, "snapshot": try #require(String(data: bytes, encoding: .utf8))], first]
        let response = try support.bytes(page)
        let cloud = support.client(fetch: { request in #expect(request.limit == 20); return response })
        let listing = ObservationHistoryListingService(cloud: cloud)
        #expect(try !listing.hasMultiple(observationID: support.observation, container: container))
        let single = support.client(fetch: { _ in try support.bytes(support.fixture()) })
        _ = try await ObservationHistorySyncService(cloud: single).syncPage(observationID: support.observation, container: container)
        #expect(try !listing.hasMultiple(observationID: support.observation, container: container))
        let result = try await listing.page(observationID: support.observation, container: container)
        #expect(result.entries.count == 2 && result.entries.first?.result.analysisID == id)
        #expect(try listing.hasMultiple(observationID: support.observation, container: container))
        #expect(result.context.revision == 10 && result.context.selected.uuidString.lowercased().hasSuffix("000009"))
        #expect(result.entries.allSatisfy { $0.authority == nil })
    }
    @Test func newerServerPageIsCachedButCannotClaimCurrentAuthority() async throws {
        let container = try support.container(); var page = try support.fixture(); page["state_revision"] = 11
        let cloud = support.client(fetch: { _ in try support.bytes(page) })
        await #expect(throws: ObservationHistoryPreviewService.AdmissionError.refreshRequired) {
            try await ObservationHistoryListingService(cloud: cloud).page(observationID: support.observation, container: container)
        }
        #expect(try support.count(container) == 1)
        #expect(try ObservationHistoryListingService(cloud: cloud).context(observationID: support.observation, container: container).revision == 10)
    }
    @Test func staleOrMissingAuthorityNeverBecomesConfirmationFromTheSelectedScan() async throws {
        let fixture = ObservationHistorySelectionIntentTests(), container = try await fixture.seeded()
        let cloud = fixture.support.support.support.client(fetch: { _ in Data() })
        let service = ObservationHistoryListingService(cloud: cloud)
        let entry = try service.cached(observationID: fixture.observation, analysisID: fixture.target, container: container)
        let row = try IdentificationHistoryPresentation.row(entry)
        #expect(row.review != "Confirmed species" && row.title != "Preserved correction")
        let context = try service.context(observationID: fixture.observation, container: container)
        #expect(try IdentificationHistoryPresentation.detail(entry, context: context, cached: true).canRestore)
    }

    @Test func opaqueLegacyCandidatesDoNotBlockSavedIdentificationPreview() async throws {
        let fixture = SavedIdentificationDisplayBaselineTests()
        let container = try fixture.container()
        _ = try await fixture.support.service(data: fixture.support.fixture(revision: 10))
            .syncSelected(observationID: fixture.support.support.observation, container: container)
        let cloud = fixture.support.support.client(fetch: { _ in Data() })
        let listing = ObservationHistoryListingService(cloud: cloud)
        let entry = try listing.cached(observationID: fixture.support.support.observation,
            analysisID: UUID(uuidString: fixture.support.analysisID)!, container: container)
        #expect(entry.display?.candidatesData == Data("{}".utf8))
        let context = ObservationHistoryListingService.Context(owner: fixture.support.support.owner,
            selected: UUID(), revision: 10, pendingOperation: nil, undoOperation: nil)
        let preview = try IdentificationHistoryPresentation.detail(entry, context: context, cached: true)
        #expect(preview.canRestore && preview.alternatives.isEmpty)
        #expect(preview.row.title == "Preserved correction")
    }
}
