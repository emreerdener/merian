import Foundation
import Testing

@Suite("Offline Queue Admission and Replay Architecture")
struct OfflineQueueAdmissionArchitectureTests {
    @Test func focusedFilesAndDeclarationsHaveExactOwners() throws {
        let root = try offlineSyncRoot()
        let sources = try swiftFiles(below: root)
        let actualPaths = Set(sources.map {
            relativePath(of: $0, below: root)
        }.filter { path in
            Self.serviceDirectories.contains { directory in
                path.hasPrefix("Services/\(directory)/")
            }
        })

        #expect(actualPaths == Set(Self.expectedImportsByPath.keys))
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "OfflineQueueManager+Queue.swift"
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

    @Test func focusedFilesStayBoundedAndDependencyFocused() throws {
        let root = try offlineSyncRoot()

        for (path, expectedImports) in Self.expectedImportsByPath {
            let source = try contents(
                of: root.appendingPathComponent(path)
            )
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

    @Test func focusedBehavioralTestsMirrorTheNewOwners() throws {
        let repository = try repositoryRoot()
        let testsRoot = repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Data/OfflineSync"
        )
        let legacyAggregate = try contents(
            of: repository.appendingPathComponent(
                "apps/ios/MerianTests/Core/Data/OfflineQueueManagerTests.swift"
            )
        )

        for (path, suite) in Self.expectedTestSuitesByPath {
            let testSource = try contents(
                of: testsRoot.appendingPathComponent(path)
            )
            #expect(testSource.contains("struct \(suite.typeName)"))
            #expect(testSource.contains("\"\(suite.displayName)\""))
            #expect(testSource.contains(".serialized"))
            #expect(
                testSource.contains(
                    ".sharedProcessState(.offlineQueueManager)"
                )
            )
            for declaration in Self.expectedTestDeclarationsByPath[path, default: []] {
                #expect(testSource.contains(declaration))
            }
            #expect(
                lineCount(of: testSource) <= 600,
                "\(path) exceeds the 600-line review ceiling"
            )
        }

        for movedDeclaration in Self.movedTestDeclarations {
            #expect(!legacyAggregate.contains(movedDeclaration))
        }
    }

