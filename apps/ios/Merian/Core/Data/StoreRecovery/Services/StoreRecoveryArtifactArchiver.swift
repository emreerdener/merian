import Foundation

extension ModelStoreRecoveryCoordinator {
    static func hasStoreArtifacts(
        at storeURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        !StoreRecoveryArtifactArchiver.artifacts(
            for: storeURL,
            fileManager: fileManager
        ).isEmpty
    }

    @discardableResult
    static func quarantineStoreArtifacts(
        at storeURL: URL,
        for error: Error? = nil,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> URL {
        try StoreRecoveryArtifactArchiver.archive(
            storeURL: storeURL,
            rootName: "store-quarantine",
            archiveReason: "corruption_quarantine",
            error: error,
            fileManager: fileManager,
            now: now
        )
    }

    @discardableResult
    static func rescueStoreArtifactsAfterMigrationFailure(
        at storeURL: URL,
        for error: Error? = nil,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> URL {
        try StoreRecoveryArtifactArchiver.archive(
            storeURL: storeURL,
            rootName: "store-rescue",
            archiveReason: "legacy_migration_rescue",
            error: error,
            fileManager: fileManager,
            now: now
        )
    }
}

enum StoreRecoveryArtifactArchiver {
    struct Dependencies {
        let moveItem: (URL, URL) throws -> Void
        let writeData: (Data, URL) throws -> Void

        static func live(fileManager: FileManager) -> Self {
            Self(
                moveItem: { source, destination in
                    try fileManager.moveItem(
                        at: source,
                        to: destination
                    )
                },
                writeData: { data, destination in
                    try data.write(to: destination, options: .atomic)
                }
            )
        }
    }

    private struct MovedArtifact {
        let source: URL
        let destination: URL
    }

    private static let manifestFilename = "recovery-manifest.json"

    static func artifacts(
        for storeURL: URL,
        fileManager: FileManager
    ) -> [URL] {
        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    static func archive(
        storeURL: URL,
        rootName: String,
        archiveReason: String,
        error: Error?,
        fileManager: FileManager,
        now: Date,
        dependencies: Dependencies? = nil
    ) throws -> URL {
        let artifacts = artifacts(for: storeURL, fileManager: fileManager)
        guard !artifacts.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }
        let dependencies = dependencies ?? .live(fileManager: fileManager)

        let archiveRoot = storeURL.deletingLastPathComponent().appending(
            path: rootName,
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: archiveRoot,
            withIntermediateDirectories: true
        )

        let timestamp = ISO8601DateFormatter().string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        let archiveDirectory = archiveRoot.appending(
            path: "\(timestamp)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: archiveDirectory,
            withIntermediateDirectories: false
        )

        var movedArtifacts: [MovedArtifact] = []
        do {
            for artifact in artifacts {
                let destination = archiveDirectory.appending(
                    path: artifact.lastPathComponent
                )
                do {
                    try dependencies.moveItem(artifact, destination)
                    guard !fileManager.fileExists(atPath: artifact.path),
                          fileManager.fileExists(atPath: destination.path) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    movedArtifacts.append(
                        MovedArtifact(
                            source: artifact,
                            destination: destination
                        )
                    )
                } catch {
                    trackCompletedMoveAfterFailure(
                        source: artifact,
                        destination: destination,
                        movedArtifacts: &movedArtifacts,
                        fileManager: fileManager
                    )
                    throw error
                }
            }

            try writeManifest(
                to: archiveDirectory,
                archiveReason: archiveReason,
                movedArtifacts: artifacts.map(\.lastPathComponent),
                error: error,
                now: now,
                fileManager: fileManager,
                dependencies: dependencies
            )
        } catch {
            rollback(
                movedArtifacts,
                archiveDirectory: archiveDirectory,
                fileManager: fileManager,
                dependencies: dependencies
            )
            throw error
        }

        return archiveDirectory
    }

    private static func trackCompletedMoveAfterFailure(
        source: URL,
        destination: URL,
        movedArtifacts: inout [MovedArtifact],
        fileManager: FileManager
    ) {
        guard !fileManager.fileExists(atPath: source.path),
              fileManager.fileExists(atPath: destination.path) else {
            return
        }
        movedArtifacts.append(
            MovedArtifact(source: source, destination: destination)
        )
    }

    private static func rollback(
        _ movedArtifacts: [MovedArtifact],
        archiveDirectory: URL,
        fileManager: FileManager,
        dependencies: Dependencies
    ) {
        var restoredEveryArtifact = true

        for artifact in movedArtifacts.reversed() {
            let sourceExists = fileManager.fileExists(
                atPath: artifact.source.path
            )
            let destinationExists = fileManager.fileExists(
                atPath: artifact.destination.path
            )

            if sourceExists, !destinationExists {
                continue
            }
            guard !sourceExists, destinationExists else {
                restoredEveryArtifact = false
                continue
            }

            do {
                try dependencies.moveItem(
                    artifact.destination,
                    artifact.source
                )
                guard fileManager.fileExists(atPath: artifact.source.path),
                      !fileManager.fileExists(
                          atPath: artifact.destination.path
                      ) else {
                    restoredEveryArtifact = false
                    continue
                }
            } catch {
                restoredEveryArtifact = false
                MerianLog.general.error(
                    "Store recovery could not roll back an artifact move: \(error.localizedDescription, privacy: .private)"
                )
            }
        }

        guard restoredEveryArtifact else { return }

        do {
            try fileManager.removeItem(at: archiveDirectory)
        } catch {
            MerianLog.general.error(
                "Store recovery could not remove an empty failed archive: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private static func writeManifest(
        to archiveDirectory: URL,
        archiveReason: String,
        movedArtifacts: [String],
        error: Error?,
        now: Date,
        fileManager: FileManager,
        dependencies: Dependencies
    ) throws {
        let nsError = error.map { $0 as NSError }
        let manifest = ModelStoreRecoveryManifest(
            timestamp: ISO8601DateFormatter().string(from: now),
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown",
            buildNumber: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            archiveReason: archiveReason,
            reasonDomain: nsError.map {
                StoreRecoveryPrivacyPolicy.sanitizedErrorDomain($0.domain)
            },
            reasonCode: nsError?.code,
            reasonDescription: StoreRecoveryPrivacyPolicy.sanitizedErrorText(
                nsError?.localizedDescription
            ),
            reasonFailureReason: StoreRecoveryPrivacyPolicy.sanitizedErrorText(
                nsError?.userInfo[NSLocalizedFailureReasonErrorKey] as? String
            ),
            movedArtifacts: movedArtifacts.sorted()
        )

        let data = try StoreRecoveryJSONCoding.encode(manifest)
        let url = archiveDirectory.appending(path: manifestFilename)
        try dependencies.writeData(data, url)
        guard fileManager.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
