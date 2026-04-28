import XCTest
import CoreData
@testable import Merian

final class merianTests: XCTestCase {
    func testModelStoreRecoveryRejectsNonCorruptionFailures() {
        let migrationError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSPersistentStoreIncompatibleVersionHashError,
            userInfo: [NSLocalizedDescriptionKey: "Persistent store is incompatible with the current model version."]
        )

        XCTAssertFalse(ModelStoreRecoveryCoordinator.shouldAttemptRecovery(for: migrationError))
    }

    func testModelStoreRecoveryAcceptsSQLiteCorruptionFailures() {
        let corruptionError = NSError(
            domain: NSSQLiteErrorDomain,
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: "database disk image is malformed"]
        )

        XCTAssertTrue(ModelStoreRecoveryCoordinator.shouldAttemptRecovery(for: corruptionError))
    }

    func testModelStoreRecoveryQuarantinesStoreArtifacts() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, conformingTo: .directory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")

        try Data("store".utf8).write(to: storeURL)
        try Data("shm".utf8).write(to: shmURL)
        try Data("wal".utf8).write(to: walURL)

        let quarantineDirectory = try ModelStoreRecoveryCoordinator.quarantineStoreArtifacts(at: storeURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineDirectory.appendingPathComponent("default.store").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineDirectory.appendingPathComponent("default.store-shm").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineDirectory.appendingPathComponent("default.store-wal").path))
    }
}
