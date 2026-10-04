import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationPublicationPersistenceTests {
    let owner = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let observation = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
    let analysis = UUID(uuidString: "10000000-0000-4000-8000-000000000003")!
    let operation = UUID(uuidString: "10000000-0000-4000-8000-000000000004")!
    let now = Date(timeIntervalSince1970: 1_780_000_000)

    func request(note: String? = "Private synthetic note") throws -> ObservationPublicationRequest {
        try .init(operationID: operation, observationID: observation, analysisID: analysis,
                  expectedObservationRevision: 3, expectedReviewRevision: 1,
                  taxonomyVersionID: UUID(uuidString: "10000000-0000-4000-8000-000000000005")!, initialTaxonID: nil,
                  note: note, mediaIDs: [UUID(uuidString: "10000000-0000-4000-8000-000000000006")!,
                                      UUID(uuidString: "10000000-0000-4000-8000-000000000007")!])
    }

    func container(url: URL? = nil, seed: Bool = true) throws -> ModelContainer {
        let schema = Schema(CurrentSchema.models)
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        if seed {
            let context = ModelContext(container)
            let scan = LocalScanRecord(id: observation.uuidString, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
            scan.analysisOwnerAccountID = owner.uuidString.lowercased(); scan.analysisSelectionInitialized = true
            scan.selectedAnalysisID = analysis.uuidString.lowercased(); scan.observationStateRevision = 3
            scan.isBiological = false
            context.insert(scan)
            let child = try LocalAnalysisRecord(analysisID: analysis, observationID: scan.id, ownerAccountID: owner,
                completedAt: now, resultSnapshotData: Data("{\"synthetic\":true}".utf8))
            context.insert(child); scan.analysisRecords = [child]; try context.save()
        }
        return container
    }

    func receipt(_ status: ObservationPublicationStatus) throws -> ObservationPublicationReceipt {
        let row: [String: Any] = ["schema_version": 1, "operation_id": operation.uuidString.lowercased(),
            "observation_id": observation.uuidString.lowercased(), "analysis_id": analysis.uuidString.lowercased(), "status": status.rawValue]
        return try .decodeStatus(JSONSerialization.data(withJSONObject: row), request: request().statusRequest)
    }

    func stage(_ container: ModelContainer, note: String? = "Private synthetic note") throws -> ObservationPublicationIntent {
        try ObservationPublicationPersistence.stage(request(note: note), ownerID: owner, container: container, isCurrent: { true })
    }

    @Test(arguments: ObservationPublicationStatus.allCases)
    func acknowledgementStripsConsentButPreservesFingerprint(status: ObservationPublicationStatus) throws {
        let container = try container(), original = try stage(container)
        let next = try ObservationPublicationPersistence.acknowledge(receipt(status), expected: original, at: now,
            container: container, isCurrent: { true })
        let reopened = try ObservationPublicationIntent.decode(next.storedData())
        #expect(reopened.request == nil && reopened.requestSHA256 == original.requestSHA256)
        #expect(reopened.receipt?.status == status && reopened.observedAt == now)
        if reopened.isTerminal {
            let inventory = try LibraryMutationInventory.read(from: container, sourceUserID: owner)
            #expect(inventory.pendingJobs == 0 && inventory.attentionJobs == 0)
        }
        let data = String(decoding: try reopened.storedData(), as: UTF8.self)
        #expect(!data.contains("Private synthetic note") && !data.contains("media_ids") && !data.contains("expected_review_revision"))
        #expect(try stage(container).storedData() == next.storedData())
        #expect(throws: (any Error).self) { try stage(container, note: "Changed consent") }
    }

    @Test func canonicalDigestRejectsEveryChangedConsentFieldAndUnicodeNormalization() throws {
        let original = try request()
        let digest = try ObservationPublicationIntent.fingerprint(original)
        let row = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        let changes: [(String, Any)] = [
            ("note", NSNull()), ("note", ""), ("expected_observation_revision", 4), ("expected_review_revision", 2),
            ("taxonomy_version_id", UUID().uuidString.lowercased()), ("initial_taxon_id", UUID().uuidString.lowercased()),
            ("analysis_id", UUID().uuidString.lowercased()), ("observation_id", UUID().uuidString.lowercased()),
            ("media_ids", original.mediaIDs.reversed().map { $0.uuidString.lowercased() }),
            ("media_ids", [UUID().uuidString.lowercased()])
        ]
        for (key, value) in changes {
            var changed = row; changed[key] = value
            let request = try ObservationPublicationRequest.decode(JSONSerialization.data(withJSONObject: changed))
            #expect(try ObservationPublicationIntent.fingerprint(request) != digest)
        }
        #expect(try ObservationPublicationIntent.fingerprint(request(note: "é")) != ObservationPublicationIntent.fingerprint(request(note: "e\u{301}")))
        let restored = try ObservationPublicationRequest.decode(JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]))
        #expect(try ObservationPublicationIntent.fingerprint(restored) == digest)
    }

    @Test func malformedMetadataFailsClosedBeforeRestoration() throws {
        let original = try ObservationPublicationIntent(request: request(), ownerID: owner)
        let row = try #require(JSONSerialization.jsonObject(with: original.storedData()) as? [String: Any])
        for key in row.keys {
            var damaged = row; damaged.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try ObservationPublicationIntent.decode(JSONSerialization.data(withJSONObject: damaged)) }
        }
        let changes: [(String, Any)] = [("version", true), ("request_sha256", String(repeating: "a", count: 64)),
            ("observed_at", true), ("status", "admitted"), ("extra", "private")]
        for (key, value) in changes {
            var damaged = row; damaged[key] = value
            #expect(throws: (any Error).self) { try ObservationPublicationIntent.decode(JSONSerialization.data(withJSONObject: damaged)) }
        }
    }

    @Test func staleResponseCannotRegressOrReopenTerminalReceipt() throws {
        let container = try container(), original = try stage(container)
        let accepted = try ObservationPublicationPersistence.acknowledge(receipt(.accepted), expected: original, at: now,
            container: container, isCurrent: { true })
        #expect(throws: (any Error).self) {
            try ObservationPublicationPersistence.acknowledge(receipt(.processing), expected: original, at: now, container: container, isCurrent: { true })
        }
        let terminal = try ObservationPublicationPersistence.acknowledge(receipt(.admitted), expected: accepted, at: now,
            container: container, isCurrent: { true })
        #expect(throws: (any Error).self) {
            try ObservationPublicationPersistence.acknowledge(receipt(.accepted), expected: terminal, at: now, container: container, isCurrent: { true })
        }
        #expect(try stage(container).storedData() == terminal.storedData())
        let duplicate = try ObservationPublicationPersistence.acknowledge(receipt(.admitted), expected: terminal, at: now.addingTimeInterval(100),
            container: container, isCurrent: { true })
        #expect(duplicate.observedAt == now)
    }

    @Test func leaseLossBeforeSaveRollsBackAdmissionAndAcknowledgement() throws {
        let container = try container()
        var checks = 0
        #expect(throws: (any Error).self) {
            try ObservationPublicationPersistence.stage(request(), ownerID: owner, container: container, isCurrent: { checks += 1; return checks == 1 })
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        let original = try stage(container); checks = 0
        #expect(throws: (any Error).self) {
            try ObservationPublicationPersistence.acknowledge(receipt(.admitted), expected: original, at: now, container: container,
                isCurrent: { checks += 1; return checks == 1 })
        }
        #expect(try stage(container).storedData() == original.storedData())
        #expect(throws: (any Error).self) {
            try ObservationPublicationPersistence.stage(request(), ownerID: UUID(), container: container, isCurrent: { true })
        }
    }

    @Test func terminalReceiptSurvivesDiskReopeningWithoutRawConsent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("receipt.store")
        func write() throws {
            let container = try container(url: url), original = try stage(container)
            _ = try ObservationPublicationPersistence.acknowledge(receipt(.admitted), expected: original, at: now, container: container, isCurrent: { true })
        }
        try write()
        let reopened = try container(url: url, seed: false)
        let saved = try stage(reopened)
        #expect(saved.isTerminal && saved.request == nil && saved.observedAt == now)
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }

    @Test(arguments: [false, true])
    func directAndBulkDeletionEraseReceiptsAndRejectLateAcknowledgements(bulk: Bool) async throws {
        let container = try container(), original = try stage(container)
        _ = try ObservationPublicationPersistence.acknowledge(receipt(.admitted), expected: original, at: now, container: container, isCurrent: { true })
        // The primary key must retain erasure reachability after metadata damage.
        let damage = ModelContext(container)
        let job = try #require(try damage.fetchOfflineJob(id: ObservationPublicationPersistence.jobID(operation, observationID: observation)))
        job.subjectId = nil; job.metadataJSON = "damaged"; job.kindRaw = "future-corruption"
        try damage.save()
        if bulk {
            _ = try await BackgroundDatabaseActor(modelContainer: container).bulkDeleteNonBiologicalScans(
                payloads: [.init(id: observation.uuidString, mediaPaths: [])], requestingAccountID: owner)
        } else {
            let manager = OfflineQueueManager.shared, previous = manager.modelContext, online = manager.isOnline
            manager.modelContext = ModelContext(container); manager.isOnline = false
            defer { manager.modelContext = previous; manager.isOnline = online }
            let context = ModelContext(container), scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
            await ScanRepository.shared.eradicateScan(record: scan, modelContext: context, allowsMutation: { true })?.value
        }
        #expect(try ModelContext(container).fetchOfflineJob(id: ObservationPublicationPersistence.jobID(operation, observationID: observation)) == nil)
        #expect(throws: (any Error).self) { try stage(container) }
        #expect(throws: (any Error).self) {
            try ObservationPublicationPersistence.acknowledge(receipt(.accepted), expected: original, at: now, container: container, isCurrent: { true })
        }
    }

    @Test func sameOperationOnAnotherObservationConflictsAndDeletionDoesNotCrossNamespaces() throws {
        let container = try container(); _ = try stage(container)
        let context = ModelContext(container), other = UUID(), otherAnalysis = UUID()
        let scan = LocalScanRecord(id: other.uuidString, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        scan.analysisOwnerAccountID = owner.uuidString.lowercased(); scan.analysisSelectionInitialized = true
        scan.selectedAnalysisID = otherAnalysis.uuidString.lowercased(); scan.observationStateRevision = 3
        let child = try LocalAnalysisRecord(analysisID: otherAnalysis, observationID: scan.id, ownerAccountID: owner,
            completedAt: now, resultSnapshotData: Data("{\"synthetic\":true}".utf8))
        context.insert(scan); context.insert(child); scan.analysisRecords = [child]; try context.save()
        let original = try request()
        let reused = try ObservationPublicationRequest(operationID: operation, observationID: other, analysisID: otherAnalysis,
            expectedObservationRevision: 3, expectedReviewRevision: 1, taxonomyVersionID: original.taxonomyVersionID,
            initialTaxonID: nil, note: original.note, mediaIDs: original.mediaIDs)
        #expect(throws: (any Error).self) {
            try ObservationPublicationPersistence.stage(reused, ownerID: owner, container: container, isCurrent: { true })
        }
        let job = try #require(try context.fetchOfflineJob(id: ObservationPublicationPersistence.jobID(operation, observationID: observation)))
        job.subjectId = other.uuidString.lowercased(); try context.save()
        try ObservationPublicationPersistence.removeForDeletion(other.uuidString, context: context)
        try context.save()
        #expect(try context.fetchOfflineJob(id: job.id) != nil)
    }

    @Test func cloudCleanupUsesOwnerAndPrimaryKeyWhenSubjectIsMissing() throws {
        let container = try container(); _ = try stage(container)
        let context = ModelContext(container), id = ObservationPublicationPersistence.jobID(operation, observationID: observation)
        let job = try #require(try context.fetchOfflineJob(id: id)); job.subjectId = nil; try context.save()
        try ObservationPublicationPersistence.removeForDeletion(observation.uuidString, context: context, ownerID: owner)
        try context.save(); #expect(try context.fetchOfflineJob(id: id) == nil)
        _ = try stage(container)
        let damaged = try #require(try context.fetchOfflineJob(id: id)); damaged.metadataJSON = "damaged"; try context.save()
        #expect(throws: (any Error).self) {
            try ObservationPublicationPersistence.removeForDeletion(observation.uuidString, context: context, ownerID: owner)
        }
        #expect(try context.fetchOfflineJob(id: id) != nil)
    }

    @Test func cloudCleanupScopesOwnerAndExplicitDeletionErasesDamagedNamespace() throws {
        let container = try container(); _ = try stage(container)
        let context = ModelContext(container), id = ObservationPublicationPersistence.jobID(operation, observationID: observation)
        try ObservationPublicationPersistence.removeForDeletion(observation.uuidString, context: context, ownerID: UUID())
        try context.save(); #expect(try context.fetchOfflineJob(id: id) != nil)
        try ObservationPublicationPersistence.removeForDeletion(observation.uuidString, context: context, ownerID: owner)
        context.rollback(); #expect(try ModelContext(container).fetchOfflineJob(id: id) != nil)
        let job = try #require(try context.fetchOfflineJob(id: id))
        job.kindRaw = "unknown-future"; job.subjectId = nil; job.metadataJSON = "damaged"; try context.save()
        try ObservationPublicationPersistence.removeForDeletion(observation.uuidString, context: context)
        try context.save(); #expect(try ModelContext(container).fetchOfflineJob(id: id) == nil)
    }
}
