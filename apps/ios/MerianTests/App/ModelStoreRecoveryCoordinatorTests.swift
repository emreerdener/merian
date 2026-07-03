import CoreData
@testable import Merian
import XCTest

final class ModelStoreRecoveryCoordinatorTests: XCTestCase {
    func testRejectsNonCorruptionFailures() {
        let migrationError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSPersistentStoreIncompatibleVersionHashError,
            userInfo: [NSLocalizedDescriptionKey: "Persistent store is incompatible with the current model version."]
        )

        XCTAssertFalse(ModelStoreRecoveryCoordinator.shouldAttemptRecovery(for: migrationError))
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
