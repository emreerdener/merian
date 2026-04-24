import Foundation
import Testing
import SwiftData
@testable import Merian

/// Validates the SwiftData migration plan structurally — ensures no two consecutive custom migration
/// stages produce the same NSManagedObjectModel, which causes a fatal crash on iOS 26+.
///
/// Two test categories:
///  1. In-memory init — covers the case where the app has no existing store (fresh install).
///  2. Disk migration — covers the case where a user upgrades from a prior schema version.
///     On iOS 26+, `NSCustomMigrationStage` validates all custom stages at migration time,
///     not just the one being applied. Any stage with equal from/to models crashes at that point.
@Suite(.serialized)
@MainActor
struct MigrationPlanTests {

    /// Mirrors MerianApp.init() exactly, using in-memory storage to keep the test fast.
    ///
    /// On iOS 26+, `NSCustomMigrationStage` validates at `ModelContainer` init time that
    /// `fromVersion` and `toVersion` resolve to non-equal `NSManagedObjectModelReference` values.
    /// If any custom stage has equal references (both schemas pointing to the same global model type),
    /// this throws at app launch:
    ///   'The current model reference and the next model reference cannot be equal.'
    ///
    /// Regression coverage: V24/V25/V26 extension-pattern name resolution ambiguity (2026-03).
    @Test func migrationPlanContainerInitializesWithoutCrash() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        _ = try ModelContainer(
            for: schema,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config]
        )
    }

    /// Simulates upgrading from V26 to V27 on-disk — the scenario that triggers iOS 26's
    /// eager custom-stage validation during `migrateStoreWithContext:error:`.
    ///
    /// On iOS 26, when any migration runs (even lightweight V26→V27), SwiftData iterates ALL
    /// custom stages in MerianMigrationPlan.stages and calls NSCustomMigrationStage.init for each.
    /// If any pair produces equal NSManagedObjectModelReferences, the app crashes before migration
    /// even begins. The in-memory test above does NOT cover this path because no migration runs.
    ///
    /// This test:
    ///  1. Creates a disk-based V26 store (no migration plan — just the V26 schema).
    ///  2. Reopens the same store with the full migration plan targeting V27.
    ///  3. Verifies no crash occurs during stage validation and store loading.
    @Test func migrationFromV26ToV27DoesNotCrash() throws {
        let url = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + "_v26migration_test.sqlite")

        // Step 1 — create a V26 store with no migration plan.
        let schema26 = Schema(versionedSchema: MerianSchemaV26.self)
        let config26 = ModelConfiguration(schema: schema26, url: url)
        let container26 = try ModelContainer(for: schema26, configurations: [config26])

        // Insert a minimal V26 record so the store actually has data and is not empty.
        let context26 = ModelContext(container26)
        let record = MerianSchemaV26.LocalScanRecord(
            speciesId: "test-species",
            scientificName: "Testus testus",
            commonName: "Test Species",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )
        context26.insert(record)
        try context26.save()

        // Close V26 container before reopening with migration plan.
        _ = container26

        // Step 2 — reopen with the full migration plan targeting V27.
        // On iOS 26, this triggers NSCustomMigrationStage construction for ALL custom stages.
        let schema27 = Schema(versionedSchema: CurrentSchema.self)
        let config27 = ModelConfiguration(schema: schema27, url: url)
        _ = try ModelContainer(
            for: schema27,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config27]
        )

        // Clean up the temp file.
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-shm"))
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-wal"))
    }

    /// Simulates upgrading from V28 to V29 on-disk — verifies that adding
    /// `userIdentificationOverride` and `userConfirmedIdentification` (lightweight migration,
    /// no custom stage) does not crash during iOS 26 migration plan validation.
    @Test func migrationFromV28ToV29DoesNotCrash() throws {
        let url = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + "_v28migration_test.sqlite")

        // Step 1 — create a V28 store with no migration plan.
        let schema28 = Schema(versionedSchema: MerianSchemaV28.self)
        let config28 = ModelConfiguration(schema: schema28, url: url)
        let container28 = try ModelContainer(for: schema28, configurations: [config28])

        // Insert a minimal V28 record so the store has data and is not empty.
        let context28 = ModelContext(container28)
        let record = MerianSchemaV28.LocalScanRecord(
            speciesId: "test-v28-species",
            scientificName: "Testus testus",
            commonName: "Test Species",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )
        context28.insert(record)
        try context28.save()

        // Close V28 container before reopening with migration plan.
        _ = container28

        // Step 2 — reopen with the full migration plan targeting the current schema (V29).
        let schema29 = Schema(versionedSchema: CurrentSchema.self)
        let config29 = ModelConfiguration(schema: schema29, url: url)
        _ = try ModelContainer(
            for: schema29,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config29]
        )

        // Clean up the temp file.
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-shm"))
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-wal"))
    }

    /// Simulates upgrading from V30 to V33 on-disk — verifies that adding
    /// `isFlagged` (V31), `isUploaded` (V32), and migrating to `scanStateRaw` (V33)
    /// does not crash during iOS 26 migration plan validation.
    @Test func migrationFromV30ToV33DoesNotCrash() throws {
        let url = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + "_v30migration_test.sqlite")

        // Step 1 — create a V30 store with no migration plan.
        let schema30 = Schema(versionedSchema: MerianSchemaV30.self)
        let config30 = ModelConfiguration(schema: schema30, url: url)
        let container30 = try ModelContainer(for: schema30, configurations: [config30])

        // Insert a minimal V30 record so the store has data and is not empty.
        let context30 = ModelContext(container30)
        let record = MerianSchemaV30.LocalScanRecord(
            speciesId: "test-v30-species",
            scientificName: "Testus testus",
            commonName: "Test Species",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )
        context30.insert(record)
        try context30.save()

        // Close V30 container before reopening with migration plan.
        _ = container30

        // Step 2 — reopen with the full migration plan targeting the current schema (V33).
        let schema33 = Schema(versionedSchema: CurrentSchema.self)
        let config33 = ModelConfiguration(schema: schema33, url: url)
        _ = try ModelContainer(
            for: schema33,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config33]
        )

        // Clean up the temp file.
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-shm"))
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-wal"))
    }

    /// Simulates upgrading from V38 to V39 — verifies that the custom migration stage
    /// correctly backfills the singular `audioFilePath`/`observationContextJSON` String?
    /// columns into the new plural `audioFilePaths`/`observationContextsJSON` [String]? arrays.
    ///
    /// Zeroes the four `nonisolated(unsafe) static var` backfill dictionaries before and
    /// after via `defer` to prevent false positives from other tests running in the same process.

    @Test func testFullMigrationV38ToV40() throws {
        // Guard against stale backfill data from a prior test in the same process.
        MerianMigrationPlan._v38LocalAudioBackfill.removeAll()
        MerianMigrationPlan._v38LocalContextBackfill.removeAll()
        MerianMigrationPlan._v38OfflineAudioBackfill.removeAll()
        MerianMigrationPlan._v38OfflineContextBackfill.removeAll()
        MerianMigrationPlan._v38LocalAdditionalImagesBackfill.removeAll()
        MerianMigrationPlan._v38LocalSemanticTagsBackfill.removeAll()
        MerianMigrationPlan._v38OfflineLocalImagesBackfill.removeAll()
        defer {
            MerianMigrationPlan._v38LocalAudioBackfill.removeAll()
            MerianMigrationPlan._v38LocalContextBackfill.removeAll()
            MerianMigrationPlan._v38OfflineAudioBackfill.removeAll()
            MerianMigrationPlan._v38OfflineContextBackfill.removeAll()
            MerianMigrationPlan._v38LocalAdditionalImagesBackfill.removeAll()
            MerianMigrationPlan._v38LocalSemanticTagsBackfill.removeAll()
            MerianMigrationPlan._v38OfflineLocalImagesBackfill.removeAll()
        }

        let url = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + "_v38migration_test.sqlite")

        // Step 1 — create a V38 store with both model types carrying the singular fields.
        let schema38 = Schema(versionedSchema: MerianSchemaV38.self)
        let config38 = ModelConfiguration(schema: schema38, url: url)
        let container38 = try ModelContainer(for: schema38, configurations: [config38])
        let context38 = ModelContext(container38)

        let localRecord = MerianSchemaV38.LocalScanRecord(
            speciesId: "test-species",
            scientificName: "Testus testus",
            commonName: "Test Species",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown",
            observationContextJSON: "{\"freeText\":\"Yellow wings\"}",
            audioFilePath: "recording_abc.wav"
        )
        localRecord.additionalImagePaths = ["extra1.webp"]
        localRecord.localImagePath = "main_image.webp"
        context38.insert(localRecord)

        let offlineRecord = MerianSchemaV38.OfflineQueuedScan(
            localImagePaths: ["offline_img1.webp"],
            observationContextJSON: "{\"freeText\":\"Near water\"}",
            audioFilePath: "offline_recording.wav"
        )
        context38.insert(offlineRecord)
        try context38.save()

        let capturedLocalId = localRecord.id
        let capturedOfflineId = offlineRecord.id
        _ = container38

        // Step 2 — reopen with the full migration plan targeting V40 (CurrentSchema).
        let schema40 = Schema(versionedSchema: CurrentSchema.self)
        let config40 = ModelConfiguration(schema: schema40, url: url)
        let container40 = try ModelContainer(
            for: schema40,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config40]
        )

        // Step 3 — verify both models migrated to V40 correctly.
        let context40 = ModelContext(container40)

        var localDescriptor = FetchDescriptor<LocalScanRecord>()
        localDescriptor.fetchLimit = 500
        let localScans = try context40.fetch(localDescriptor)
        let migratedLocal = localScans.first { $0.id == capturedLocalId }
        #expect(migratedLocal != nil, "LocalScanRecord must survive V38→V40 migration")
        #expect(
            migratedLocal?.capturedMediaJSON?.contains("recording_abc.wav") == true,
            "capturedMediaJSON must contain audioFilePath"
        )
        #expect(
            migratedLocal?.capturedMediaJSON?.contains("Yellow wings") == true,
            "capturedMediaJSON must contain observationContextJSON"
        )
        #expect(
            migratedLocal?.capturedMediaJSON?.contains("extra1.webp") == true,
            "capturedMediaJSON must contain additionalImagePaths"
        )
        #expect(
            migratedLocal?.capturedMediaJSON?.contains("main_image.webp") == true,
            "capturedMediaJSON must contain main_image.webp"
        )

        var offlineDescriptor = FetchDescriptor<OfflineQueuedScan>()
        offlineDescriptor.fetchLimit = 500
        let offlineScans = try context40.fetch(offlineDescriptor)
        let migratedOffline = offlineScans.first { $0.id == capturedOfflineId }
        #expect(migratedOffline != nil, "OfflineQueuedScan must survive V38→V40 migration")
        #expect(
            migratedOffline?.capturedMediaJSON?.contains("offline_recording.wav") == true,
            "capturedMediaJSON must contain audioFilePath"
        )
        #expect(
            migratedOffline?.capturedMediaJSON?.contains("Near water") == true,
            "capturedMediaJSON must contain observationContextJSON"
        )
        #expect(
            migratedOffline?.capturedMediaJSON?.contains("offline_img1.webp") == true,
            "capturedMediaJSON must contain localImagePaths"
        )

        // Cleanup.
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-shm"))
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-wal"))
    }
    @Test func testFullMigrationV39ToV40BackfillsMediaJSON() throws {
        // Ensures cleanup of static state between runs.
        defer {
            MerianMigrationPlan._v39LocalMediaBackfill.removeAll()
            MerianMigrationPlan._v39OfflineMediaBackfill.removeAll()
            MerianMigrationPlan._v39LocalCoverBackfill.removeAll()
            MerianMigrationPlan._v39OfflineCoverBackfill.removeAll()
        }

        let url = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + "_v39migration_test.sqlite")

        // Step 1 — create a V39 store with plural fields populated.
        let schema39 = Schema(versionedSchema: MerianSchemaV39.self)
        let config39 = ModelConfiguration(schema: schema39, url: url)
        let container39 = try ModelContainer(for: schema39, configurations: [config39])
        let context39 = ModelContext(container39)

        let localRecord = MerianSchemaV39.LocalScanRecord(
            speciesId: "test-species",
            scientificName: "Testus testus",
            commonName: "Test Species",
            localImagePath: "main_image.webp",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown",
            additionalImagePaths: ["extra1.webp", "extra2.webp"],
            observationContextsJSON: ["{\"freeText\":\"Yellow wings\"}"]
        )
        // Set audioFilePaths manually since init doesn't take it in V39 snapshot
        localRecord.audioFilePaths = ["recording_abc.wav"]
        context39.insert(localRecord)

        let offlineRecord = MerianSchemaV39.OfflineQueuedScan(
            localImagePaths: ["offline_main.webp", "offline_extra.webp"],
            observationContextsJSON: ["{\"freeText\":\"Near water\"}"]
        )
        // Set audioFilePaths manually
        offlineRecord.audioFilePaths = ["offline_recording.wav"]
        context39.insert(offlineRecord)
        try context39.save()

        let capturedLocalId = localRecord.id
        let capturedOfflineId = offlineRecord.id
        _ = container39

        // Step 2 — reopen with the full migration plan targeting V40 (CurrentSchema).
        let schema40 = Schema(versionedSchema: CurrentSchema.self)
        let config40 = ModelConfiguration(schema: schema40, url: url)
        let container40 = try ModelContainer(
            for: schema40,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config40]
        )

        // Step 3 — verify both models had their arrays consolidated into capturedMediaJSON.
        let context40 = ModelContext(container40)

        var localDescriptor = FetchDescriptor<LocalScanRecord>()
        localDescriptor.fetchLimit = 500
        let localScans = try context40.fetch(localDescriptor)
        let migratedLocal = localScans.first { $0.id == capturedLocalId }
        
        #expect(migratedLocal != nil, "LocalScanRecord must survive V39→V40 migration")
        
        // Assert coverImagePath is the first image
        #expect(migratedLocal?.coverImagePath == "main_image.webp", "coverImagePath must be the first image")
        
        // Decode JSON and verify structure and order
        if let jsonStr = migratedLocal?.capturedMediaJSON,
           let jsonData = jsonStr.data(using: String.Encoding.utf8),
           let items = try? JSONDecoder().decode([SerializedMediaItem].self, from: jsonData) {
            #expect(items.count == 5, "Should have 5 items: 1 main image, 2 extra images, 1 description, 1 audio")
            
            if items.count == 5 {
                if case .image(let path) = items[0] { #expect(path == "main_image.webp") } else { Issue.record("Item 0 not image") }
                if case .image(let path) = items[1] { #expect(path == "extra1.webp") } else { Issue.record("Item 1 not image") }
                if case .image(let path) = items[2] { #expect(path == "extra2.webp") } else { Issue.record("Item 2 not image") }
                if case .description(let ctx) = items[3] { #expect(ctx.freeText == "Yellow wings") } else { Issue.record("Item 3 not description") }
                if case .audio(let path) = items[4] { #expect(path == "recording_abc.wav") } else { Issue.record("Item 4 not audio") }
            }
        } else {
            Issue.record("Failed to decode capturedMediaJSON for migratedLocal")
        }

        var offlineDescriptor = FetchDescriptor<OfflineQueuedScan>()
        offlineDescriptor.fetchLimit = 500
        let offlineScans = try context40.fetch(offlineDescriptor)
        let migratedOffline = offlineScans.first { $0.id == capturedOfflineId }
        
        #expect(migratedOffline != nil, "OfflineQueuedScan must survive V39→V40 migration")
        
        // Assert coverImagePath is the first image
        #expect(migratedOffline?.coverImagePath == "offline_main.webp", "coverImagePath must be the first image")
        
        // Decode JSON and verify structure and order
        if let jsonStr = migratedOffline?.capturedMediaJSON,
           let jsonData = jsonStr.data(using: String.Encoding.utf8),
           let items = try? JSONDecoder().decode([SerializedMediaItem].self, from: jsonData) {
            #expect(items.count == 4, "Should have 4 items: 2 images, 1 description, 1 audio")
            
            if items.count == 4 {
                if case .image(let path) = items[0] { #expect(path == "offline_main.webp") } else { Issue.record("Item 0 not image") }
                if case .image(let path) = items[1] { #expect(path == "offline_extra.webp") } else { Issue.record("Item 1 not image") }
                if case .description(let ctx) = items[2] { #expect(ctx.freeText == "Near water") } else { Issue.record("Item 2 not description") }
                if case .audio(let path) = items[3] { #expect(path == "offline_recording.wav") } else { Issue.record("Item 3 not audio") }
            }
        } else {
            Issue.record("Failed to decode capturedMediaJSON for migratedOffline")
        }

        // Cleanup.
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-shm"))
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-wal"))
    }
}
