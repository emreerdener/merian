import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationHistoryEnrollmentProtectionTests {
    let support = ObservationHistoryEnrollmentTests()
    var observation: UUID { UUID(uuidString: support.support.support.observation)! }
    var owner: UUID { support.support.support.owner }

    func hold(_ container: ModelContainer) throws {
        let context = ModelContext(container)
        _ = try ObservationHistoryEnrollmentIntent.stage(observationID: observation, ownerID: owner, context: context)
        try context.save()
    }

    @Test(arguments: [false, true])
    func queuedLegacyActorWritesCannotChangeHeldOrEnrolledScan(acknowledged: Bool) async throws {
        let container = try support.container()
        let actor = BackgroundDatabaseActor(modelContainer: container)
        if acknowledged { _ = try await support.run(support.service(), container) } else { try hold(container) }
        let before = try #require(ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        let originalName = before.commonName, originalOverride = before.userIdentificationOverride
        let originalConfirmed = before.userConfirmedIdentification, originalFlag = before.isFlagged
        await actor.beginScanIdentificationOverride(scanId: before.id, scientificName: "Forbidden override")
        await actor.updateScanWithOverride(scanId: before.id, override: "Forbidden override", confirmed: false,
            newConfirmedSpeciesId: nil, userReviewState: .userOverridden)
        await actor.updateScanAsUnflagged(scanId: before.id)
        await actor.updateScanWithOverrideSpeciesData(scanId: before.id, commonName: "Forbidden name", hazardType: "none",
            wikipediaOverview: nil, wikipediaUrl: nil, referenceImageUrl: nil, iucnRedListStatus: nil,
            habitatDescription: nil, gbifTaxonKey: nil, taxonomy: nil, replacingSpeciesIdentity: true)
        let after = try #require(ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(after.commonName == originalName && after.userIdentificationOverride == originalOverride)
        #expect(after.userConfirmedIdentification == originalConfirmed && after.isFlagged == originalFlag)
    }

    @Test func delayedReplacementCannotDeleteHeldOrAcknowledgedOriginalThroughStaleContext() async throws {
        let container = try support.container(), stale = ModelContext(container)
        let original = try #require(stale.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(original.analysisOwnerAccountID == nil)
        let service = support.service(duringEnroll: {
            #expect(ScanRepository.shared.eradicateScan(record: original, modelContext: stale,
                origin: .reanalysisReplacement, allowsMutation: { true }) == nil)
            let pendingCount = try ModelContext(container).fetchCount(FetchDescriptor<PendingCloudDeletionTask>())
            #expect(pendingCount == 0)
        })
        _ = try await support.run(service, container)
        #expect(ScanRepository.shared.eradicateScan(record: original, modelContext: stale,
            origin: .reanalysisReplacement, allowsMutation: { true }) == nil)
        let verify = ModelContext(container)
        #expect(try verify.fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
        #expect(try verify.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
        #expect(try verify.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 0)
    }

    @Test func explicitDeletionSupersedesHoldAndWinsOverLateEnrollmentResponse() async throws {
        let container = try support.container()
        let manager = OfflineQueueManager.shared, previous = manager.modelContext, online = manager.isOnline
        manager.modelContext = ModelContext(container); manager.isOnline = false
        defer { manager.modelContext = previous; manager.isOnline = online }
        var cleanup: Task<Void, Never>?
        let service = support.service(duringEnroll: {
            let context = ModelContext(container), scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
            cleanup = ScanRepository.shared.eradicateScan(record: scan, modelContext: context, allowsMutation: { true })
        })
        await #expect(throws: ObservationHistoryError.deleted) { try await support.run(service, container) }
        await cleanup?.value
        let verify = ModelContext(container)
        #expect(try verify.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        #expect(try verify.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
        #expect(try verify.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 1)
        #expect(try ObservationHistoryEnrollmentIntent.holds(observation.uuidString, context: verify))
        let fence = try #require(try verify.fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.jobID(observation.uuidString)))
        #expect(fence.status == .cancelled && fence.metadataJSON == nil)
        // Even after cloud erasure has acknowledged and removed its task, a stale page cannot recreate A.
        for task in try verify.fetch(FetchDescriptor<PendingCloudDeletionTask>()) { verify.delete(task) }
        try verify.save()
        let response = try JSONDecoder().decode(HistoricalScanResponse.self, from: Data("{\"id\":\"\(observation.uuidString.lowercased())\",\"timestamp\":\"2026-01-01T00:00:00Z\"}".utf8))
        #expect(try await HistoricalDatabaseActor(modelContainer: container).reconcileScanPage(responses: [response]) == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
    }

    @Test func automaticExpirySkipsHeldPageAndExplicitNonbioDeletionSupersedesHold() async throws {
        let container = try support.container()
        try support.support.update(container) { scan, context in
            scan.isBiological = false; scan.timestamp = Date(timeIntervalSince1970: 1)
            context.insert(LocalScanRecord(id: "later-expiry", speciesId: "", scientificName: "Synthetic object", commonName: "Synthetic object",
                timestamp: Date(timeIntervalSince1970: 2), isBiological: false))
        }
        try hold(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let result = try await actor.purgeExpiredNonBiologicalScans(cutoffDate: Date(timeIntervalSince1970: 3), limit: 1, requestingAccountID: owner)
        #expect(result.deletedRecordCount == 1)
        let verify = ModelContext(container)
        #expect(try verify.fetch(FetchDescriptor<LocalScanRecord>()).first?.id.lowercased() == observation.uuidString.lowercased())
        #expect(try verify.fetch(FetchDescriptor<PendingCloudDeletionTask>()).first?.scanId == "later-expiry")
        _ = try await actor.bulkDeleteNonBiologicalScans(payloads: [.init(id: observation.uuidString.uppercased(), mediaPaths: [])], requestingAccountID: owner)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        #expect(try ObservationHistoryEnrollmentIntent.holds(observation.uuidString, context: ModelContext(container)))
    }

    @Test func malformedHoldStillProtectsDeletionAndExplicitErasureRetiresIt() async throws {
        let container = try support.container(), context = ModelContext(container)
        context.insert(OfflineJobRecord(id: ObservationHistoryEnrollmentIntent.jobID(observation.uuidString), kind: .future, metadataJSON: "invalid"))
        try context.save()
        let record = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(ScanRepository.shared.eradicateScan(record: record, modelContext: context, origin: .reanalysisReplacement, allowsMutation: { true }) == nil)
        try ObservationHistoryEnrollmentIntent.supersedeForExplicitDeletion(record.id, context: context)
        try context.save()
        #expect(try ObservationHistoryEnrollmentIntent.holds(record.id, context: context))
    }

    @Test func acknowledgedHistoryErasureCreatesTerminalFenceThroughStaleContext() async throws {
        let container = try support.container(), stale = ModelContext(container)
        _ = try stale.fetch(FetchDescriptor<LocalScanRecord>())
        _ = try await support.run(support.service(), container)
        try ObservationHistoryEnrollmentIntent.supersedeForExplicitDeletion(observation.uuidString, context: stale)
        try stale.save()
        let job = try #require(try ModelContext(container).fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.jobID(observation.uuidString)))
        #expect(job.status == .cancelled && job.metadataJSON == nil)
        #expect(throws: ObservationHistoryEnrollmentIntent.IntegrityError.self) {
            try ObservationHistoryEnrollmentIntent.stage(observationID: observation, ownerID: owner, context: ModelContext(container))
        }
    }

    @Test func pendingLegacyDeletionBlocksHistoricalReinsertion() async throws {
        let container = try support.container(), context = ModelContext(container)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        try context.ensurePendingCloudDeletionTask(scanId: scan.id, requestingAccountID: owner, origin: .explicitUserDeletion)
        context.delete(scan); try context.save()
        let response = try JSONDecoder().decode(HistoricalScanResponse.self, from: Data("{\"id\":\"\(observation.uuidString.lowercased())\",\"timestamp\":\"2026-01-01T00:00:00Z\"}".utf8))
        #expect(try await HistoricalDatabaseActor(modelContainer: container).reconcileScanPage(responses: [response]) == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
    }

    @Test func historicalAndEnrichmentHydrationCannotAlterHeldBaseline() async throws {
        let container = try support.container()
        // Prime actors before the hold to exercise stale model contexts.
        let background = BackgroundDatabaseActor(modelContainer: container)
        _ = await background.updateScanWithWikipedia(scanId: observation.uuidString.uppercased(), extract: nil, url: nil, imageUrl: nil)
        try hold(container)
        let data = Data("{\"id\":\"\(observation.uuidString.uppercased())\",\"ai_reasoning\":\"Remote replacement\",\"ai_confidence_score\":0.2}".utf8)
        let response = try JSONDecoder().decode(HistoricalScanResponse.self, from: data)
        let historical = HistoricalDatabaseActor(modelContainer: container)
        _ = try await historical.reconcileScanPage(responses: [response])
        #expect(await background.updateScanWithWikipedia(scanId: observation.uuidString.uppercased(), extract: "Delayed enrichment", url: nil, imageUrl: nil) == false)
        await background.updateScanWithEnrichment(scanId: observation.uuidString.uppercased(), habitatDescription: "Delayed habitat", gbifTaxonKey: nil, similarSpeciesJsonData: nil, taxonomy: nil)
        let verify = ModelContext(container), scan = try #require(verify.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(scan.aiReasoning == "Synthetic saved identification." && scan.confidenceScore == 0.75)
        #expect(scan.wikipediaOverview == "Locally saved overview" && scan.habitatDescription == nil)
        _ = try await support.run(support.service(), container)
        // Legacy pages remain fenced after acknowledgment; enrichment may resume.
        _ = try await historical.reconcileScanPage(responses: [response])
        #expect(await background.updateScanWithWikipedia(scanId: observation.uuidString.uppercased(), extract: "New enrichment", url: nil, imageUrl: nil))
        let after = try #require(ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(after.aiReasoning == "Synthetic saved identification." && after.wikipediaOverview == "New enrichment")
    }
}
