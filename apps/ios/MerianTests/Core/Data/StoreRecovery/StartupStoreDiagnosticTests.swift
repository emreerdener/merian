import CoreData
import Foundation
@testable import Merian
import XCTest

final class StartupStoreDiagnosticTests: XCTestCase {
    func testFreshStoreDiagnosticDoesNotReportMetadataReadFailure() throws {
        let currentSchemaMajor = CurrentSchema.versionIdentifier.major
        let tempDirectory = try StoreRecoveryTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        let decision = ModelStoreRecoveryCoordinator.StoreMigrationDecision(
            hasStoreArtifacts: false,
            storedSchemaMajorVersion: nil,
            hint: .currentStore
        )
        let diagnostic = ModelStoreRecoveryCoordinator.makeStartupDiagnostic(
            storeURL: storeURL,
            currentSchemaMajor: currentSchemaMajor,
            migrationSchemas: "50,51",
            migrationStages: "50>51:C",
            decision: decision
        )

        XCTAssertFalse(diagnostic.store.hasArtifacts)
        XCTAssertTrue(diagnostic.store.artifacts.isEmpty)
        XCTAssertNil(diagnostic.store.metadataReadError)
    }

    func testStartupDiagnosticCapturesAttemptsAndRedactsPrivateText() throws {
        let currentSchemaMajor = CurrentSchema.versionIdentifier.major
        let tempDirectory = try StoreRecoveryTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try StoreRecoveryTestSupport.writeStoreArtifact(
            at: storeURL,
            contents: "store"
        )

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
        let privateErrorDomain = "private.error.person@example.invalid"
        let error = NSError(
            domain: privateErrorDomain,
            code: NSPersistentStoreIncompatibleVersionHashError,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "/private/var/mobile/default.store could not open",
                NSLocalizedFailureReasonErrorKey:
                    "person@example.invalid failed migration",
                NSDebugDescriptionErrorKey:
                    "scan note text should stay private"
            ]
        )

        diagnostic.recordAttempt(
            name: "recent-v48-known-good",
            outcome: "failure",
            error: error
        )
        diagnostic.recordFinalOutcome(
            "safe_mode",
            reason: "persistent_store_migration_failed"
        )

        let text = try XCTUnwrap(
            ModelStoreRecoveryCoordinator.startupDiagnosticText(diagnostic)
        )
        XCTAssertTrue(
            text.contains("\"currentSchemaMajor\" : \(currentSchemaMajor)")
        )
        XCTAssertTrue(
            text.contains(#""selectedStrategy" : "recent-source-v48""#)
        )
        XCTAssertTrue(text.contains(#""descriptionFingerprint""#))
        XCTAssertTrue(text.contains(#""failureReasonFingerprint""#))
        XCTAssertTrue(text.contains(#""debugDescriptionFingerprint""#))
        XCTAssertFalse(text.contains(privateErrorDomain))
        XCTAssertFalse(text.contains("/private/var/mobile"))
        XCTAssertFalse(text.contains(tempDirectory.path))
        XCTAssertFalse(text.contains("person@example.invalid"))
        XCTAssertFalse(text.contains("scan note text should stay private"))
        let errorSummary = try XCTUnwrap(
            diagnostic.attempts.first?.errorSummaries.first
        )
        XCTAssertTrue(errorSummary.domain.hasPrefix("sha256:"))
        XCTAssertFalse(
            diagnostic.telemetryProperties["first_error"]?.contains(
                privateErrorDomain
            ) == true
        )
        XCTAssertEqual(
            diagnostic.telemetryProperties["selected_strategy"],
            "recent-source-v48"
        )
        XCTAssertEqual(
            diagnostic.telemetryProperties["attempts"],
            "recent-v48-known-good:failure"
        )
        XCTAssertEqual(
            diagnostic.telemetryProperties["final_outcome"],
            "safe_mode"
        )
    }

    func testStoreMetadataStringsAreFingerprintedBeforeDiagnosticsPersist() throws {
        let tempDirectory = try StoreRecoveryTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        let privateIdentifier = "PrivateID"
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["V51", privateIdentifier]
        let coordinator = NSPersistentStoreCoordinator(
            managedObjectModel: model
        )
        let store = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL
        )
        try coordinator.remove(store)

        let decision = ModelStoreRecoveryCoordinator.migrationDecision(
            at: storeURL,
            currentSchemaMajor: 51
        )
        let diagnostic = ModelStoreRecoveryCoordinator.makeStartupDiagnostic(
            storeURL: storeURL,
            currentSchemaMajor: 51,
            migrationSchemas: "50,51",
            migrationStages: "50>51:C",
            decision: decision
        )
        let text = try XCTUnwrap(
            ModelStoreRecoveryCoordinator.startupDiagnosticText(diagnostic)
        )

        XCTAssertEqual(diagnostic.store.storedSchemaMajorVersion, 51)
        XCTAssertFalse(diagnostic.store.modelVersionIdentifiers.isEmpty)
        XCTAssertTrue(
            diagnostic.store.modelVersionIdentifiers.allSatisfy {
                $0.hasPrefix("sha256:")
            }
        )
        XCTAssertTrue(
            diagnostic.store.modelVersionIdentifiers.contains(
                StoreRecoveryPrivacyPolicy.sanitizedMetadataString(
                    privateIdentifier
                )
            )
        )
        XCTAssertTrue(
            diagnostic.store.metadataFingerprints.keys.allSatisfy {
                $0.hasPrefix("sha256:")
            }
        )
        XCTAssertFalse(text.contains(privateIdentifier))
        XCTAssertFalse(
            diagnostic.telemetryProperties.values.contains { value in
                value.contains(privateIdentifier)
            }
        )
    }

    func testStartupDiagnosticCapturesMigrationRescueState() throws {
        let currentSchemaMajor = CurrentSchema.versionIdentifier.major
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

        XCTAssertEqual(
            diagnostic.telemetryProperties["diagnostic_schema"],
            "2"
        )
        XCTAssertEqual(
            diagnostic.telemetryProperties["final_reason"],
            "legacy_store_rescued"
        )
        XCTAssertEqual(
            diagnostic.telemetryProperties["rescue_attempted"],
            "true"
        )
        XCTAssertEqual(
            diagnostic.telemetryProperties["rescue_performed"],
            "true"
        )
        let text = try XCTUnwrap(
            ModelStoreRecoveryCoordinator.startupDiagnosticText(diagnostic)
        )
        XCTAssertTrue(text.contains(#""rescueAttempted" : true"#))
        XCTAssertTrue(text.contains(#""rescuePerformed" : true"#))
    }
}
