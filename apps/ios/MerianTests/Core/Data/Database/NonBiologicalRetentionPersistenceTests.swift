import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Non-Biological Retention Persistence")
struct NonBiologicalRetentionPersistenceTests {
    @Test func testBulkDeleteNonBiologicalScansCommitsBeforeReturningPaths() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let scan = LocalScanRecord(
            id: "nonbio_delete_001",
            speciesId: "nonbio_species",
            scientificName: "Concrete slab",
            commonName: "Concrete slab",
            timestamp: Date(),
            isBiological: false,
            isLiveCapture: false,
            ecologyType: "unknown"
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let deletedPaths = try await actor.bulkDeleteNonBiologicalScans(
            payloads: [
                .init(
                    id: scan.id,
                    mediaPaths: [
                        "nonbio_001.webp",
                        "https://merian.app/cloud.webp"
                    ]
                )
            ]
        )

        let recordDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == "nonbio_delete_001" }
        )
        let taskDescriptor = FetchDescriptor<PendingCloudDeletionTask>(
            predicate: #Predicate { $0.scanId == "nonbio_delete_001" }
        )
        #expect(
            try context.fetch(recordDescriptor).isEmpty,
            "Record should be deleted once the actor returns success"
        )
        #expect(
            try context.fetch(taskDescriptor).count == 1,
            "Cloud deletion task must be committed atomically with the delete"
        )
        #expect(
            deletedPaths == ["nonbio_001.webp"],
            "Only local file paths should be returned for post-commit deletion"
        )
    }

    @Test func testBulkDeleteNonBiologicalScansReusesExistingPendingCloudDeletionTask() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "nonbio_conflict_001"

        let scan = LocalScanRecord(
            id: scanId,
            speciesId: "nonbio_species_conflict",
            scientificName: "Parking cone",
            commonName: "Parking cone",
            timestamp: Date(),
            isBiological: false,
            isLiveCapture: false,
            ecologyType: "unknown"
        )
        context.insert(scan)
        context.insert(PendingCloudDeletionTask(scanId: scanId))
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let deletedPaths = try await actor.bulkDeleteNonBiologicalScans(
            payloads: [
                .init(
                    id: scanId,
                    mediaPaths: ["should_not_delete.webp"]
                )
            ]
        )

        let recordDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        let taskDescriptor = FetchDescriptor<PendingCloudDeletionTask>(
            predicate: #Predicate { $0.scanId == scanId }
        )

        #expect(
            try context.fetch(recordDescriptor).isEmpty,
            "Delete should still succeed when a cloud deletion task already exists"
        )
        #expect(
            try context.fetch(taskDescriptor).count == 1,
            "Re-queueing must remain idempotent and preserve a single cloud deletion task"
        )
        #expect(
            deletedPaths == ["should_not_delete.webp"],
            "Committed local file paths should still be returned for cleanup"
        )
    }

    @Test func testBulkDeleteNonBiologicalScansKeepsMissingRecordCleanupIdempotent() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "nonbio_already_missing"
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let payload = BackgroundDatabaseActor.ScanErasurePayload(
            id: scanId,
            mediaPaths: [
                "missing_nonbio.wav",
                "https://merian.example/missing_nonbio.wav"
            ]
        )

        let firstDeletedPaths = try await actor.bulkDeleteNonBiologicalScans(
            payloads: [payload]
        )
        let secondDeletedPaths = try await actor.bulkDeleteNonBiologicalScans(
            payloads: [payload]
        )

        let taskDescriptor = FetchDescriptor<PendingCloudDeletionTask>(
            predicate: #Predicate { $0.scanId == scanId }
        )
        #expect(
            try context.fetch(taskDescriptor).count == 1,
            "Retries for a missing row must preserve one cloud deletion task"
        )
        #expect(firstDeletedPaths == ["missing_nonbio.wav"])
        #expect(secondDeletedPaths == ["missing_nonbio.wav"])
    }

    @Test func testBulkDeleteNonBiologicalScansRevalidatesEligibilityBeforeCommit() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "nonbio_reclassified_before_delete"
        let scan = LocalScanRecord(
            id: scanId,
            speciesId: "reclassified_species",
            scientificName: "Quercus alba",
            commonName: "White Oak",
            timestamp: Date(),
            isBiological: true,
            isLiveCapture: false,
            ecologyType: "wild"
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let deletedPaths = try await actor.bulkDeleteNonBiologicalScans(
            payloads: [
                .init(
                    id: scanId,
                    mediaPaths: ["must-remain.webp"]
                )
            ]
        )

        let recordDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        let taskDescriptor = FetchDescriptor<PendingCloudDeletionTask>(
            predicate: #Predicate { $0.scanId == scanId }
        )

        #expect(try context.fetch(recordDescriptor).count == 1)
        #expect(try context.fetch(taskDescriptor).isEmpty)
        #expect(deletedPaths.isEmpty)
    }

    @Test func testPurgeExpiredNonBiologicalScansDeletesOnlyExpiredNonBioRecords() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let cutoffDate = referenceDate.addingTimeInterval(
            TimeInterval(
                -MerianConfig.nonBiologicalRetentionDays * 24 * 60 * 60
            )
        )
        let mediaJSON = try #require(CapturedMediaSnapshot(items: [
            .image(.documents("expired_nonbio.webp")),
            .audio(.documents("expired_nonbio.wav")),
            .image(.remoteURL("https://merian.example/nonbio.webp"))
        ]).jsonString)

        let expiredNonBio = LocalScanRecord(
            id: "expired_nonbio",
            speciesId: "nonbio_species",
            scientificName: "Notebook",
            commonName: "Notebook",
            timestamp: cutoffDate.addingTimeInterval(-60),
            capturedMediaJSON: mediaJSON,
            isBiological: false,
            isLiveCapture: false,
            ecologyType: "unknown"
        )
        let freshNonBio = LocalScanRecord(
            id: "fresh_nonbio",
            speciesId: "nonbio_species_fresh",
            scientificName: "Desk",
            commonName: "Desk",
            timestamp: cutoffDate.addingTimeInterval(60),
            isBiological: false,
            isLiveCapture: false,
            ecologyType: "unknown"
        )
        let expiredBiological = LocalScanRecord(
            id: "expired_bio",
            speciesId: "bio_species",
            scientificName: "Quercus alba",
            commonName: "White Oak",
            timestamp: cutoffDate.addingTimeInterval(-60),
            isBiological: true,
            isLiveCapture: false,
            ecologyType: "wild"
        )
        context.insert(expiredNonBio)
        context.insert(freshNonBio)
        context.insert(expiredBiological)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let result = try await actor.purgeExpiredNonBiologicalScans(
            cutoffDate: cutoffDate
        )

        let recordDescriptor = FetchDescriptor<LocalScanRecord>()
        let remainingIds = try context.fetch(recordDescriptor).map(\.id)
        let taskDescriptor = FetchDescriptor<PendingCloudDeletionTask>(
            predicate: #Predicate { $0.scanId == "expired_nonbio" }
        )

        #expect(
            !remainingIds.contains("expired_nonbio"),
            "Expired non-biological records should be removed locally"
        )
        #expect(
            remainingIds.contains("fresh_nonbio"),
            "Fresh non-biological records should remain"
        )
        #expect(
            remainingIds.contains("expired_bio"),
            "Biological records should not be affected by the nonbio purge"
        )
        #expect(
            try context.fetch(taskDescriptor).count == 1,
            "Expired local purge should queue cloud deletion idempotently"
        )
        #expect(
            result.committedErasureCount == 1,
            "The purge result should report one accepted erasure"
        )
        #expect(
            result.deletedRecordCount == 1,
            "The purge result should report the count of committed record deletions"
        )
        #expect(
            result.localMediaPaths == [
                "expired_nonbio.webp",
                "expired_nonbio.wav"
            ],
            "Only local mixed-media paths should be returned for cleanup"
        )
    }

    @Test func testPurgeExpiredNonBiologicalScansHonorsOldestFirstBatchLimit() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let cutoffDate = Date(timeIntervalSince1970: 1_800_000_000)
        let records = try [
            ("nonbio_oldest", -180.0, "nonbio_oldest.webp"),
            ("nonbio_middle", -120.0, "nonbio_middle.webp"),
            ("nonbio_newest", -60.0, "nonbio_newest.webp")
        ].map { id, age, mediaPath in
            let mediaJSON = try #require(
                CapturedMediaSnapshot(items: [
                    .image(.documents(mediaPath))
                ]).jsonString
            )
            return LocalScanRecord(
                id: id,
                speciesId: "nonbio_\(id)",
                scientificName: "Non-biological observation",
                commonName: "Non-biological observation",
                timestamp: cutoffDate.addingTimeInterval(age),
                capturedMediaJSON: mediaJSON,
                isBiological: false,
                isLiveCapture: false,
                ecologyType: "unknown"
            )
        }
        for record in records {
            context.insert(record)
        }
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let result = try await actor.purgeExpiredNonBiologicalScans(
            cutoffDate: cutoffDate,
            limit: 2
        )

        let remainingIds = Set(
            try context.fetch(FetchDescriptor<LocalScanRecord>()).map(\.id)
        )
        let queuedIds = Set(
            try context.fetch(FetchDescriptor<PendingCloudDeletionTask>())
                .map(\.scanId)
        )
        #expect(result.committedErasureCount == 2)
        #expect(result.deletedRecordCount == 2)
        #expect(
            result.localMediaPaths == [
                "nonbio_oldest.webp",
                "nonbio_middle.webp"
            ],
            "The bounded purge should return committed paths oldest first"
        )
        #expect(remainingIds == ["nonbio_newest"])
        #expect(queuedIds == ["nonbio_oldest", "nonbio_middle"])
    }
}
