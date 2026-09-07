import Foundation
import Testing

@Suite("Offline Queue Sync Architecture")
struct OfflineQueueSyncArchitectureTests {
    @Test func serviceFilesAndDeclarationsHaveExactOwners() throws {
        let root = try offlineSyncRoot()
        let sources = try swiftFiles(below: root)
        let actualPaths = Set(sources.map {
            relativePath(of: $0, below: root)
        }.filter { path in
            Self.syncServiceDirectories.contains { directory in
                path.hasPrefix("Services/\(directory)/")
            }
        })

        #expect(actualPaths == Set(Self.expectedImportsByPath.keys))
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "OfflineQueueManager+Sync.swift"
                ).path
            )
        )

        for (declaration, expectedPath) in Self.declarationOwners {
            let owners = try sources.compactMap { file -> String? in
                let source = try contents(of: file)
                guard containsDeclaration(declaration, in: source) else {
                    return nil
                }
                return relativePath(of: file, below: root)
            }
            #expect(owners == [expectedPath])
        }
    }

    @Test func serviceFilesStayBoundedAndDependencyFocused() throws {
        let root = try offlineSyncRoot()

        for (path, expectedImports) in Self.expectedImportsByPath {
            let source = try contents(of: root.appendingPathComponent(path))
            #expect(
                lineCount(of: source) <= 600,
                "\(path) exceeds the 600-line review ceiling"
            )
            #expect(
                imports(in: source) == expectedImports,
                "\(path) has an unexpected framework dependency"
            )
        }
    }

    @Test func isolatedStoreFixtureDoesNotInstallSharedManagerState() throws {
        let support = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/MerianTests/Core/Data/OfflineSync/OfflineSyncTestSupport.swift"
            )
        )

        #expect(!support.contains("OfflineQueueManager.shared"))
    }

    @Test func mediaUploadCompletionTestsMirrorOwner() throws {
        let repository = try repositoryRoot()
        let focusedTests = try contents(
            of: repository.appendingPathComponent(
                "apps/ios/MerianTests/Core/Data/OfflineSync/MediaUploadCompletionTests.swift"
            )
        )
        let legacyAggregate = try contents(
            of: repository.appendingPathComponent(
                "apps/ios/MerianTests/Core/Data/OfflineQueueManagerTests.swift"
            )
        )

        #expect(focusedTests.contains("struct MediaUploadCompletionTests"))
        #expect(focusedTests.contains("\"Media Upload Completion\""))
        #expect(focusedTests.contains(".serialized"))
        #expect(
            focusedTests.contains(
                ".sharedProcessState(.offlineQueueManager)"
            )
        )
        for declaration in Self.mediaUploadCompletionTestDeclarations {
            #expect(focusedTests.contains(declaration))
            #expect(!legacyAggregate.contains(declaration))
        }
        #expect(
            lineCount(of: focusedTests) <= 600,
            "MediaUploadCompletionTests.swift exceeds the 600-line review ceiling"
        )
    }

    @Test func privateHelpersAndResponsibilityBoundariesRemainContained() throws {
        let root = try offlineSyncRoot()
        let cloudDeletion = try source(
            "Services/CloudDeletion/OfflineQueueManager+CloudDeletionSync.swift",
            below: root
        )
        let collections = try source(
            "Services/Collections/OfflineQueueManager+CollectionSync.swift",
            below: root
        )
        let uploadSync = try source(
            "Services/MediaUpload/OfflineQueueManager+UploadSync.swift",
            below: root
        )
        let uploadPreparation = try source(
            "Services/MediaUpload/OfflineQueueManager+UploadPreparation.swift",
            below: root
        )
        let uploadDispatch = try source(
            "Services/MediaUpload/OfflineQueueManager+UploadDispatch.swift",
            below: root
        )
        let uploadCompletion = try source(
            "Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift",
            below: root
        )
        let uploadLifecycle = try source(
            "Services/MediaUpload/OfflineQueueManager+UploadLifecycle.swift",
            below: root
        )
        let backgroundInferenceServices = try [
            source(
                "Services/BackgroundInference/OfflineQueueManager+InferenceRecovery.swift",
                below: root
            ),
            source(
                "Services/BackgroundInference/OfflineQueueManager+InferenceRetry.swift",
                below: root
            )
        ].joined(separator: "\n")

        #expect(cloudDeletion.contains("private func dispatchDeleteBatches("))
        #expect(cloudDeletion.contains("private func markCloudDeletionJob("))
        #expect(!cloudDeletion.contains("generateUploadURLs"))
        #expect(!cloudDeletion.contains("pushCollectionsToEdge"))

        #expect(collections.contains("private func fetchCollectionSyncJob("))
        #expect(collections.contains("private func markCollectionSyncStarted("))
        #expect(collections.contains("pushCollectionsToEdge"))
        #expect(!collections.contains("generateUploadURLs"))
        #expect(!collections.contains("uploadTask("))

        #expect(uploadSync.contains("private func activeUploadTaskCount("))
        #expect(uploadSync.contains("private func trackUploadPreparation("))
        #expect(uploadSync.contains("private func clearUploadPreparation("))
        #expect(uploadSync.contains("generateUploadURLs"))

        #expect(uploadPreparation.contains(
            "nonisolated private func removeInterruptedLegacyQueuedAudioOutputs("
        ))
        #expect(uploadPreparation.contains(
            "\n    nonisolated func prepareUploadItems("
        ))
        #expect(!uploadPreparation.contains("generateUploadURLs"))
        #expect(!uploadPreparation.contains("uploadTask("))

        #expect(uploadDispatch.contains("private struct UploadDispatchEntry"))
        #expect(!uploadDispatch.contains("struct UploadDispatchResult"))
        #expect(uploadDispatch.contains("\n    func dispatchUploadTasks("))
        #expect(uploadDispatch.contains("\n    func handleSyncNetworkFailure("))
        #expect(uploadDispatch.contains("session.uploadTask("))
        #expect(!uploadDispatch.contains("generateUploadURLs"))

        #expect(uploadCompletion.contains("func processUploadCompletion("))
        #expect(uploadCompletion.contains("private func isUploadCompletionCurrent("))
        #expect(uploadCompletion.contains("private func handleUploadFallback("))
        #expect(uploadCompletion.contains("private func fetchScanMetadata("))
        #expect(uploadCompletion.contains("queueActor.markScanAsStaged("))
        #expect(uploadCompletion.contains("dispatchInferenceDownloadTask("))
        #expect(!uploadCompletion.contains("func isUploadGenerationCurrent("))
        #expect(!uploadCompletion.contains("OfflineQueueManager.shared"))

        #expect(uploadLifecycle.contains("func isUploadGenerationCurrent("))
        #expect(uploadLifecycle.contains("func invalidateUploadGeneration("))
        #expect(!uploadLifecycle.contains("import SwiftData"))

        #expect(!backgroundInferenceServices.contains(
            "func processUploadCompletion("
        ))
        #expect(!backgroundInferenceServices.contains(
            "private func handleUploadFallback("
        ))
        #expect(!backgroundInferenceServices.contains(
            "private func fetchScanMetadata("
        ))
        #expect(!backgroundInferenceServices.contains(
            "func isUploadGenerationCurrent("
        ))
    }

    private static let syncServiceDirectories = [
        "CloudDeletion",
        "Collections",
        "MediaUpload"
    ]

    private static let declarationOwners: [String: String] = [
        "func syncPendingDeletions":
            "Services/CloudDeletion/OfflineQueueManager+CloudDeletionSync.swift",
        "func cloudDeletionWasConfirmed":
            "Services/CloudDeletion/OfflineQueueManager+CloudDeletionSync.swift",
        "func cloudDeletionStatusRequiresRecovery":
            "Services/CloudDeletion/OfflineQueueManager+CloudDeletionSync.swift",
        "func nextCloudDeletionRetryAttempt":
            "Services/CloudDeletion/OfflineQueueManager+CloudDeletionSync.swift",
        "func dispatchDeleteBatches":
            "Services/CloudDeletion/OfflineQueueManager+CloudDeletionSync.swift",
        "func markCloudDeletionJob":
            "Services/CloudDeletion/OfflineQueueManager+CloudDeletionSync.swift",
        "func isRunnableCloudDeletionStatus":
            "Services/CloudDeletion/OfflineQueueManager+CloudDeletionSync.swift",
        "func ensureCloudDeletionJob":
            "Services/CloudDeletion/OfflineQueueManager+CloudDeletionSync.swift",
        "func syncPendingScans":
            "Services/MediaUpload/OfflineQueueManager+UploadSync.swift",
        "func activeUploadTaskCount":
            "Services/MediaUpload/OfflineQueueManager+UploadSync.swift",
        "func trackUploadPreparation":
            "Services/MediaUpload/OfflineQueueManager+UploadSync.swift",
        "func clearUploadPreparation":
            "Services/MediaUpload/OfflineQueueManager+UploadSync.swift",
        "func isUploadGenerationCurrent":
            "Services/MediaUpload/OfflineQueueManager+UploadLifecycle.swift",
        "func invalidateUploadGeneration":
            "Services/MediaUpload/OfflineQueueManager+UploadLifecycle.swift",
        "func isCurrentUploadSync":
            "Services/MediaUpload/OfflineQueueManager+UploadLifecycle.swift",
        "func finishUploadSync":
            "Services/MediaUpload/OfflineQueueManager+UploadLifecycle.swift",
        "func expireUploadSync":
            "Services/MediaUpload/OfflineQueueManager+UploadLifecycle.swift",
        "func repairLegacyQueuedAudio":
            "Services/MediaUpload/OfflineQueueManager+UploadPreparation.swift",
        "func removeInterruptedLegacyQueuedAudioOutputs":
            "Services/MediaUpload/OfflineQueueManager+UploadPreparation.swift",
        "func currentMediaStagingUserId":
            "Services/MediaUpload/OfflineQueueManager+UploadPreparation.swift",
        "func prepareUploadItems":
            "Services/MediaUpload/OfflineQueueManager+UploadPreparation.swift",
        "func selectUploadBatch":
            "Services/MediaUpload/OfflineQueueManager+UploadPreparation.swift",
        "func dispatchUploadTasks":
            "Services/MediaUpload/OfflineQueueManager+UploadDispatch.swift",
        "func queuedUploadRequest":
            "Services/MediaUpload/OfflineQueueManager+UploadDispatch.swift",
        "func handleSyncNetworkFailure":
            "Services/MediaUpload/OfflineQueueManager+UploadDispatch.swift",
        "func processUploadCompletion":
            "Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift",
        "func isUploadCompletionCurrent":
            "Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift",
        "func handleUploadFallback":
            "Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift",
        "func fetchScanMetadata":
            "Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift",
        "func enqueueCollectionSync":
            "Services/Collections/OfflineQueueManager+CollectionSync.swift",
        "var hasPendingCollectionSyncJob":
            "Services/Collections/OfflineQueueManager+CollectionSync.swift",
        "var isCollectionSyncJobRunnable":
            "Services/Collections/OfflineQueueManager+CollectionSync.swift",
        "func fetchCollectionSyncJob":
            "Services/Collections/OfflineQueueManager+CollectionSync.swift",
        "func isActiveCollectionSyncStatus":
            "Services/Collections/OfflineQueueManager+CollectionSync.swift",
        "func syncCollectionsIfPending":
            "Services/Collections/OfflineQueueManager+CollectionSync.swift",
        "func drainCollectionSyncIfPossible":
            "Services/Collections/OfflineQueueManager+CollectionSync.swift",
        "func awaitCollectionSyncQuiescenceForAuthTransition":
            "Services/Collections/OfflineQueueManager+CollectionSync.swift",
        "func markCollectionSyncPending":
            "Services/Collections/OfflineQueueManager+CollectionSync.swift",
        "func finishCollectionSyncAttempt":
            "Services/Collections/OfflineQueueManager+CollectionSync.swift",
        "func markCollectionSyncStarted":
            "Services/Collections/OfflineQueueManager+CollectionSync.swift"
    ]

    private static let expectedImportsByPath: [String: Set<String>] = [
        "Services/CloudDeletion/OfflineQueueManager+CloudDeletionSync.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "Services/Collections/OfflineQueueManager+CollectionSync.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "Services/MediaUpload/OfflineQueueManager+UploadSync.swift": [
            "import Foundation"
        ],
        "Services/MediaUpload/OfflineQueueManager+UploadLifecycle.swift": [
            "import Foundation"
        ],
        "Services/MediaUpload/OfflineQueueManager+UploadPreparation.swift": [
            "import Foundation"
        ],
        "Services/MediaUpload/OfflineQueueManager+UploadDispatch.swift": [
            "import Foundation"
        ],
        "Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift": [
            "import Foundation",
            "import SwiftData"
        ]
    ]

    private static let mediaUploadCompletionTestDeclarations = [
        "func survivingLegacyUploadCompletionRepairsBeforeInferenceClaim()",
        "func testUploadGenerationRejectsDelayedReplacementCallback()",
        "func testUploadFailureFencesEverySiblingCallbackInGeneration()",
        "func testUploadManifestWaitsForEverySiblingCallbackOutcome()",
        "func testCompleteUploadManifestResetsRetryOnlyWithDurableStagingCommit()",
        "func testUploadCompletionClearsOnlyTheOwningCallbackToken()",
        "func testStaleUploadGenerationCannotFinishReplacementSync()"
    ]

    private func offlineSyncRoot() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Data/OfflineSync"
        )
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        while candidate.path != "/" {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func source(_ path: String, below root: URL) throws -> String {
        try contents(of: root.appendingPathComponent(path))
    }

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private func imports(in source: String) -> Set<String> {
        Set(
            source.split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("import ") }
        )
    }

    private func lineCount(of source: String) -> Int {
        source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
    }

    private func relativePath(of file: URL, below root: URL) -> String {
        file.path.replacingOccurrences(of: root.path + "/", with: "")
    }

    private func swiftFiles(below root: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else {
            return []
        }
        return try enumerator.compactMap { element in
            guard let file = element as? URL,
                  file.pathExtension == "swift",
                  try file.resourceValues(forKeys: keys).isRegularFile == true
            else {
                return nil
            }
            return file
        }
    }

    private func containsDeclaration(
        _ declaration: String,
        in source: String
    ) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: declaration)
        let pattern =
            #"(?m)^\s*(?:(?:private|fileprivate|internal|package|public|final|static|nonisolated)\s+)*"#
            + escaped
            + #"(?:\s*[:(<{=])"#
        return source.range(of: pattern, options: .regularExpression) != nil
    }
}
