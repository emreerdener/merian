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
    func container(enrolled: Bool = true, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
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

extension ObservationHistorySyncTests {
    func audioSnapshot() throws -> [String: Any] {
        let page = try fixture(), items = try #require(page["items"] as? [[String: Any]])
        var row = try #require(JSONSerialization.jsonObject(with: Data((items[0]["snapshot"] as! String).utf8)) as? [String: Any])
        row["schema_version"] = 4
        row["evidence_manifest"] = ["schema_version": 3, "items": [
            ["kind": "description", "text": "Before é"],
            ["kind": "audio", "media_id": "00000000-0000-4000-8000-000000000070", "content_type": "audio/wav",
             "byte_count": 46, "sha256": String(repeating: "b", count: 64)],
            ["kind": "description", "text": "After e\u{301}"]
        ]]
        return row
    }
    func audioPage(_ snapshot: [String: Any]) throws -> Data {
        var page = try fixture()
        page["items"] = [["ordinal": 1, "snapshot": try #require(String(bytes: bytes(snapshot), encoding: .utf8))]]
        return try bytes(page)
    }
    @Test func audioResultRetainsExactBytesWithSeparateReference() throws {
        let snapshot = try audioSnapshot(), data = try bytes(snapshot)
        let result = try ObservationHistoryPage.snapshot(data, observationID: observation, ordinal: 1)
        #expect(result.version == 4)
        #expect(result.bytes == data)
        #expect(result.photos.isEmpty)
        #expect(result.audio?.byteCount == 46)
        #expect(result.audio?.contentType == "audio/wav")
        #expect(result.audio?.sha256 == String(repeating: "b", count: 64))
        #expect(result.importedAt == nil)
        #expect(result.completedAt != nil)
    }
    @Test func audioResultRejectsMalformedOrAliasedEvidence() throws {
        let original = try audioSnapshot()
        let manifest = try #require(original["evidence_manifest"] as? [String: Any])
        let items = try #require(manifest["items"] as? [[String: Any]])
        for change: [String: Any] in [
            ["kind": "image"], ["content_type": "audio/mp4"], ["byte_count": true], ["byte_count": 45],
            ["byte_count": 2_700_001], ["sha256": String(repeating: "A", count: 64)],
            ["object_id": UUID().uuidString], ["media_id": observation], ["media_id": original["analysis_id"]!]
        ] {
            var row = original
            row["evidence_manifest"] = ["schema_version": 3, "items": [items[1].merging(change) { _, new in new }]]
            #expect(throws: (any Error).self) { try ObservationHistoryPage.snapshot(bytes(row), observationID: observation, ordinal: 1) }
        }
        for invalid: [String: Any] in [
            ["schema_version": 3, "items": []], ["schema_version": 3, "items": [items[0]]],
            ["schema_version": 3, "items": [items[1], items[1]]], ["schema_version": 2, "items": items],
            ["schema_version": 3, "items": items, "url": "https://example.invalid"]
        ] {
            var row = original; row["evidence_manifest"] = invalid
            #expect(throws: (any Error).self) { try ObservationHistoryPage.snapshot(bytes(row), observationID: observation, ordinal: 1) }
        }
        var alias = original; alias["source_analysis_id"] = items[1]["media_id"]
        #expect(try ObservationHistoryPage.snapshot(bytes(alias), observationID: observation, ordinal: 1).audio != nil)
        var imported = original; imported["schema_version"] = 3
        #expect(throws: (any Error).self) { try ObservationHistoryPage.snapshot(bytes(imported), observationID: observation, ordinal: 1) }
    }
    @Test func audioDescriptionBoundsPreserveUnicodeUnits() throws {
        var row = try audioSnapshot()
        let manifest = try #require(row["evidence_manifest"] as? [String: Any])
        let audio = try #require((manifest["items"] as? [[String: Any]])?[1])
        row["evidence_manifest"] = ["schema_version": 3, "items": [audio, ["kind": "description", "text": "\u{0085}"]]]
        #expect(try ObservationHistoryPage.snapshot(bytes(row), observationID: observation, ordinal: 1).audio != nil)
        let maximum = String(repeating: "😀", count: 8192)
        row["evidence_manifest"] = ["schema_version": 3, "items": [audio, ["kind": "description", "text": maximum]]]
        #expect(try ObservationHistoryPage.snapshot(bytes(row), observationID: observation, ordinal: 1).audio != nil)
        for texts in [[maximum + "a"], [maximum, maximum], ["\n\t"], ["\u{FEFF}"], [String(repeating: "a", count: 8193)]] {
            row["evidence_manifest"] = ["schema_version": 3, "items": [audio] + texts.map { ["kind": "description", "text": $0] }]
            #expect(throws: (any Error).self) { try ObservationHistoryPage.snapshot(bytes(row), observationID: observation, ordinal: 1) }
        }
    }
    @Test func audioAdmissionReplayPreservesSelectionAndCannotBecomeLegacySource() async throws {
        let container = try container(), data = try audioPage(audioSnapshot())
        let service = ObservationHistorySyncService(cloud: client(fetch: { _ in data }))
        _ = try await service.syncPage(observationID: observation, container: container)
        _ = try await service.syncPage(observationID: observation, container: container)
        let context = ModelContext(container), record = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        #expect(record.snapshotVersion == 4)
        #expect(try count(container) == 1)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(scan.selectedAnalysisID == "00000000-0000-4000-8000-000000000009")
        #expect(scan.userIdentificationOverride == "Existing correction")
        #expect(throws: ObservationHistoryError.unavailable) {
            try ObservationReanalysisSource.capture(observationID: UUID(uuidString: observation)!, analysisID: UUID(uuidString: record.id)!, ownerID: owner, container: container)
        }
        let loader = ObservationHistoryPhotoLoader(account: client(fetch: { _ in Data() }), resolve: { _ in
            Issue.record("Audio reached photo resolver"); throw ObservationHistoryError.unavailable
        }, download: { _ in Issue.record("Audio reached photo downloader"); return Data() })
        await #expect(throws: (any Error).self) {
            try await loader.load(observationID: observation, analysisID: UUID(uuidString: record.id)!,
                mediaID: UUID(uuidString: "00000000-0000-4000-8000-000000000070")!, container: container)
        }
    }
    @Test func audioSyncSurvivesDiskReopenWithExactListingBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("audio-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixture.store"), snapshot = try audioSnapshot(), data = try audioPage(snapshot)
        let analysis = try ObservationHistoryPage.uuid(snapshot["analysis_id"])
        do {
            let container = try container(url: url)
            let service = ObservationHistorySyncService(cloud: client(fetch: { _ in data }))
            _ = try await service.syncPage(observationID: observation, container: container)
        }
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(reopened), scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let entry = try ObservationHistoryListingService.entry(analysis, scan: scan, context: context)
        #expect(try entry.result.bytes == bytes(snapshot))
        #expect(entry.result.version == 4 && entry.result.audio != nil && entry.result.photos.isEmpty)
        #expect(scan.selectedAnalysisID == "00000000-0000-4000-8000-000000000009")
        #expect(scan.userIdentificationOverride == "Existing correction")
    }
    @Test func audioPreviewAllowsExplicitSelectionButNotChat() async throws {
        let fixture = ObservationHistorySelectionIntentTests()
        let container = try await fixture.support.seeded()
        var response = try #require(JSONSerialization.jsonObject(with: fixture.support.nativeResponse(revision: 10)) as? [String: Any])
        var item = try #require(response["analysis"] as? [String: Any]), snapshot = try audioSnapshot()
        snapshot["analysis_id"] = fixture.target.uuidString.lowercased(); snapshot["ordinal"] = 2
        item["snapshot"] = try #require(String(bytes: bytes(snapshot), encoding: .utf8)); response["analysis"] = item
        response["selected_analysis_id"] = fixture.support.support.analysisID
        var cloud = client(fetch: { _ in Data() })
        cloud.fetchState = { _ in try bytes(response) }
        _ = try await ObservationHistoryPreviewService(cloud: cloud).preview(observationID: observation, analysisID: fixture.target, container: container)
        let context = ModelContext(container), scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let entry = try ObservationHistoryListingService.entry(fixture.target, scan: scan, context: context)
        let listingContext = ObservationHistoryListingService.Context(owner: owner,
            selected: UUID(uuidString: fixture.support.support.analysisID)!, revision: 10, pendingOperation: nil, undoOperation: nil)
        let detail = try IdentificationHistoryPresentation.detail(entry, context: listingContext, cached: true)
        #expect(detail.canRestore && detail.restoreUnavailableReason == nil)
        #expect(throws: ObservationHistoryError.unavailable) {
            try ProtectedInsightChatTicket(entry: entry, context: .init(owner: owner, selected: fixture.target,
                revision: 10, pendingOperation: nil, undoOperation: nil), observationID: UUID(uuidString: observation)!)
        }
    }
    @Test func audioTargetStateDoesNotSubstituteSelectedIdentity() throws {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at: "services/supabase/functions/_shared/analysisHistory/fixtures/state-v1.json")
        var state = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        var item = try #require(state["analysis"] as? [String: Any]), snapshot = try audioSnapshot()
        let target = "00000000-0000-4000-8000-000000000071"
        snapshot["analysis_id"] = target
        item["snapshot"] = try #require(String(bytes: bytes(snapshot), encoding: .utf8)); state["analysis"] = item
        let decoded = try ObservationHistoryState.decode(bytes(state), request: .init(observation_id: observation, analysis_id: target), ownerID: owner)
        #expect(decoded.result.audio != nil)
        #expect(decoded.result.analysisID.uuidString.lowercased() == target)
        #expect(decoded.selectedAnalysisID.uuidString.lowercased() == "00000000-0000-4000-8000-000000000002")
        #expect(throws: (any Error).self) { try ObservationHistoryState.decode(bytes(state), request: .init(observation_id: observation, analysis_id: nil), ownerID: owner) }
    }
}

