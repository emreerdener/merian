import CoreData
import Foundation

enum StoreRecoveryTestSupport {
    static func makeTempDirectory() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, conformingTo: .directory)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        return tempDirectory
    }

    static func writeStoreArtifact(at url: URL, contents: String) throws {
        try Data(contents.utf8).write(to: url)
    }

    static func sqliteCorruptionError(
        description: String = "database disk image is malformed"
    ) -> NSError {
        NSError(
            domain: NSSQLiteErrorDomain,
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}
