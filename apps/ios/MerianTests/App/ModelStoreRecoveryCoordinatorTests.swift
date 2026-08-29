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

    func testDetectsEqualModelReferenceFailuresForTargetedRetry() {
        let equalModelReferenceError = NSError(
            domain: "app.merian.objc-exception",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "The current model reference and the next model reference cannot be equal.",
                NSLocalizedFailureReasonErrorKey: "NSInvalidArgumentException"
            ]
        )

        XCTAssertTrue(ModelStoreRecoveryCoordinator.isDuplicateVersionChecksumFailure(equalModelReferenceError))
        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.safeModeFallback(for: equalModelReferenceError).telemetryReason,
            "persistent_store_migration_failed"
        )
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
            "NSStoreModelVersionIdentifiers": NSSet(array: ["V45", "V49"])
        ]

        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.storedSchemaMajorVersion(from: metadata),
            49
        )
    }

    func testStoreMigrationHintOpensFreshStoresAsCurrentStore() {
        let currentSchemaMajor = CurrentSchema.versionIdentifier.major
        let hint = ModelStoreRecoveryCoordinator.migrationHint(
            storedSchemaMajorVersion: nil,
            hasStoreArtifacts: false,
            currentSchemaMajor: currentSchemaMajor
        )

        XCTAssertEqual(hint, .currentStore)
    }

    func testStoreMigrationHintOpensAlreadyCurrentStoresWithoutMigrationPlan() {
        let currentSchemaMajor = CurrentSchema.versionIdentifier.major
        let hint = ModelStoreRecoveryCoordinator.migrationHint(
            storedSchemaMajorVersion: currentSchemaMajor,
            hasStoreArtifacts: true,
            currentSchemaMajor: currentSchemaMajor
        )

        XCTAssertEqual(hint, .currentStore)
    }

    func testSourceIsolatedSchemasAreConsecutiveAndEndAtCurrentPredecessor() {
        let sourceVersions = ModelStoreRecoveryCoordinator.RecentSourceSchema.allCases.map(\.rawValue)

        XCTAssertEqual(sourceVersions.first, 42)
        XCTAssertEqual(sourceVersions.last, CurrentSchema.versionIdentifier.major - 1)
        XCTAssertEqual(sourceVersions, Array(42 ... (CurrentSchema.versionIdentifier.major - 1)))
    }

    func testStoreMigrationHintUsesRecentPlansForEverySourceIsolatedStore() {
        let currentSchemaMajor = CurrentSchema.versionIdentifier.major

        for source in ModelStoreRecoveryCoordinator.RecentSourceSchema.allCases {
            XCTAssertEqual(
                ModelStoreRecoveryCoordinator.migrationHint(
                    storedSchemaMajorVersion: source.rawValue,
                    hasStoreArtifacts: true,
                    currentSchemaMajor: currentSchemaMajor
                ),
                .recentSource(source)
            )
        }
    }

    func testStoreMigrationHintUsesFullPlanForUnknownOrOlderExistingStores() {
        let currentSchemaMajor = CurrentSchema.versionIdentifier.major
        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.migrationHint(
                storedSchemaMajorVersion: nil,
                hasStoreArtifacts: true,
                currentSchemaMajor: currentSchemaMajor
            ),
            .fullHistorical
        )
        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.migrationHint(
                storedSchemaMajorVersion: 43,
                hasStoreArtifacts: true,
                currentSchemaMajor: currentSchemaMajor
            ),
            .recentSource(.v43)
        )
        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.migrationHint(
                storedSchemaMajorVersion: 41,
                hasStoreArtifacts: true,
                currentSchemaMajor: currentSchemaMajor
            ),
            .fullHistorical
        )
    }

    func testStartupDiagnosticCapturesAttemptsAndRedactsPrivateText() throws {
        let currentSchemaMajor = CurrentSchema.versionIdentifier.major
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try writeStoreArtifact(at: storeURL, contents: "store")

        let decision = ModelStoreRecoveryCoordinator.StoreMigrationDecision(
            hasStoreArtifacts: true,
            storedSchemaMajorVersion: 48,
            hint: .recentSource(.v48)
        )
        var diagnostic = ModelStoreRecoveryCoordinator.makeStartupDiagnostic(
            storeURL: storeURL,
            currentSchemaMajor: currentSchemaMajor,
            migrationSchemas: "43,47,48,49,50",
            migrationStages: "43>49:C,48>49:C,49>50:L",
            decision: decision,
            now: Date(timeIntervalSince1970: 1_788_271_200)
        )
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSPersistentStoreIncompatibleVersionHashError,
            userInfo: [
                NSLocalizedDescriptionKey: "/private/var/mobile/default.store could not open",
                NSLocalizedFailureReasonErrorKey: "emre@example.com failed migration",
                NSDebugDescriptionErrorKey: "scan note text should stay private"
            ]
        )

        diagnostic.recordAttempt(name: "recent-v48-known-good", outcome: "failure", error: error)
        diagnostic.recordFinalOutcome("safe_mode", reason: "persistent_store_migration_failed")

        let text = try XCTUnwrap(ModelStoreRecoveryCoordinator.startupDiagnosticText(diagnostic))
        XCTAssertTrue(text.contains("\"currentSchemaMajor\" : \(currentSchemaMajor)"))
        XCTAssertTrue(text.contains(#""selectedStrategy" : "recent-source-v48""#))
        XCTAssertTrue(text.contains(#""descriptionFingerprint""#))
        XCTAssertTrue(text.contains(#""failureReasonFingerprint""#))
        XCTAssertTrue(text.contains(#""debugDescriptionFingerprint""#))
        XCTAssertFalse(text.contains("/private/var/mobile"))
        XCTAssertFalse(text.contains(tempDirectory.path))
        XCTAssertFalse(text.contains("emre@example.com"))
        XCTAssertFalse(text.contains("scan note text should stay private"))
        XCTAssertEqual(diagnostic.telemetryProperties["selected_strategy"], "recent-source-v48")
        XCTAssertEqual(diagnostic.telemetryProperties["attempts"], "recent-v48-known-good:failure")
        XCTAssertEqual(diagnostic.telemetryProperties["final_outcome"], "safe_mode")
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

    func testRescuesLegacyMigrationFailuresEvenWhenSwiftDataErrorIsGeneric() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try writeStoreArtifact(at: storeURL, contents: "store")
        let decision = ModelStoreRecoveryCoordinator.StoreMigrationDecision(
            hasStoreArtifacts: true,
            storedSchemaMajorVersion: 42,
            hint: .recentSource(.v42)
        )
        let swiftDataError = NSError(
            domain: "SwiftData.SwiftDataError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "SwiftData.SwiftDataError error 1."]
        )

        XCTAssertTrue(
            ModelStoreRecoveryCoordinator.shouldRescueStoreAfterMigrationFailure(
                for: swiftDataError,
                decision: decision,
                storeURL: storeURL
            )
        )
    }

    func testDoesNotRescueAlreadyCurrentStoreFailures() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try writeStoreArtifact(at: storeURL, contents: "store")
        let decision = ModelStoreRecoveryCoordinator.StoreMigrationDecision(
            hasStoreArtifacts: true,
            storedSchemaMajorVersion: 49,
            hint: .currentStore
        )
        let genericError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [NSLocalizedDescriptionKey: "The file could not be opened because permission was denied."]
        )

        XCTAssertFalse(
            ModelStoreRecoveryCoordinator.shouldRescueStoreAfterMigrationFailure(
                for: genericError,
                decision: decision,
                storeURL: storeURL
            )
        )
    }

    func testDoesNotRescueCorruptionFailuresBeforeQuarantinePath() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try writeStoreArtifact(at: storeURL, contents: "store")
        let decision = ModelStoreRecoveryCoordinator.StoreMigrationDecision(
            hasStoreArtifacts: true,
            storedSchemaMajorVersion: 42,
            hint: .recentSource(.v42)
        )

        XCTAssertFalse(
            ModelStoreRecoveryCoordinator.shouldRescueStoreAfterMigrationFailure(
                for: sqliteCorruptionError(),
                decision: decision,
                storeURL: storeURL
            )
        )
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

    func testRescueArchivesStoreArtifacts() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
        let swiftDataError = NSError(
            domain: "SwiftData.SwiftDataError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "SwiftData.SwiftDataError error 1."]
        )

        try writeStoreArtifact(at: storeURL, contents: "store")
        try writeStoreArtifact(at: shmURL, contents: "shm")
        try writeStoreArtifact(at: walURL, contents: "wal")

        let rescueDirectory = try ModelStoreRecoveryCoordinator.rescueStoreArtifactsAfterMigrationFailure(
            at: storeURL,
            for: swiftDataError,
            now: Date(timeIntervalSince1970: 1_788_271_200)
        )

        XCTAssertEqual(rescueDirectory.deletingLastPathComponent().lastPathComponent, "store-rescue")
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rescueDirectory.appendingPathComponent("default.store").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rescueDirectory.appendingPathComponent("default.store-shm").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rescueDirectory.appendingPathComponent("default.store-wal").path
            )
        )

        let manifestURL = rescueDirectory.appendingPathComponent("recovery-manifest.json")
        let manifest = try JSONDecoder().decode(
            ModelStoreRecoveryManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        XCTAssertEqual(manifest.schemaVersion, 2)
        XCTAssertEqual(manifest.archiveReason, "legacy_migration_rescue")
        XCTAssertEqual(manifest.reasonDomain, "SwiftData.SwiftDataError")
        XCTAssertEqual(manifest.reasonCode, 1)
        XCTAssertEqual(manifest.movedArtifacts, ["default.store", "default.store-shm", "default.store-wal"])
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

        XCTAssertEqual(manifest.schemaVersion, 2)
        XCTAssertEqual(manifest.archiveReason, "corruption_quarantine")
        XCTAssertEqual(manifest.reasonDomain, NSSQLiteErrorDomain)
        XCTAssertEqual(manifest.reasonCode, 11)
        XCTAssertEqual(manifest.movedArtifacts, ["default.store"])

        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        XCTAssertFalse(manifestText.contains("Keychain"))
        XCTAssertFalse(manifestText.contains("Supabase"))
        XCTAssertFalse(manifestText.contains("currentUser"))
    }

    func testStartupDiagnosticCapturesMigrationRescueState() throws {
        let currentSchemaMajor = CurrentSchema.versionIdentifier.major
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try writeStoreArtifact(at: storeURL, contents: "store")
        let decision = ModelStoreRecoveryCoordinator.StoreMigrationDecision(
            hasStoreArtifacts: true,
            storedSchemaMajorVersion: 42,
            hint: .recentSource(.v42)
        )
        var diagnostic = ModelStoreRecoveryCoordinator.makeStartupDiagnostic(
            storeURL: storeURL,
            currentSchemaMajor: currentSchemaMajor,
            migrationSchemas: "42,49,50",
            migrationStages: "42>49:C,49>50:L",
            decision: decision,
            now: Date(timeIntervalSince1970: 1_788_271_200)
        )

        diagnostic.recordFinalOutcome(
            "recovered",
            reason: "legacy_store_rescued",
            rescueAttempted: true,
            rescuePerformed: true
        )

        XCTAssertEqual(diagnostic.telemetryProperties["diagnostic_schema"], "2")
        XCTAssertEqual(diagnostic.telemetryProperties["final_reason"], "legacy_store_rescued")
        XCTAssertEqual(diagnostic.telemetryProperties["rescue_attempted"], "true")
        XCTAssertEqual(diagnostic.telemetryProperties["rescue_performed"], "true")
        let text = try XCTUnwrap(ModelStoreRecoveryCoordinator.startupDiagnosticText(diagnostic))
        XCTAssertTrue(text.contains(#""rescueAttempted" : true"#))
        XCTAssertTrue(text.contains(#""rescuePerformed" : true"#))
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