    @Test func privateHelpersAndResponsibilityBoundariesRemainContained() throws {
        let root = try offlineSyncRoot()
        let funding = try source(
            "Services/Funding/OfflineQueueManager+Funding.swift",
            below: root
        )
        let fieldTrip = try source(
            "Services/FieldTripProgress/OfflineQueueManager+FieldTripProgress.swift",
            below: root
        )
        let replay = try source(
            "Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift",
            below: root
        )
        let capture = try source(
            "Services/CaptureAdmission/OfflineQueueManager+CaptureEnqueue.swift",
            below: root
        )
        let describe = try source(
            "Services/CaptureAdmission/OfflineQueueManager+DescribeEnqueue.swift",
            below: root
        )
        let fileStore = try source(
            "Services/CaptureAdmission/OfflineCaptureFileStore.swift",
            below: root
        )
        let lifecycle = try source(
            "Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift",
            below: root
        )

        #expect(funding.contains("MerianNetworkClient.shared"))
        #expect(funding.contains("private func localFundingBlockerIsTerminal("))
        #expect(!funding.contains("backgroundSession"))
        #expect(!funding.contains("FileIOActor"))

        #expect(fieldTrip.contains("scanMilestoneCoordinator"))
        #expect(!fieldTrip.contains("MerianNetworkClient"))
        #expect(!fieldTrip.contains("EntitlementManager"))

        #expect(replay.contains("private func replayInferenceStagedScans("))
        #expect(replay.contains("backgroundSession.allTasks"))
        #expect(replay.contains(
            "QueuedInferenceMediaPolicy.containsUnsupportedAudio("
        ))
        #expect(replay.contains(
            "quarantineInvalidQueuedMedia(scanId: scanId)"
        ))
        #expect(!replay.contains("FileManager.default.moveItem"))

        #expect(capture.contains("private func claimFundingAdmission("))
        #expect(capture.contains("private func rollbackFundingAdmission("))
        #expect(capture.contains("private func isFlashFallbackEligible("))
        #expect(capture.contains("private func cleanupPersistedCaptureFiles("))
        #expect(capture.contains("private func insertAndPersistRecord("))
        #expect(capture.components(
            separatedBy: "OfflineCaptureFileStore.persistFiles("
        ).count == 5)
        #expect(capture.components(
            separatedBy: "OfflineCaptureFileStore.makeCapturedMediaJSON("
        ).count == 3)
        #expect(!capture.contains("FileManager.default.moveItem"))

        #expect(describe.contains("func enqueueDescribe("))
        #expect(describe.contains("enqueueNonVisualCapture("))
        #expect(!describe.contains("OfflineQueueStoragePolicy"))
        #expect(!describe.contains("EntitlementManager"))

        #expect(fileStore.contains("enum OfflineCaptureFileStore"))
        #expect(fileStore.contains("private static func persistFile("))
        #expect(fileStore.contains("FileManager.default.moveItem"))
        #expect(!fileStore.contains("extension OfflineQueueManager"))
        #expect(!fileStore.contains("EntitlementManager"))
        let fileStoreConsumers = try swiftFiles(below: root).compactMap { file -> String? in
            let candidate = try contents(of: file)
            guard candidate.contains("OfflineCaptureFileStore") else {
                return nil
            }
            return relativePath(of: file, below: root)
        }
        #expect(Set(fileStoreConsumers) == Self.expectedFileStoreConsumers)

        #expect(lifecycle.contains("ScanInferencePersistenceCoordinator.shared"))
        #expect(lifecycle.contains("func updateDeferredContext("))
        #expect(!lifecycle.contains("FileIOActor"))
        #expect(!lifecycle.contains("MerianNetworkClient"))
    }

    @Test func durableAdmissionAndHandoffOrderingRemainExplicit() throws {
        let root = try offlineSyncRoot()
        let capture = normalizedSource(try source(
            "Services/CaptureAdmission/OfflineQueueManager+CaptureEnqueue.swift",
            below: root
        ))
        let lifecycle = normalizedSource(try source(
            "Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift",
            below: root
        ))

        let fundingClaim = try #require(capture.range(
            of: "guard let funding = claimFundingAdmission("
        ))
        let storageAdmission = try #require(capture.range(
            of: "guard OfflineQueueStoragePolicy.canAdmitNewPayload(",
            range: fundingClaim.upperBound..<capture.endIndex
        ))
        let durableWrite = try #require(capture.range(
            of: "BackgroundTaskWrapper.execute(",
            range: storageAdmission.upperBound..<capture.endIndex
        ))
        let recordInsert = try #require(capture.range(
            of: "await self.insertAndPersistRecord(",
            range: durableWrite.upperBound..<capture.endIndex
        ))
        #expect(fundingClaim.lowerBound < storageAdmission.lowerBound)
        #expect(storageAdmission.lowerBound < durableWrite.lowerBound)
        #expect(durableWrite.lowerBound < recordInsert.lowerBound)

        let rowInsert = try #require(capture.range(
            of: "modelContext.insert(scan)"
        ))
        let committedSave = try #require(capture.range(
            of: "try modelContext.save()",
            range: rowInsert.upperBound..<capture.endIndex
        ))
        let dispatch = try #require(capture.range(
            of: "if startSyncImmediately && funding.allowsDispatch",
            range: committedSave.upperBound..<capture.endIndex
        ))
        #expect(rowInsert.lowerBound < committedSave.lowerBound)
        #expect(committedSave.lowerBound < dispatch.lowerBound)

        let persistenceLock = try #require(lifecycle.range(
            of: "ScanInferencePersistenceCoordinator.shared.acquire(scanId: scanId)"
        ))
        let durableLookup = try #require(lifecycle.range(
            of: "context.fetchOfflineJob(id: jobId)",
            range: persistenceLock.upperBound..<lifecycle.endIndex
        ))
        let release = try #require(lifecycle.range(
            of: "ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)",
            range: durableLookup.upperBound..<lifecycle.endIndex
        ))
        #expect(persistenceLock.lowerBound < durableLookup.lowerBound)
        #expect(durableLookup.lowerBound < release.lowerBound)
    }

    private static let serviceDirectories = [
        "CaptureAdmission",
        "FieldTripProgress",
        "Funding",
        "InferenceReplay"
    ]

    private static let declarationOwners: [String: String] = [
        "func restoreFundingReservationsForCurrentAccount":
            "Services/Funding/OfflineQueueManager+Funding.swift",
        "func reconcileDeferredFundingReservations":
            "Services/Funding/OfflineQueueManager+Funding.swift",
        "func localFundingBlockerIsTerminal":
            "Services/Funding/OfflineQueueManager+Funding.swift",
        "func releaseFundingForProvenPredispatchFailure":
            "Services/Funding/OfflineQueueManager+Funding.swift",
        "func acknowledgeFieldTripProgress":
            "Services/FieldTripProgress/OfflineQueueManager+FieldTripProgress.swift",
        "func replayPendingFieldTripProgress":
            "Services/FieldTripProgress/OfflineQueueManager+FieldTripProgress.swift",
        "func replayInferenceForUploadedScans":
            "Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift",
        "func replayInferenceStagedScans":
            "Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift",
        "enum OfflineCaptureFileStore":
            "Services/CaptureAdmission/OfflineCaptureFileStore.swift",
        "func approximateBytes":
            "Services/CaptureAdmission/OfflineCaptureFileStore.swift",
        "func estimatedBytes":
            "Services/CaptureAdmission/OfflineCaptureFileStore.swift",
        "func persistFiles":
            "Services/CaptureAdmission/OfflineCaptureFileStore.swift",
        "func persistFile":
            "Services/CaptureAdmission/OfflineCaptureFileStore.swift",
        "func makeCapturedMediaJSON":
            "Services/CaptureAdmission/OfflineCaptureFileStore.swift",
        "func enqueueCapture":
            "Services/CaptureAdmission/OfflineQueueManager+CaptureEnqueue.swift",
        "func claimFundingAdmission":
            "Services/CaptureAdmission/OfflineQueueManager+CaptureEnqueue.swift",
        "func rollbackFundingAdmission":
            "Services/CaptureAdmission/OfflineQueueManager+CaptureEnqueue.swift",
        "func isFlashFallbackEligible":
            "Services/CaptureAdmission/OfflineQueueManager+CaptureEnqueue.swift",
        "func cleanupPersistedCaptureFiles":
            "Services/CaptureAdmission/OfflineQueueManager+CaptureEnqueue.swift",
        "func enqueueNonVisualCapture":
            "Services/CaptureAdmission/OfflineQueueManager+CaptureEnqueue.swift",
        "func insertAndPersistRecord":
            "Services/CaptureAdmission/OfflineQueueManager+CaptureEnqueue.swift",
        "func enqueueDescribe":
            "Services/CaptureAdmission/OfflineQueueManager+DescribeEnqueue.swift",
        "func releaseDeferredLiveUpload":
            "Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift",
        "func releaseAllDeferredLiveUploads":
            "Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift",
        "func isForegroundInferenceGenerationCurrent":
            "Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift",
        "func canStartForegroundInference":
            "Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift",
        "func isForegroundInferenceAttemptCurrent":
            "Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift",
        "func claimForegroundInferenceStart":
            "Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift",
        "func retireForegroundInference":
            "Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift",
        "func endForegroundInference":
            "Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift",
        "func releaseAllForegroundInferenceClaims":
            "Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift",
        "func updateDeferredContext":
            "Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift"
    ]

    private static let expectedImportsByPath: [String: Set<String>] = [
        "Services/Funding/OfflineQueueManager+Funding.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "Services/FieldTripProgress/OfflineQueueManager+FieldTripProgress.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "Services/CaptureAdmission/OfflineCaptureFileStore.swift": [
            "import Foundation"
        ],
        "Services/CaptureAdmission/OfflineQueueManager+CaptureEnqueue.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "Services/CaptureAdmission/OfflineQueueManager+DescribeEnqueue.swift": [
            "import Foundation"
        ],
        "Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift": [
            "import Foundation",
            "import SwiftData"
        ]
    ]

    private struct ExpectedTestSuite {
        let typeName: String
        let displayName: String
    }

    private static let expectedTestSuitesByPath = [
        "CaptureAdmissionTests.swift": ExpectedTestSuite(
            typeName: "CaptureAdmissionTests",
            displayName: "Capture Admission Tests"
        ),
        "LiveCaptureLifecycleTests.swift": ExpectedTestSuite(
            typeName: "LiveCaptureLifecycleTests",
            displayName: "Live Capture Lifecycle Tests"
        ),
        "InferenceReplayTests.swift": ExpectedTestSuite(
            typeName: "InferenceReplayTests",
            displayName: "Inference Replay Tests"
        )
    ]

    private static let expectedFileStoreConsumers: Set<String> = [
        "Services/CaptureAdmission/OfflineCaptureFileStore.swift",
        "Services/CaptureAdmission/OfflineQueueManager+CaptureEnqueue.swift"
    ]

    private static let expectedTestDeclarationsByPath = [
        "CaptureAdmissionTests.swift": [
            "func testEnqueueCapture_WithValidData_PersistsQueuedScan(",
            "func testEnqueueCaptureCanHoldAndIdempotentlyReleaseLiveUpload(",
            "func testEnqueueDescribe_InsertsStagedScan(",
            "func testEnqueueCapturePreservesMixedTimelineOrder(",
            "func testEnqueueCaptureSeparatesDisplayMediaFromInferenceFrames(",
            "func testEnqueueNonVisualCaptureSupportsAllowedCombinationMatrix(",
            "func testEnqueueNonVisualCaptureRejectsExtensionSpoofedWAVBeforePersistence("
        ],
        "LiveCaptureLifecycleTests.swift": [
            "func testForegroundInferenceOwnershipOutlivesBodyUploadHandoff(",
            "func staleForegroundGenerationCannotClearReplacementQueueWork("
        ],
        "InferenceReplayTests.swift": [
            "func inferenceReplayReconciliationCoalescesConcurrentWakeSources("
        ]
    ]

    private static let movedTestDeclarations = [
        "func testEnqueueCapture_WithValidData_PersistsQueuedScan(",
        "func testEnqueueCaptureCanHoldAndIdempotentlyReleaseLiveUpload(",
        "func testForegroundInferenceOwnershipOutlivesBodyUploadHandoff(",
        "func testEnqueueDescribe_InsertsStagedScan(",
        "func testEnqueueCapturePreservesMixedTimelineOrder(",
        "func testEnqueueCaptureSeparatesDisplayMediaFromInferenceFrames(",
        "func testEnqueueNonVisualCaptureSupportsAllowedCombinationMatrix(",
        "func testEnqueueNonVisualCaptureRejectsExtensionSpoofedWAVBeforePersistence(",
        "func inferenceReplayReconciliationCoalescesConcurrentWakeSources(",
        "func staleForegroundGenerationCannotClearReplacementQueueWork("
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

    private func normalizedSource(_ source: String) -> String {
        source.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
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
