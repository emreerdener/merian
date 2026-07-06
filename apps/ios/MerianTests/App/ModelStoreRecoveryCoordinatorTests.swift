import CoreData
@testable import Merian
import SwiftData
import XCTest

final class ModelStoreRecoveryCoordinatorTests: XCTestCase {
    func testFallbackInMemoryBootstrapMarksSafeMode() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LocalScanRecord.self,
            ScanCollection.self,
            OfflineQueuedScan.self,
            configurations: configuration
        )

        let outcome = MerianApp.fallbackInMemoryBootstrap(
            reason: "Unit safe mode",
            makeInMemoryContainer: { container }
        )

        XCTAssertNotNil(outcome.container)
        XCTAssertEqual(outcome.startupStoreState, .safeMode)
        XCTAssertEqual(outcome.startupNotice?.title, "Safe Mode Enabled")
        XCTAssertEqual(outcome.startupNotice?.message, "Unit safe mode")
        XCTAssertEqual(outcome.telemetryEvent?.outcome, "safe_mode")
        XCTAssertEqual(outcome.telemetryEvent?.reason, "persistent_store_unavailable")
    }

    func testRejectsNonCorruptionFailures() {
        let migrationError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSPersistentStoreIncompatibleVersionHashError,
            userInfo: [NSLocalizedDescriptionKey: "Persistent store is incompatible with the current model version."]
        )

        XCTAssertFalse(ModelStoreRecoveryCoordinator.shouldAttemptRecovery(for: migrationError))
    }

    func testMigrationFailureUsesUpgradeSafeModeDiagnostics() {
        let migrationError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSPersistentStoreIncompatibleVersionHashError,
            userInfo: [NSLocalizedDescriptionKey: "Persistent store is incompatible with the current model version."]
        )

        let fallback = ModelStoreRecoveryCoordinator.safeModeFallback(for: migrationError)

        XCTAssertTrue(fallback.message.contains("could not finish upgrading"))
        XCTAssertEqual(fallback.telemetryReason, "persistent_store_migration_failed")
    }

    func testNestedMigrationFailureUsesUpgradeSafeModeDiagnostics() {
        let underlying = NSError(
            domain: NSCocoaErrorDomain,
            code: NSPersistentStoreIncompatibleVersionHashError,
            userInfo: [NSLocalizedFailureReasonErrorKey: "Cannot migrate store to the current model version."]
        )
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadUnknownError,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )

        let fallback = ModelStoreRecoveryCoordinator.safeModeFallback(for: wrapped)

        XCTAssertEqual(fallback.telemetryReason, "persistent_store_migration_failed")
    }

    func testDuplicateVersionChecksumFailureUsesUpgradeSafeModeDiagnostics() {
        let duplicateChecksumError = NSError(
            domain: "app.merian.model-container",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Duplicate version checksums across stages detected."]
        )

        let fallback = ModelStoreRecoveryCoordinator.safeModeFallback(for: duplicateChecksumError)

        XCTAssertTrue(fallback.message.contains("could not finish upgrading"))
        XCTAssertEqual(fallback.telemetryReason, "persistent_store_migration_failed")
    }

    func testDetectsDuplicateVersionChecksumFailuresForTargetedRetry() {
        let duplicateChecksumError = NSError(
            domain: "app.merian.model-container",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Duplicate version checksums across stages detected."]
        )

        XCTAssertTrue(ModelStoreRecoveryCoordinator.isDuplicateVersionChecksumFailure(duplicateChecksumError))
    }

    func testReadsSchemaMajorVersionFromStoreMetadataIdentifiers() {
        let metadata: [String: Any] = [
            "NSStoreModelVersionIdentifiers": ["MerianSchemaV48"]
        ]

        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.storedSchemaMajorVersion(from: metadata),
            48
        )
    }

    func testReadsSchemaMajorVersionFromSwiftDataVersionIdentifierText() {
        let metadata: [String: Any] = [
            "NSStoreModelVersionIdentifiers": ["Schema.Version(47, 0, 0)"]
        ]

        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.storedSchemaMajorVersion(from: metadata),
            47
        )
    }

    func testReadsHighestSchemaMajorVersionFromNestedMetadataIdentifiers() {
        let metadata: [String: Any] = [
            "NSStoreModelVersionIdentifiers": NSSet(array: ["V45", "V48"])
        ]

        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.storedSchemaMajorVersion(from: metadata),
            48
        )
    }

    func testStoreMigrationHintOpensFreshStoresAsCurrentStore() {
        let hint = ModelStoreRecoveryCoordinator.migrationHint(
            storedSchemaMajorVersion: nil,
            hasStoreArtifacts: false,
            currentSchemaMajor: 48
        )

        XCTAssertEqual(hint, .currentStore)
    }

    func testStoreMigrationHintOpensAlreadyCurrentStoresWithoutMigrationPlan() {
        let hint = ModelStoreRecoveryCoordinator.migrationHint(
            storedSchemaMajorVersion: 48,
            hasStoreArtifacts: true,
            currentSchemaMajor: 48
        )

        XCTAssertEqual(hint, .currentStore)
    }

    func testStoreMigrationHintUsesRecentPlansForRecentSourceStores() {
        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.migrationHint(
                storedSchemaMajorVersion: 44,
                hasStoreArtifacts: true,
                currentSchemaMajor: 48
            ),
            .recentSource(44)
        )
        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.migrationHint(
                storedSchemaMajorVersion: 45,
                hasStoreArtifacts: true,
                currentSchemaMajor: 48
            ),
            .recentSource(45)
        )
        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.migrationHint(
                storedSchemaMajorVersion: 46,
                hasStoreArtifacts: true,
                currentSchemaMajor: 48
            ),
            .recentSource(46)
        )
        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.migrationHint(
                storedSchemaMajorVersion: 47,
                hasStoreArtifacts: true,
                currentSchemaMajor: 48
            ),
            .recentSource(47)
        )
    }

    func testStoreMigrationHintUsesFullPlanForUnknownOrOlderExistingStores() {
        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.migrationHint(
                storedSchemaMajorVersion: nil,
                hasStoreArtifacts: true,
                currentSchemaMajor: 48
            ),
            .fullHistorical
        )
        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.migrationHint(
                storedSchemaMajorVersion: 43,
                hasStoreArtifacts: true,
                currentSchemaMajor: 48
            ),
            .fullHistorical
        )
    }

    func testGenericFailureUsesPersistentUnavailableSafeModeDiagnostics() {
        let genericError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [NSLocalizedDescriptionKey: "The file could not be opened because permission was denied."]
        )

        let fallback = ModelStoreRecoveryCoordinator.safeModeFallback(for: genericError)

        XCTAssertTrue(fallback.message.contains("persistent store failed to open"))
        XCTAssertEqual(fallback.telemetryReason, "persistent_store_unavailable")
    }

    func testAcceptsSQLiteCorruptionFailures() {
        let corruptionError = sqliteCorruptionError()

        XCTAssertTrue(ModelStoreRecoveryCoordinator.shouldAttemptRecovery(for: corruptionError))
    }

    func testDoesNotQuarantineGenericFailuresEvenWithExistingStore() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try writeStoreArtifact(at: storeURL, contents: "store")

        let genericError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [NSLocalizedDescriptionKey: "The file could not be opened because permission was denied."]
        )

        XCTAssertFalse(
            ModelStoreRecoveryCoordinator.shouldQuarantineStore(for: genericError, storeURL: storeURL)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testQuarantineRequiresStoreArtifacts() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")

        XCTAssertFalse(
            ModelStoreRecoveryCoordinator.shouldQuarantineStore(
                for: sqliteCorruptionError(),
                storeURL: storeURL
            )
        )
    }

    func testQuarantinesConfirmedCorruptionWithExistingStore() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try writeStoreArtifact(at: storeURL, contents: "store")

        XCTAssertTrue(
            ModelStoreRecoveryCoordinator.shouldQuarantineStore(
                for: sqliteCorruptionError(),
                storeURL: storeURL
            )
        )
    }

    func testQuarantinesStoreArtifacts() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")

        try writeStoreArtifact(at: storeURL, contents: "store")
        try writeStoreArtifact(at: shmURL, contents: "shm")
        try writeStoreArtifact(at: walURL, contents: "wal")

        let quarantineDirectory = try ModelStoreRecoveryCoordinator.quarantineStoreArtifacts(
            at: storeURL,
            for: sqliteCorruptionError()
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: quarantineDirectory.appendingPathComponent("default.store").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: quarantineDirectory.appendingPathComponent("default.store-shm").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: quarantineDirectory.appendingPathComponent("default.store-wal").path
            )
        )
    }

    func testQuarantineWritesPIISafeRecoveryManifest() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try writeStoreArtifact(at: storeURL, contents: "store")

        let quarantineDirectory = try ModelStoreRecoveryCoordinator.quarantineStoreArtifacts(
            at: storeURL,
            for: sqliteCorruptionError(),
            now: Date(timeIntervalSince1970: 1_788_271_200)
        )
        let manifestURL = quarantineDirectory.appendingPathComponent("recovery-manifest.json")
        let manifest = try JSONDecoder().decode(
            ModelStoreRecoveryManifest.self,
            from: Data(contentsOf: manifestURL)
        )

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.reasonDomain, NSSQLiteErrorDomain)
        XCTAssertEqual(manifest.reasonCode, 11)
        XCTAssertEqual(manifest.movedArtifacts, ["default.store"])

        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        XCTAssertFalse(manifestText.contains("Keychain"))
        XCTAssertFalse(manifestText.contains("Supabase"))
        XCTAssertFalse(manifestText.contains("currentUser"))
    }

    func testRecoveryCoordinatorDoesNotReferenceAuthOrSessionManagers() throws {
        let source = try String(
            contentsOf: recoveryCoordinatorSourceURL(),
            encoding: .utf8
        )
        let forbiddenTokens = [
            "KeychainManager",
            "SupabaseManager",
            "PostHogManager.shared.reset",
            "signOut(",
            "initializeGhostSession",
            "currentUser"
        ]
        let violations = forbiddenTokens.filter { source.contains($0) }

        XCTAssertTrue(
            violations.isEmpty,
            "Store recovery must remain isolated from auth/session state. Violations: \(violations.joined(separator: ", "))"
        )
    }

    private func makeTempDirectory() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            conformingTo: .directory
        )
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        return tempDirectory
    }

    private func writeStoreArtifact(at url: URL, contents: String) throws {
        try Data(contents.utf8).write(to: url)
    }

    private func recoveryCoordinatorSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Merian")
            .appendingPathComponent("Core")
            .appendingPathComponent("Data")
            .appendingPathComponent("StoreRecovery")
            .appendingPathComponent("ModelStoreRecoveryCoordinator.swift")
    }

    private func sqliteCorruptionError() -> NSError {
        NSError(
            domain: NSSQLiteErrorDomain,
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: "database disk image is malformed"]
        )
    }
}
