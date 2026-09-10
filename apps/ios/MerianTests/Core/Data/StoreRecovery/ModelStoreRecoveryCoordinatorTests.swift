import CoreData
import Foundation
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
        XCTAssertEqual(
            outcome.telemetryEvent?.reason,
            "persistent_store_unavailable"
        )
    }

    func testRejectsNonCorruptionFailures() {
        let migrationError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSPersistentStoreIncompatibleVersionHashError,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Persistent store is incompatible with the current model version."
            ]
        )

        XCTAssertFalse(
            ModelStoreRecoveryCoordinator.shouldAttemptRecovery(
                for: migrationError
            )
        )
    }

    func testMigrationFailureUsesUpgradeSafeModeDiagnostics() {
        let migrationError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSPersistentStoreIncompatibleVersionHashError,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Persistent store is incompatible with the current model version."
            ]
        )

        let fallback = ModelStoreRecoveryCoordinator.safeModeFallback(
            for: migrationError
        )

        XCTAssertTrue(fallback.message.contains("could not finish upgrading"))
        XCTAssertEqual(
            fallback.telemetryReason,
            "persistent_store_migration_failed"
        )
    }

    func testNestedMigrationFailureUsesUpgradeSafeModeDiagnostics() {
        let underlying = NSError(
            domain: NSCocoaErrorDomain,
            code: NSPersistentStoreIncompatibleVersionHashError,
            userInfo: [
                NSLocalizedFailureReasonErrorKey:
                    "Cannot migrate store to the current model version."
            ]
        )
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadUnknownError,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )

        let fallback = ModelStoreRecoveryCoordinator.safeModeFallback(
            for: wrapped
        )

        XCTAssertEqual(
            fallback.telemetryReason,
            "persistent_store_migration_failed"
        )
    }

    func testDuplicateVersionChecksumFailureUsesUpgradeSafeModeDiagnostics() {
        let duplicateChecksumError = NSError(
            domain: "app.merian.model-container",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Duplicate version checksums across stages detected."
            ]
        )

        let fallback = ModelStoreRecoveryCoordinator.safeModeFallback(
            for: duplicateChecksumError
        )

        XCTAssertTrue(fallback.message.contains("could not finish upgrading"))
        XCTAssertEqual(
            fallback.telemetryReason,
            "persistent_store_migration_failed"
        )
    }

    func testDetectsDuplicateVersionChecksumFailuresForTargetedRetry() {
        let duplicateChecksumError = NSError(
            domain: "app.merian.model-container",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Duplicate version checksums across stages detected."
            ]
        )

        XCTAssertTrue(
            ModelStoreRecoveryCoordinator.isDuplicateVersionChecksumFailure(
                duplicateChecksumError
            )
        )
    }

    func testDetectsEqualModelReferenceFailuresForTargetedRetry() {
        let equalModelReferenceError = NSError(
            domain: "app.merian.objc-exception",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The current model reference and the next model reference cannot be equal.",
                NSLocalizedFailureReasonErrorKey: "NSInvalidArgumentException"
            ]
        )

        XCTAssertTrue(
            ModelStoreRecoveryCoordinator.isDuplicateVersionChecksumFailure(
                equalModelReferenceError
            )
        )
        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.safeModeFallback(
                for: equalModelReferenceError
            ).telemetryReason,
            "persistent_store_migration_failed"
        )
    }

    func testReadsSchemaMajorVersionFromStoreMetadataIdentifiers() {
        let metadata: [String: Any] = [
            "NSStoreModelVersionIdentifiers": ["MerianSchemaV48"]
        ]

        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.storedSchemaMajorVersion(
                from: metadata
            ),
            48
        )
    }

    func testReadsSchemaMajorVersionFromSwiftDataVersionIdentifierText() {
        let metadata: [String: Any] = [
            "NSStoreModelVersionIdentifiers": ["Schema.Version(47, 0, 0)"]
        ]

        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.storedSchemaMajorVersion(
                from: metadata
            ),
            47
        )
    }

    func testReadsHighestSchemaMajorVersionFromNestedMetadataIdentifiers() {
        let metadata: [String: Any] = [
            "NSStoreModelVersionIdentifiers": NSSet(array: ["V45", "V49"])
        ]

        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.storedSchemaMajorVersion(
                from: metadata
            ),
            49
        )
    }

    func testRecognizesReleasedActiveV50ModelChecksum() {
        let metadata: [String: Any] = [
            "NSStoreModelVersionIdentifiers": ["50.0.0"],
            "NSStoreModelVersionChecksumKey":
                "+dx/dTSCWpD8SHFdhzJkUjXCtRV172JY0C1pwGsl4z8="
        ]

        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.v50StoreVariant(from: metadata),
            .releasedActive
        )
    }

    func testRecognizesFrozenSnapshotV50ModelChecksum() {
        let metadata: [String: Any] = [
            "NSStoreModelVersionIdentifiers": ["50.0.0"],
            "NSStoreModelVersionChecksumKey":
                "zwOw+VMIYDnV2lZqCjKds6BvDT0Tndh6YCc0XmatW0c="
        ]

        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.v50StoreVariant(from: metadata),
            .frozenSnapshot
        )
    }

    func testRejectsUnknownV50ModelChecksum() {
        let metadata: [String: Any] = [
            "NSStoreModelVersionIdentifiers": ["50.0.0"],
            "NSStoreModelVersionChecksumKey": "unrecognized-v50-model"
        ]

        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.v50StoreVariant(from: metadata),
            .unknown
        )
    }

    func testReleasedActiveV50StrategyNamesTheSelectedGraph() {
        let decision = ModelStoreRecoveryCoordinator.StoreMigrationDecision(
            hasStoreArtifacts: true,
            storedSchemaMajorVersion: 50,
            hint: .recentSource(.v50),
            v50StoreVariant: .releasedActive
        )

        XCTAssertEqual(
            decision.strategyDescription,
            "recent-source-v50-released-active"
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

    func testRecoveryStoreURLMatchesSwiftDataAutomaticConfiguration() {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelStoreRecoveryCoordinator
            .productionStoreConfiguration(for: schema)

        XCTAssertEqual(
            ModelStoreRecoveryCoordinator.defaultStoreURL(),
            configuration.url
        )
        XCTAssertEqual(configuration.url.lastPathComponent, "default.store")
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
        let sourceVersions = ModelStoreRecoveryCoordinator.RecentSourceSchema
            .allCases.map(\.rawValue)

        XCTAssertEqual(sourceVersions.first, 42)
        XCTAssertEqual(
            sourceVersions.last,
            CurrentSchema.versionIdentifier.major - 1
        )
        XCTAssertEqual(
            sourceVersions,
            Array(42 ... (CurrentSchema.versionIdentifier.major - 1))
        )
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

    func testGenericFailureUsesPersistentUnavailableSafeModeDiagnostics() {
        let genericError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The file could not be opened because permission was denied."
            ]
        )

        let fallback = ModelStoreRecoveryCoordinator.safeModeFallback(
            for: genericError
        )

        XCTAssertTrue(
            fallback.message.contains("persistent store failed to open")
        )
        XCTAssertEqual(
            fallback.telemetryReason,
            "persistent_store_unavailable"
        )
    }

    func testAcceptsSQLiteCorruptionFailures() {
        let corruptionError = StoreRecoveryTestSupport.sqliteCorruptionError()

        XCTAssertTrue(
            ModelStoreRecoveryCoordinator.shouldAttemptRecovery(
                for: corruptionError
            )
        )
    }

    func testDoesNotQuarantineGenericFailuresEvenWithExistingStore() throws {
        let tempDirectory = try StoreRecoveryTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try StoreRecoveryTestSupport.writeStoreArtifact(
            at: storeURL,
            contents: "store"
        )
        let genericError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The file could not be opened because permission was denied."
            ]
        )

        XCTAssertFalse(
            ModelStoreRecoveryCoordinator.shouldQuarantineStore(
                for: genericError,
                storeURL: storeURL
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testRescuesLegacyMigrationFailuresEvenWhenSwiftDataErrorIsGeneric() throws {
        let tempDirectory = try StoreRecoveryTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try StoreRecoveryTestSupport.writeStoreArtifact(
            at: storeURL,
            contents: "store"
        )
        let decision = ModelStoreRecoveryCoordinator.StoreMigrationDecision(
            hasStoreArtifacts: true,
            storedSchemaMajorVersion: 42,
            hint: .recentSource(.v42)
        )
        let swiftDataError = NSError(
            domain: "SwiftData.SwiftDataError",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "SwiftData.SwiftDataError error 1."
            ]
        )

        XCTAssertTrue(
            ModelStoreRecoveryCoordinator
                .shouldRescueStoreAfterMigrationFailure(
                    for: swiftDataError,
                    decision: decision,
                    storeURL: storeURL
                )
        )
    }

    func testDoesNotRescueAlreadyCurrentStoreFailures() throws {
        let tempDirectory = try StoreRecoveryTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try StoreRecoveryTestSupport.writeStoreArtifact(
            at: storeURL,
            contents: "store"
        )
        let decision = ModelStoreRecoveryCoordinator.StoreMigrationDecision(
            hasStoreArtifacts: true,
            storedSchemaMajorVersion: 49,
            hint: .currentStore
        )
        let genericError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The file could not be opened because permission was denied."
            ]
        )

        XCTAssertFalse(
            ModelStoreRecoveryCoordinator
                .shouldRescueStoreAfterMigrationFailure(
                    for: genericError,
                    decision: decision,
                    storeURL: storeURL
                )
        )
    }

    func testDoesNotRescueCorruptionFailuresBeforeQuarantinePath() throws {
        let tempDirectory = try StoreRecoveryTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try StoreRecoveryTestSupport.writeStoreArtifact(
            at: storeURL,
            contents: "store"
        )
        let decision = ModelStoreRecoveryCoordinator.StoreMigrationDecision(
            hasStoreArtifacts: true,
            storedSchemaMajorVersion: 42,
            hint: .recentSource(.v42)
        )

        XCTAssertFalse(
            ModelStoreRecoveryCoordinator
                .shouldRescueStoreAfterMigrationFailure(
                    for: StoreRecoveryTestSupport.sqliteCorruptionError(),
                    decision: decision,
                    storeURL: storeURL
                )
        )
    }

    func testQuarantineRequiresStoreArtifacts() throws {
        let tempDirectory = try StoreRecoveryTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")

        XCTAssertFalse(
            ModelStoreRecoveryCoordinator.shouldQuarantineStore(
                for: StoreRecoveryTestSupport.sqliteCorruptionError(),
                storeURL: storeURL
            )
        )
    }

    func testQuarantinesConfirmedCorruptionWithExistingStore() throws {
        let tempDirectory = try StoreRecoveryTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try StoreRecoveryTestSupport.writeStoreArtifact(
            at: storeURL,
            contents: "store"
        )

        XCTAssertTrue(
            ModelStoreRecoveryCoordinator.shouldQuarantineStore(
                for: StoreRecoveryTestSupport.sqliteCorruptionError(),
                storeURL: storeURL
            )
        )
    }
}
