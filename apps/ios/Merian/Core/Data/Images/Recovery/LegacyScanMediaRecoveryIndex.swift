import Foundation
import SQLite3

struct LegacyScanMediaRecoveryRecord {
    let coverImagePath: String?
    let capturedMediaJSON: String?
}

enum LegacyScanMediaRecoveryStoreLocator {
    static func storeURLs(
        configuredStoreDirectory: URL,
        legacyApplicationSupportDirectory: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        var visitedDirectories = Set<String>()
        let storeDirectories = [configuredStoreDirectory, legacyApplicationSupportDirectory]
            .filter { visitedDirectories.insert($0.standardizedFileURL.path).inserted }

        return storeDirectories.flatMap { storeDirectory in
            let rescueRoot = storeDirectory.appendingPathComponent(
                "store-rescue",
                isDirectory: true
            )
            let archiveDirectories = (try? fileManager.contentsOfDirectory(
                at: rescueRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            return archiveDirectories
                .sorted { $0.path > $1.path }
                .map {
                    $0.appendingPathComponent("default.store", isDirectory: false)
                }
                .filter { fileManager.fileExists(atPath: $0.path) }
        }
    }
}

final class LegacyScanMediaRecoveryIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedRecords: [String: LegacyScanMediaRecoveryRecord]?

    var hasRecords: Bool {
        !records().isEmpty
    }

    func record(for scanID: String) -> LegacyScanMediaRecoveryRecord? {
        records()[scanID.lowercased()]
    }

    private func records() -> [String: LegacyScanMediaRecoveryRecord] {
        lock.withLock {
            if let cachedRecords {
                return cachedRecords
            }
            let loadedRecords = loadRecords()
            cachedRecords = loadedRecords
            return loadedRecords
        }
    }

    private func loadRecords(
        applicationSupportDirectory: URL = .applicationSupportDirectory,
        fileManager: FileManager = .default
    ) -> [String: LegacyScanMediaRecoveryRecord] {
        let configuredStoreDirectory = ModelStoreRecoveryCoordinator
            .defaultStoreURL()
            .deletingLastPathComponent()
        let storeURLs = LegacyScanMediaRecoveryStoreLocator.storeURLs(
            configuredStoreDirectory: configuredStoreDirectory,
            legacyApplicationSupportDirectory: applicationSupportDirectory,
            fileManager: fileManager
        )

        var recordsByID: [String: LegacyScanMediaRecoveryRecord] = [:]
        for storeURL in storeURLs {
            for (scanID, record) in readRecords(from: storeURL)
                where recordsByID[scanID] == nil {
                recordsByID[scanID] = record
            }
        }
        return recordsByID
    }

    private func readRecords(
        from storeURL: URL
    ) -> [String: LegacyScanMediaRecoveryRecord] {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            storeURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            if database != nil {
                sqlite3_close(database)
            }
            return [:]
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT ZID, ZCOVERIMAGEPATH, ZCAPTUREDMEDIAJSON
        FROM ZLOCALSCANRECORD
        WHERE ZID IS NOT NULL
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            query,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        var recordsByID: [String: LegacyScanMediaRecoveryRecord] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let scanID = stringValue(
                from: statement,
                column: 0
            )?.lowercased() else {
                continue
            }
            recordsByID[scanID] = LegacyScanMediaRecoveryRecord(
                coverImagePath: stringValue(from: statement, column: 1),
                capturedMediaJSON: stringValue(from: statement, column: 2)
            )
        }
        return recordsByID
    }

    private func stringValue(
        from statement: OpaquePointer,
        column: Int32
    ) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: text)
    }
}
