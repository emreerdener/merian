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

    /// Simulates upgrading from V30 to V31 on-disk — verifies that adding
    /// `isFlagged` (lightweight migration, no custom stage) does not crash during
    /// iOS 26 migration plan validation.
    @Test func migrationFromV30ToV31DoesNotCrash() throws {
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

        // Step 2 — reopen with the full migration plan targeting the current schema (V31).
        let schema31 = Schema(versionedSchema: CurrentSchema.self)
        let config31 = ModelConfiguration(schema: schema31, url: url)
        _ = try ModelContainer(
            for: schema31,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config31]
        )

        // Clean up the temp file.
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-shm"))
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-wal"))
    }
}
