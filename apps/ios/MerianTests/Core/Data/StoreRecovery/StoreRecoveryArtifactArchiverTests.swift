import CoreData
import Foundation
@testable import Merian
import XCTest

final class StoreRecoveryArtifactArchiverTests: XCTestCase {
    func testQuarantinesStoreArtifacts() throws {
        let tempDirectory = try StoreRecoveryTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")

        try StoreRecoveryTestSupport.writeStoreArtifact(
            at: storeURL,
            contents: "store"
        )
        try StoreRecoveryTestSupport.writeStoreArtifact(
            at: shmURL,
            contents: "shm"
        )
        try StoreRecoveryTestSupport.writeStoreArtifact(
            at: walURL,
            contents: "wal"
        )

        let quarantineDirectory = try ModelStoreRecoveryCoordinator
            .quarantineStoreArtifacts(
                at: storeURL,
                for: StoreRecoveryTestSupport.sqliteCorruptionError()
            )

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: quarantineDirectory
                    .appendingPathComponent("default.store").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: quarantineDirectory
                    .appendingPathComponent("default.store-shm").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: quarantineDirectory
                    .appendingPathComponent("default.store-wal").path
            )
        )
    }

    func testRescueArchivesStoreArtifacts() throws {
        let tempDirectory = try StoreRecoveryTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
        let swiftDataError = NSError(
            domain: "SwiftData.SwiftDataError",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "SwiftData.SwiftDataError error 1."
            ]
        )

        try StoreRecoveryTestSupport.writeStoreArtifact(
            at: storeURL,
            contents: "store"
        )
        try StoreRecoveryTestSupport.writeStoreArtifact(
            at: shmURL,
            contents: "shm"
        )
        try StoreRecoveryTestSupport.writeStoreArtifact(
            at: walURL,
            contents: "wal"
        )

        let rescueDirectory = try ModelStoreRecoveryCoordinator
            .rescueStoreArtifactsAfterMigrationFailure(
                at: storeURL,
                for: swiftDataError,
                now: Date(timeIntervalSince1970: 1_788_271_200)
            )

        XCTAssertEqual(
            rescueDirectory.deletingLastPathComponent().lastPathComponent,
            "store-rescue"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rescueDirectory
                    .appendingPathComponent("default.store").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rescueDirectory
                    .appendingPathComponent("default.store-shm").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rescueDirectory
                    .appendingPathComponent("default.store-wal").path
            )
        )

        let manifest = try recoveryManifest(in: rescueDirectory)
        XCTAssertEqual(manifest.schemaVersion, 2)
        XCTAssertEqual(manifest.archiveReason, "legacy_migration_rescue")
        XCTAssertEqual(manifest.reasonDomain, "SwiftData.SwiftDataError")
        XCTAssertEqual(manifest.reasonCode, 1)
        XCTAssertEqual(
            manifest.movedArtifacts,
            ["default.store", "default.store-shm", "default.store-wal"]
        )
    }

    func testQuarantineWritesPIISafeRecoveryManifest() throws {
        let tempDirectory = try StoreRecoveryTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try StoreRecoveryTestSupport.writeStoreArtifact(
            at: storeURL,
            contents: "store"
        )
        let corruptionError = StoreRecoveryTestSupport.sqliteCorruptionError(
            description:
                "/private/var/mobile/default.store for person@example.invalid is malformed"
        )
        let privateFailureReason = "scan note text should stay private"
        let privateErrorDomain = "private.error.person@example.invalid"
        let error = NSError(
            domain: privateErrorDomain,
            code: corruptionError.code,
            userInfo: [
                NSLocalizedDescriptionKey: corruptionError.localizedDescription,
                NSLocalizedFailureReasonErrorKey: privateFailureReason
            ]
        )

        let quarantineDirectory = try ModelStoreRecoveryCoordinator
            .quarantineStoreArtifacts(
                at: storeURL,
                for: error,
                now: Date(timeIntervalSince1970: 1_788_271_200)
            )
        let manifestURL = quarantineDirectory.appendingPathComponent(
            "recovery-manifest.json"
        )
        let manifest = try recoveryManifest(in: quarantineDirectory)

        XCTAssertEqual(manifest.schemaVersion, 2)
        XCTAssertEqual(manifest.archiveReason, "corruption_quarantine")
        XCTAssertTrue(manifest.reasonDomain?.hasPrefix("sha256:") == true)
        XCTAssertEqual(manifest.reasonCode, 11)
        XCTAssertEqual(manifest.movedArtifacts, ["default.store"])
        XCTAssertTrue(manifest.reasonDescription?.hasPrefix("sha256:") == true)
        XCTAssertTrue(manifest.reasonFailureReason?.hasPrefix("sha256:") == true)

        let manifestText = try String(
            contentsOf: manifestURL,
            encoding: .utf8
        )
        XCTAssertFalse(manifestText.contains("/private/var/mobile"))
        XCTAssertFalse(manifestText.contains("person@example.invalid"))
        XCTAssertFalse(manifestText.contains(privateFailureReason))
        XCTAssertFalse(manifestText.contains(privateErrorDomain))
        XCTAssertFalse(manifestText.contains("Keychain"))
        XCTAssertFalse(manifestText.contains("Supabase"))
        XCTAssertFalse(manifestText.contains("currentUser"))
    }

    func testArchiveRollsBackAllArtifactsWhenMoveFailsAfterMutation() throws {
        let tempDirectory = try StoreRecoveryTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileManager = FileManager.default
        let storeURL = tempDirectory.appendingPathComponent("default.store")
        let artifactURLs = try makeStoreArtifacts(at: storeURL)
        var moveAttempt = 0
        let dependencies = StoreRecoveryArtifactArchiver.Dependencies(
            moveItem: { source, destination in
                moveAttempt += 1
                try fileManager.moveItem(at: source, to: destination)
                if moveAttempt == 2 {
                    throw InjectedArchiveFailure.move
                }
            },
            writeData: { data, destination in
                try data.write(to: destination, options: .atomic)
            }
        )

        XCTAssertThrowsError(
            try StoreRecoveryArtifactArchiver.archive(
                storeURL: storeURL,
                rootName: "test-archive",
                archiveReason: "test",
                error: nil,
                fileManager: fileManager,
                now: Date(timeIntervalSince1970: 1_788_271_200),
                dependencies: dependencies
            )
        )

        assertArtifactsWereRestored(artifactURLs, fileManager: fileManager)
        try assertArchiveRootIsEmpty(
            tempDirectory.appendingPathComponent("test-archive"),
            fileManager: fileManager
        )
    }

    func testArchiveRollsBackAllArtifactsWhenManifestWriteFails() throws {
        let tempDirectory = try StoreRecoveryTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileManager = FileManager.default
        let storeURL = tempDirectory.appendingPathComponent("default.store")
        let artifactURLs = try makeStoreArtifacts(at: storeURL)
        let dependencies = StoreRecoveryArtifactArchiver.Dependencies(
            moveItem: { source, destination in
                try fileManager.moveItem(at: source, to: destination)
            },
            writeData: { _, _ in
                throw InjectedArchiveFailure.manifest
            }
        )

        XCTAssertThrowsError(
            try StoreRecoveryArtifactArchiver.archive(
                storeURL: storeURL,
                rootName: "test-archive",
                archiveReason: "test",
                error: nil,
                fileManager: fileManager,
                now: Date(timeIntervalSince1970: 1_788_271_200),
                dependencies: dependencies
            )
        )

        assertArtifactsWereRestored(artifactURLs, fileManager: fileManager)
        try assertArchiveRootIsEmpty(
            tempDirectory.appendingPathComponent("test-archive"),
            fileManager: fileManager
        )
    }

    private enum InjectedArchiveFailure: Error {
        case manifest
        case move
    }

    private func makeStoreArtifacts(at storeURL: URL) throws -> [URL] {
        let artifactURLs = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]
        for (index, artifactURL) in artifactURLs.enumerated() {
            try StoreRecoveryTestSupport.writeStoreArtifact(
                at: artifactURL,
                contents: "artifact-\(index)"
            )
        }
        return artifactURLs
    }

    private func assertArtifactsWereRestored(
        _ artifactURLs: [URL],
        fileManager: FileManager,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (index, artifactURL) in artifactURLs.enumerated() {
            XCTAssertTrue(
                fileManager.fileExists(atPath: artifactURL.path),
                "Expected rollback to restore \(artifactURL.lastPathComponent)",
                file: file,
                line: line
            )
            XCTAssertEqual(
                try? String(contentsOf: artifactURL, encoding: .utf8),
                "artifact-\(index)",
                "Expected rollback to preserve \(artifactURL.lastPathComponent)",
                file: file,
                line: line
            )
        }
    }

    private func assertArchiveRootIsEmpty(
        _ archiveRoot: URL,
        fileManager: FileManager,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            try fileManager.contentsOfDirectory(atPath: archiveRoot.path),
            [],
            file: file,
            line: line
        )
    }

    private func recoveryManifest(
        in archiveDirectory: URL
    ) throws -> ModelStoreRecoveryManifest {
        let manifestURL = archiveDirectory.appendingPathComponent(
            "recovery-manifest.json"
        )
        return try JSONDecoder().decode(
            ModelStoreRecoveryManifest.self,
            from: Data(contentsOf: manifestURL)
        )
    }
}
