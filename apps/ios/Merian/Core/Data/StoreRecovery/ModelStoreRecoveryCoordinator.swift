import CoreData
import Foundation

/// Handles launch-time SwiftData store recovery without touching account identity.
///
/// Store recovery is intentionally narrow. It may quarantine damaged local SwiftData
/// files, but it must never clear Keychain, Supabase auth sessions, device identity,
/// or cloud ownership state.
enum ModelStoreRecoveryCoordinator {
    private static let sqliteCorruptionCodes: Set<Int> = [11, 26] // SQLITE_CORRUPT, SQLITE_NOTADB
    private static let unknownModelVersionErrorCode = 134_504
    private static let manifestFilename = "recovery-manifest.json"
    private static let corruptionPhrases = [
        "database disk image is malformed",
        "file is not a database",
        "file is encrypted or is not a database",
        "sqlite_corrupt",
        "sqlite_notadb",
        "malformed database schema",
        "corrupt",
        "cannot use staged migration with an unknown model version",
        "unknown model version"
    ]

    static func defaultStoreURL() -> URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    static func shouldAttemptRecovery(for error: Error) -> Bool {
        errorChain(from: error).contains { candidate in
            let nsError = candidate as NSError
            if nsError.domain == NSSQLiteErrorDomain, sqliteCorruptionCodes.contains(nsError.code) {
                return true
            }
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadCorruptFileError {
                return true
            }
            if nsError.domain == NSCocoaErrorDomain, nsError.code == unknownModelVersionErrorCode {
                return true
            }

            let normalizedText = [
                nsError.localizedDescription,
                nsError.userInfo[NSDebugDescriptionErrorKey] as? String,
                nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: "\n")

            return corruptionPhrases.contains { normalizedText.contains($0) }
        }
    }

    static func shouldQuarantineStore(
        for error: Error,
        storeURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        shouldAttemptRecovery(for: error) && hasStoreArtifacts(at: storeURL, fileManager: fileManager)
    }

    static func hasStoreArtifacts(at storeURL: URL, fileManager: FileManager = .default) -> Bool {
        !storeArtifacts(for: storeURL, fileManager: fileManager).isEmpty
    }

    @discardableResult
    static func quarantineStoreArtifacts(
        at storeURL: URL,
        for error: Error? = nil,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> URL {
        let artifacts = storeArtifacts(for: storeURL, fileManager: fileManager)
        guard !artifacts.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }

        let quarantineRoot = storeURL.deletingLastPathComponent().appending(path: "store-quarantine", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: quarantineRoot, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let quarantineDirectory = quarantineRoot.appending(path: "\(timestamp)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: quarantineDirectory, withIntermediateDirectories: false)

        for artifact in artifacts {
            let destination = quarantineDirectory.appending(path: artifact.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: artifact, to: destination)
        }

        writeManifest(
            to: quarantineDirectory,
            movedArtifacts: artifacts.map(\.lastPathComponent),
            error: error,
            now: now,
            fileManager: fileManager
        )

        return quarantineDirectory
    }

    private static func writeManifest(
        to quarantineDirectory: URL,
        movedArtifacts: [String],
        error: Error?,
        now: Date,
        fileManager: FileManager
    ) {
        let nsError = error.map { $0 as NSError }
        let manifest = ModelStoreRecoveryManifest(
            timestamp: ISO8601DateFormatter().string(from: now),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            reasonDomain: nsError?.domain,
            reasonCode: nsError?.code,
            reasonDescription: nsError?.localizedDescription,
            reasonFailureReason: nsError?.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
            movedArtifacts: movedArtifacts.sorted()
        )

        do {
            let data = try JSONEncoder.prettySorted.encode(manifest)
            let url = quarantineDirectory.appending(path: manifestFilename)
            fileManager.createFile(atPath: url.path, contents: data)
        } catch {
            MerianLog.general.error("Failed to write store recovery manifest: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static func storeArtifacts(for storeURL: URL, fileManager: FileManager) -> [URL] {
        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func errorChain(from rootError: Error) -> [Error] {
        var collected: [Error] = []
        var stack: [Error] = [rootError]

        while let next = stack.popLast() {
            collected.append(next)
            let nsError = next as NSError

            if let nestedError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                stack.append(nestedError)
            }
            if let nestedErrors = nsError.userInfo[NSDetailedErrorsKey] as? [NSError] {
                stack.append(contentsOf: nestedErrors)
            }
        }

        return collected
    }
}

struct ModelStoreRecoveryManifest: Codable, Equatable {
    let schemaVersion: Int
    let timestamp: String
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let reasonDomain: String?
    let reasonCode: Int?
    let reasonDescription: String?
    let reasonFailureReason: String?
    let movedArtifacts: [String]

    init(
        schemaVersion: Int = 1,
        timestamp: String,
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        reasonDomain: String?,
        reasonCode: Int?,
        reasonDescription: String?,
        reasonFailureReason: String?,
        movedArtifacts: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.timestamp = timestamp
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.reasonDomain = reasonDomain
        self.reasonCode = reasonCode
        self.reasonDescription = reasonDescription
        self.reasonFailureReason = reasonFailureReason
        self.movedArtifacts = movedArtifacts
    }
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
