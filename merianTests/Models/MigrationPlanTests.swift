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
    @Test func migrationFromV38ToV39BackfillsArrayColumns() throws {
        // Guard against stale backfill data from a prior test in the same process.
        MerianMigrationPlan._v38LocalAudioBackfill = [:]
        MerianMigrationPlan._v38LocalContextBackfill = [:]
        MerianMigrationPlan._v38OfflineAudioBackfill = [:]
        MerianMigrationPlan._v38OfflineContextBackfill = [:]
        defer {
            MerianMigrationPlan._v38LocalAudioBackfill = [:]
            MerianMigrationPlan._v38LocalContextBackfill = [:]
            MerianMigrationPlan._v38OfflineAudioBackfill = [:]
            MerianMigrationPlan._v38OfflineContextBackfill = [:]
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
            audioFilePath: "recording_abc.wav",
            observationContextJSON: "{\"freeText\":\"Yellow wings\"}"
        )
        context38.insert(localRecord)

        let offlineRecord = MerianSchemaV38.OfflineQueuedScan(
            localImagePaths: [],
            audioFilePath: "offline_recording.wav",
            observationContextJSON: "{\"freeText\":\"Near water\"}"
        )
        context38.insert(offlineRecord)
        try context38.save()

        let capturedLocalId = localRecord.id
        let capturedOfflineId = offlineRecord.id
        _ = container38

        // Step 2 — reopen with the full migration plan targeting V39 (CurrentSchema).
        let schema39 = Schema(versionedSchema: CurrentSchema.self)
        let config39 = ModelConfiguration(schema: schema39, url: url)
        let container39 = try ModelContainer(
            for: schema39,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config39]
        )

        // Step 3 — verify both models had their singular values backfilled into arrays.
        let context39 = ModelContext(container39)

        var localDescriptor = FetchDescriptor<LocalScanRecord>()
        localDescriptor.fetchLimit = 500
        let localScans = try context39.fetch(localDescriptor)
        let migratedLocal = localScans.first { $0.id == capturedLocalId }
        #expect(migratedLocal != nil, "LocalScanRecord must survive V38→V39 migration")
        #expect(
            migratedLocal?.audioFilePaths?.first == "recording_abc.wav",
            "audioFilePath must be backfilled into audioFilePaths[0]"
        )
        #expect(
            migratedLocal?.observationContextsJSON?.first == "{\"freeText\":\"Yellow wings\"}",
            "observationContextJSON must be backfilled into observationContextsJSON[0]"
        )

        var offlineDescriptor = FetchDescriptor<OfflineQueuedScan>()
        offlineDescriptor.fetchLimit = 500
        let offlineScans = try context39.fetch(offlineDescriptor)
        let migratedOffline = offlineScans.first { $0.id == capturedOfflineId }
        #expect(migratedOffline != nil, "OfflineQueuedScan must survive V38→V39 migration")
        #expect(
            migratedOffline?.audioFilePaths?.first == "offline_recording.wav",
            "OfflineQueuedScan.audioFilePath must be backfilled into audioFilePaths[0]"
        )
        #expect(
            migratedOffline?.observationContextsJSON?.first == "{\"freeText\":\"Near water\"}",
            "OfflineQueuedScan.observationContextJSON must be backfilled into observationContextsJSON[0]"
        )

        // Cleanup.
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-shm"))
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-wal"))
    }
}
