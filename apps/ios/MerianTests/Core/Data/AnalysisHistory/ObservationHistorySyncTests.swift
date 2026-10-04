import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ObservationHistorySyncTests {
    let observation = "00000000-0000-4000-8000-000000000001"
    let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!

    func fixture() throws -> [String: Any] {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/page-v1.json")
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
    func bytes(_ page: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: page, options: [.sortedKeys]) }
    func container(enrolled: Bool = true) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let scan = LocalScanRecord(id: observation.uppercased(), speciesId: "fixture", scientificName: "Preserved correction", commonName: "Preserved correction")
        scan.userIdentificationOverride = "Existing correction"
        scan.userConfirmedIdentification = true
        scan.aiIdentificationReviewData = Data("synthetic review bytes".utf8)
        if enrolled {
            scan.analysisOwnerAccountID = owner.uuidString.lowercased()
            scan.observationStateRevision = 10
            scan.selectedAnalysisID = "00000000-0000-4000-8000-000000000009"
        }
        context.insert(scan)
        try context.save()
        return container
    }
    func client(fetch: @escaping (ObservationHistoryPageRequest) async throws -> Data,
                current: @escaping () -> Bool = { true }, finish: @escaping () -> Void = {}) -> ObservationHistoryCloudClient {
        .init(begin: { expected in
            #expect(expected == owner)
            return AccountBoundWorkLease(id: UUID(), session: AuthTransitionSession(userID: owner, isAnonymous: false))
        }, isCurrent: { _ in current() }, finish: { _ in finish() }, fetch: fetch)
    }
    func count(_ container: ModelContainer) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<LocalAnalysisRecord>())
    }

    @Test func sharedContractFixtureStoresExactBytesAndReplayPreservesCorrection() async throws {
        let container = try container(), fixture = try fixture(), data = try bytes(fixture)
        let service = ObservationHistorySyncService(cloud: client(fetch: { request in
            #expect(request.observation_id == observation)
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
            #expect(encoded?["before_ordinal"] is NSNull)
            return data
        }))
        #expect(try await service.syncPage(observationID: observation, container: container).insertedCount == 1)
        #expect(try await service.syncPage(observationID: observation, container: container).insertedCount == 0)
        let context = ModelContext(container)
        let child = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        let text = try #require((fixture["items"] as? [[String: Any]])?.first?["snapshot"] as? String)
        #expect(child.resultSnapshotData == Data(text.utf8))
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(child.observationID == scan.id)
        #expect(scan.analysisRecords?.count == 1)
        #expect(scan.scientificName == "Preserved correction")
        #expect(scan.userIdentificationOverride == "Existing correction")
        #expect(scan.userConfirmedIdentification)
        #expect(scan.aiIdentificationReviewData == Data("synthetic review bytes".utf8))
        #expect(scan.selectedAnalysisID == "00000000-0000-4000-8000-000000000009")
        #expect(scan.observationStateRevision == 10)
        context.delete(scan); try context.save()
        #expect(try count(container) == 0)
    }

    @Test func migrationDefaultsCannotEnrollThroughCurrentLogin() async throws {
        let container = try container(enrolled: false)
        var fetched = false
        let service = ObservationHistorySyncService(cloud: client(fetch: { _ in fetched = true; return Data() }))
        await #expect(throws: ObservationHistoryError.unavailable) {
            try await service.syncPage(observationID: observation, container: container)
        }
        #expect(!fetched)
        #expect(try count(container) == 0)
    }

    @Test func accountGenerationChangeDuringFetchDiscardsResponseAndFinishesLease() async throws {
        let container = try container(), data = try bytes(fixture())
        var current = true, finished = false
        let service = ObservationHistorySyncService(cloud: client(fetch: { _ in current = false; return data },
            current: { current }, finish: { finished = true }))
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await service.syncPage(observationID: observation, container: container)
        }
        #expect(finished)
        #expect(try count(container) == 0)
    }

    @Test func backgroundDeletionDuringFetchWinsWithoutResurrection() async throws {
        let container = try container(), data = try bytes(fixture())
        let setup = ModelContext(container)
        let scan = try #require(setup.fetch(FetchDescriptor<LocalScanRecord>()).first)
        scan.isBiological = false; try setup.save()
        let service = ObservationHistorySyncService(cloud: client(fetch: { _ in
            let actor = BackgroundDatabaseActor(modelContainer: container)
            _ = try await actor.bulkDeleteNonBiologicalScans(payloads: [.init(id: observation.uppercased(), mediaPaths: [])], requestingAccountID: owner)
            return data
        }))
        await #expect(throws: ObservationHistoryError.deleted) {
            try await service.syncPage(observationID: observation, container: container)
        }
        #expect(try count(container) == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
    }

    @Test func pendingDeletionBlocksAdmissionEvenWhileParentSurvives() async throws {
        let container = try container(), data = try bytes(fixture())
        let service = ObservationHistorySyncService(cloud: client(fetch: { _ in
            let context = ModelContext(container)
            try context.ensurePendingCloudDeletionTask(scanId: observation, requestingAccountID: owner, origin: .explicitUserDeletion)
            try context.save()
            return data
        }))
        await #expect(throws: ObservationHistoryError.deleted) {
            try await service.syncPage(observationID: observation, container: container)
        }
        #expect(try count(container) == 0)
    }

    @Test func conflictingReplayRollsBackEntirePageIncludingEarlierNewResult() async throws {
        let container = try container(), original = try fixture()
        let data = try bytes(original)
        let service = ObservationHistorySyncService(cloud: client(fetch: { _ in data }))
        _ = try await service.syncPage(observationID: observation, container: container)
        var page = original
        let originalItem = try #require((page["items"] as? [[String: Any]])?.first)
        var snapshot = try #require(JSONSerialization.jsonObject(with: Data((originalItem["snapshot"] as! String).utf8)) as? [String: Any])
        snapshot["ordinal"] = 2
        snapshot["analysis_id"] = "00000000-0000-4000-8000-000000000004"
        let newItem: [String: Any] = ["ordinal": 2, "snapshot": String(decoding: try bytes(snapshot), as: UTF8.self)]
        var conflict = originalItem
        conflict["snapshot"] = (originalItem["snapshot"] as! String) + " "
        page["items"] = [newItem, conflict]
        let conflictingData = try bytes(page)
        let conflictingService = ObservationHistorySyncService(cloud: client(fetch: { _ in conflictingData }))
        await #expect(throws: ObservationHistoryError.resultConflict) {
            try await conflictingService.syncPage(observationID: observation, container: container)
        }
        #expect(try count(container) == 1)
        #expect(try ModelContext(container).fetch(FetchDescriptor<LocalAnalysisRecord>()).first?.resultSnapshotData == Data((originalItem["snapshot"] as! String).utf8))
    }

    @Test func malformedPagesFailBeforePersistence() throws {
        let base = try fixture()
        let request = ObservationHistoryPageRequest(observation_id: observation, before_ordinal: nil, limit: 20)
        for patch: [String: Any] in [
            ["owner_id": observation], ["schema_version": 2], ["state_revision": true],
            ["next_before_ordinal": 2], ["items": Array(repeating: (base["items"] as! [Any])[0], count: 21)]
        ] {
            var page = base; page.merge(patch) { _, new in new }
            #expect(throws: (any Error).self) { try ObservationHistoryPage.decode(bytes(page), request: request, ownerID: owner) }
        }
        #expect(throws: (any Error).self) {
            try ObservationHistoryPage.decode(Data(repeating: 32, count: ObservationHistoryPage.maximumPageBytes + 1), request: request, ownerID: owner)
        }
        let item = try #require((base["items"] as? [[String: Any]])?.first)
        let snapshot = try #require(JSONSerialization.jsonObject(with: Data((item["snapshot"] as! String).utf8)) as? [String: Any])
        for patch: [String: Any] in [
            ["ordinal": 2], ["source_analysis_id": snapshot["analysis_id"]!], ["completed_at_ms": true],
            ["source_analysis_id": snapshot["observation_id"]!], ["analysis_id": snapshot["observation_id"]!],
            ["completed_at_ms": -1], ["result": [:]], ["result": NSNull()],
            ["evidence_manifest": ["schema_version": 1, "captured_media": []]],
            ["evidence_manifest": ["schema_version": 1, "captured_media": [["image": ["_0": ["storage": "localFile", "path": "fixture.jpg"]]]]]]
        ] {
            var invalid = snapshot; invalid.merge(patch) { _, new in new }
            var page = base
            page["items"] = [["ordinal": 1, "snapshot": String(decoding: try bytes(invalid), as: UTF8.self)]]
            #expect(throws: (any Error).self) { try ObservationHistoryPage.decode(bytes(page), request: request, ownerID: owner) }
        }
    }

    @Test func finalLeaseCheckRollsBackStagedChildren() async throws {
        let container = try container(), data = try bytes(fixture())
        var checks = 0
        let service = ObservationHistorySyncService(cloud: client(fetch: { _ in data }, current: {
            checks += 1
            return checks < 4
        }))
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await service.syncPage(observationID: observation, container: container)
        }
        #expect(checks == 4)
        #expect(try count(container) == 0)
    }

    @Test func enrolledNonbiologicalHistoryIsExemptFromAutomaticExpiry() async throws {
        let container = try container(), context = ModelContext(container)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        scan.isBiological = false; scan.timestamp = Date(timeIntervalSince1970: 1); try context.save()
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let result = try await actor.purgeExpiredNonBiologicalScans(cutoffDate: Date(), requestingAccountID: owner)
        #expect(result.deletedRecordCount == 0)
        #expect(result.committedErasureCount == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
    }
}