extension ObservationHistorySyncTests {
    func videoSnapshot() throws -> [String: Any] {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/video-result-v5.json")
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        var snapshot = try #require(fixture["base_snapshot"] as? [String: Any])
        let manifestsText = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/video-manifest-v4.json")
        let manifests = try #require(JSONSerialization.jsonObject(with: Data(manifestsText.utf8)) as? [[String: Any]])
        snapshot["evidence_manifest"] = manifests.first?["manifest"]
        return snapshot
    }

    @Test func videoResultSyncReplaysAndReopensWithoutChangingSelectionOrCorrection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("video-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixture.store"), snapshot = try videoSnapshot(), data = try audioPage(snapshot)
        let analysis = try ObservationHistoryPage.uuid(snapshot["analysis_id"])
        do {
            let container = try container(url: url)
            let service = ObservationHistorySyncService(cloud: client(fetch: { _ in data }))
            _ = try await service.syncPage(observationID: observation, container: container)
            _ = try await service.syncPage(observationID: observation, container: container)
            #expect(try count(container) == 1)
            var changed = snapshot; changed["completed_at_ms"] = 1750000000001 as Int64
            let conflict = ObservationHistorySyncService(cloud: client(fetch: { _ in try audioPage(changed) }))
            await #expect(throws: ObservationHistoryError.resultConflict) {
                try await conflict.syncPage(observationID: observation, container: container)
            }
        }
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(reopened), scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let entry = try ObservationHistoryListingService.entry(analysis, scan: scan, context: context)
        #expect(try entry.result.bytes == bytes(snapshot))
        #expect(entry.result.version == 5 && entry.result.video != nil && entry.result.audio == nil && entry.result.photos.isEmpty)
        #expect(scan.selectedAnalysisID == "00000000-0000-4000-8000-000000000009")
        #expect(scan.userIdentificationOverride == "Existing correction")
        #expect(throws: ObservationHistoryError.unavailable) {
            try ObservationReanalysisSource.capture(observationID: UUID(uuidString: observation)!, analysisID: analysis, ownerID: owner, container: reopened)
        }
        #expect(throws: ObservationHistoryError.unavailable) {
            try ObservationReanalysisSource.captureForAudio(observationID: UUID(uuidString: observation)!, analysisID: analysis, ownerID: owner, container: reopened)
        }
        #expect(throws: ObservationHistoryError.unavailable) {
            try ObservationReanalysisSource.captureForVideo(observationID: UUID(uuidString: observation)!, analysisID: analysis, ownerID: owner, container: reopened)
        }
    }
}
