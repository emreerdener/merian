import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.sharedProcessState(.offlineQueueManager))
struct BackgroundDatabaseActorTests {

    private enum ExpectedSerializedMedia {
        case image(String)
        case audio
        case description(String)
    }
    
    // Helper to create an isolated SwiftData container caching out to disk due to iOS 18 simulator array appending bugs.
    @MainActor
    private func createIsolatedContainer() throws -> ModelContainer {
        try DatabaseActorTestSupport.makeIsolatedContainer()
    }

    private func makeTempAudioFilename(prefix: String = "test_audio") throws -> String {
        let filename = "\(prefix)_\(UUID().uuidString).wav"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try Data(repeating: 0x55, count: 128).write(to: url)
        return filename
    }

    private func assertSerializedItems(
        _ items: [SerializedMediaItem],
        match expected: [ExpectedSerializedMedia]
    ) {
        #expect(items.count == expected.count)

        for (actual, expectation) in zip(items, expected) {
            switch (actual, expectation) {
            case (.image(let reference), .image(let expectedPath)):
                #expect(reference == expectedPath)
            case (.audio(let reference), .audio):
                #expect(reference.serializedPath.hasSuffix(".wav"))
                #expect(
                    FileManager.default.fileExists(
                        atPath: URL.documentsDirectory.appendingPathComponent(reference.serializedPath).path
                    )
                )
            case (.description(let context), .description(let expectedText)):
                #expect(context.freeText == expectedText)
            default:
                Issue.record("Serialized media kind mismatch: \(String(describing: actual))")
            }
        }
    }

    private func cleanupSerializedItems(_ items: [SerializedMediaItem]) {
        for item in items {
            switch item {
            case .image(let reference), .audio(let reference):
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(reference.serializedPath))
            case .video(let reference):
                for mediaReference in [reference.video, reference.thumbnail, reference.audio].compactMap({ $0 }) {
                    try? FileManager.default.removeItem(
                        at: URL.documentsDirectory.appendingPathComponent(mediaReference.serializedPath)
                    )
                }
            case .description:
                break
            }
        }
    }

    @Test func staleLiveGenerationCannotPersistOverReplacementAttempt() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let manager = OfflineQueueManager.shared
        let scanId = "live_generation_fence_\(UUID().uuidString.lowercased())"
        let staleGeneration = UUID()
        let replacementGeneration = UUID()
        defer {
            manager.foregroundInferenceRetirementTasks.cancel(scanId)
            manager.startedForegroundInferenceGenerations.removeValue(
                forKey: scanId
            )
            manager.foregroundInferenceGenerations.removeValue(
                forKey: scanId
            )
        }

        context.insert(OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .pending
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON:
                InferenceGenerationMetadataContract.json(
                    for: replacementGeneration
                )
        ))
        try context.save()
        manager.foregroundInferenceGenerations[scanId] =
            staleGeneration
        manager.startedForegroundInferenceGenerations[scanId] =
            staleGeneration

        let staleSpecies = SpeciesData(
            scanId: scanId,
            commonName: "Stale Attempt",
            scientificName: "Attemptus stale",
            insightData: InsightData(
                aiReasoning: "Late provider response.",
                hazardType: "none"
            ),
            confidenceScore: 0.92,
            isBiological: true,
            isLiveCapture: false,
            isInvasive: false,
            ecologyType: "wild"
        )
        let replacementSpecies = SpeciesData(
            scanId: scanId,
            commonName: "Replacement Attempt",
            scientificName: "Attemptus current",
            insightData: InsightData(
                aiReasoning: "Current provider response.",
                hazardType: "none"
            ),
            confidenceScore: 0.96,
            isBiological: true,
            isLiveCapture: false,
            isInvasive: false,
            ecologyType: "wild"
        )

        let staleResult = await actor.saveNonVisualRecord(
            mappedData: staleSpecies,
            persistenceFence: LiveInferencePersistenceFence(
                scanId: scanId,
                generation: staleGeneration
            )
        )
        manager.foregroundInferenceGenerations[scanId] =
            replacementGeneration
        manager.startedForegroundInferenceGenerations[scanId] =
            replacementGeneration
        let mismatchedSpecies = SpeciesData(
            scanId: "\(scanId)-mismatched",
            commonName: "Mismatched Attempt",
            scientificName: "Attemptus mismatched",
            insightData: InsightData(
                aiReasoning: "Wrong scan identity.",
                hazardType: "none"
            ),
            confidenceScore: 0.96,
            isBiological: true,
            isLiveCapture: false,
            isInvasive: false,
            ecologyType: "wild"
        )
        let mismatchedResult = await actor.saveNonVisualRecord(
            mappedData: mismatchedSpecies,
            persistenceFence: LiveInferencePersistenceFence(
                scanId: scanId,
                generation: replacementGeneration
            )
        )
        manager.foregroundInferenceRetirementTasks.replace(
            for: scanId,
            ownerGeneration: replacementGeneration
        ) { _ in Task {} }
        let retiringResult = await actor.saveNonVisualRecord(
            mappedData: replacementSpecies,
            persistenceFence: LiveInferencePersistenceFence(
                scanId: scanId,
                generation: replacementGeneration
            )
        )
        manager.foregroundInferenceRetirementTasks.cancel(scanId)
        let replacementResult = await actor.saveNonVisualRecord(
            mappedData: replacementSpecies,
            persistenceFence: LiveInferencePersistenceFence(
                scanId: scanId,
                generation: replacementGeneration
            )
        )

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        let record = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(!staleResult.wasSaved)
        #expect(!mismatchedResult.wasSaved)
        #expect(
            !retiringResult.wasSaved,
            "Retirement must fence persistence before durable handoff clears the raw generation"
        )
        #expect(replacementResult.wasSaved)
        #expect(record.commonName == "Replacement Attempt")
    }

    @Test func testProcessAndCleanupOfflineScanPreservesOriginalTimestamp() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)

        let originalTimestamp = Date(timeIntervalSince1970: 1_712_345_678)
        let resultData = Data(
            """
            {
              "success": true,
              "data": {
                "scan_id": "offline_scan_001",
                "is_biological_subject": true,
                "is_live_capture": true,
                "ecology_type": "wild",
                "is_invasive": false,
                "scientific_name": "Danaus plexippus",
                "common_name": "Monarch Butterfly",
                "confidence_score": 0.98,
                "taxonomy": {
                  "kingdom": "Animalia",
                  "class": "Insecta",
                  "order": "Lepidoptera",
                  "family": "Nymphalidae",
                  "genus": "Danaus"
                },
                "insight_data": {
                  "hazard_type": "none",
                  "ai_reasoning": "Migratory butterfly with orange and black wings."
                }
              }
            }
            """.utf8
        )

        let processingResult = await BackgroundInferenceFinalizationService
            .live.processAndCleanupOfflineScan(
            resultData: resultData,
            originalImagePaths: ["offline_monarch.webp"],
            scanId: "offline_queue_001",
            originalTimestamp: originalTimestamp,
            persistenceActor: actor
        )

        #expect(processingResult.finalScanId == "offline_scan_001")

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == "offline_scan_001" })
        let record = try #require(context.fetch(descriptor).first)
        #expect(record.timestamp == originalTimestamp, "Offline scan timestamp must preserve capture chronology")
        #expect(record.captureDate == originalTimestamp, "captureDate must remain the original capture time")
    }

    @Test func testOfflineFinalizationRechecksExistingRecordAfterWaitingForSameScanLock() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let scanId = "finalization_race_scan_001"

        let resultData = Data(
            """
            {
              "success": true,
              "data": {
                "scan_id": "\(scanId)",
                "is_biological_subject": true,
                "is_live_capture": true,
                "ecology_type": "wild",
                "is_invasive": false,
                "scientific_name": "Danaus plexippus",
                "common_name": "Monarch Butterfly",
                "confidence_score": 0.98,
                "insight_data": {
                  "hazard_type": "none",
                  "ai_reasoning": "Migratory butterfly with orange and black wings."
                }
              }
            }
            """.utf8
        )

        await ScanFinalizationCoordinator.shared.acquire(scanId: scanId)
        let offlineTask = Task {
            await BackgroundInferenceFinalizationService.live
                .processAndCleanupOfflineScan(
                resultData: resultData,
                originalImagePaths: ["offline_race.webp"],
                scanId: scanId,
                originalTimestamp: Date(
                    timeIntervalSince1970: 1_700_000_000
                ),
                persistenceActor: actor
            )
        }

        context.insert(
            LocalScanRecord(
                id: scanId,
                speciesId: "live-species-id",
                scientificName: "Danaus plexippus",
                commonName: "Live Monarch",
                capturedMediaJSON: String(
                    data: try JSONEncoder().encode([SerializedMediaItem.image("live_race.webp")]),
                    encoding: .utf8
                ),
                coverImagePath: "live_race.webp",
                isBiological: true,
                isLiveCapture: true
            )
        )
        try context.save()

        await ScanFinalizationCoordinator.shared.release(scanId: scanId)
        _ = await offlineTask.value

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let records = try verificationContext.fetch(descriptor)
        let record = try #require(records.first)

        #expect(records.count == 1, "Offline finalization must not insert a duplicate after another path saves the same scan id")
        #expect(record.commonName == "Live Monarch")
        #expect(record.coverImagePath == "live_race.webp")
    }

    @Test func cancelledOfflineFinalizationDoesNotPersistAfterWaitingForSameScanLock() async throws {
        let container = try createIsolatedContainer()
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let scanId = "cancelled_finalization_\(UUID().uuidString.lowercased())"
        let mappedData = SpeciesData(
            scanId: scanId,
            commonName: "Cancelled Result",
            scientificName: "Cancelled resultus",
            insightData: InsightData(
                aiReasoning: "This result must not be persisted.",
                hazardType: "none"
            ),
            confidenceScore: 0.95,
            isBiological: true,
            isLiveCapture: false
        )

        await ScanFinalizationCoordinator.shared.acquire(scanId: scanId)
        let finalizationTask = Task {
            await actor.persistOfflineScanResultAssumingPersistenceLock(
                mappedData: mappedData,
                originalImagePaths: ["cancelled.webp"],
                scanId: scanId,
                originalTimestamp: Date(),
                observationContextsJSON: nil,
                audioFilePaths: nil,
                videoFilePaths: nil,
                capturedMediaJSON: nil
            )
        }
        for _ in 0..<20 {
            await Task.yield()
        }
        finalizationTask.cancel()
        await ScanFinalizationCoordinator.shared.release(scanId: scanId)

        let result = await finalizationTask.value
        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        #expect(!result.wasCleaned)
        #expect(result.finalScanId == nil)
        #expect(try verificationContext.fetch(descriptor).isEmpty)

        let waitedForLeakedOwner = await ScanFinalizationCoordinator.shared
            .acquire(scanId: scanId)
        #expect(!waitedForLeakedOwner)
        await ScanFinalizationCoordinator.shared.release(scanId: scanId)
    }

    @Test func generatedBackgroundResultRejectsWrongScanId() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let scanId =
            "background-result-owner-\(UUID().uuidString.lowercased())"
        let generation = UUID()

        context.insert(OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .inferencing
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON:
                InferenceGenerationMetadataContract.json(for: generation)
        ))
        try context.save()

        let resultData = Data(
            """
            {
              "success": true,
              "data": {
                "scan_id": "stale-background-result",
                "is_biological_subject": true,
                "scientific_name": "Resultus stale",
                "common_name": "Stale Result",
                "confidence_score": 0.95
              }
            }
            """.utf8
        )

        let result = await BackgroundInferenceFinalizationService.live
            .processAndCleanupOfflineScan(
            resultData: resultData,
            originalImagePaths: [],
            scanId: scanId,
            originalTimestamp: Date(),
            expectedGeneration: generation,
            persistenceActor: actor
        )

        #expect(!result.wasCleaned)
        let recordDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate {
                $0.id == "stale-background-result"
            }
        )
        #expect(try context.fetch(recordDescriptor).isEmpty)
    }

    @Test func generatedBackgroundResultRejectsMalformedSuccessBody() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let scanId =
            "background-malformed-response-\(UUID().uuidString.lowercased())"
        let generation = UUID()

        context.insert(OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .inferencing
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON:
                InferenceGenerationMetadataContract.json(for: generation)
        ))
        try context.save()

        for invalidResultData in [
            Data(#"{"success":true,"data":"truncated"}"#.utf8),
            Data(
                #"{"success":false,"data":{"scan_id":"\#(scanId)","confidence_score":0}}"#.utf8
            ),
            Data(
                #"{"success":true,"data":{"scan_id":"\#(scanId)"}}"#.utf8
            )
        ] {
            let result = await BackgroundInferenceFinalizationService.live
                .processAndCleanupOfflineScan(
                resultData: invalidResultData,
                originalImagePaths: [],
                scanId: scanId,
                originalTimestamp: Date(),
                expectedGeneration: generation,
                persistenceActor: actor
            )
            #expect(!result.wasCleaned)
        }
        let queueDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        #expect(try context.fetch(queueDescriptor).count == 1)
        #expect(try context.fetch(FetchDescriptor<LocalScanRecord>()).isEmpty)
    }

    @Test func generatedConfidenceZeroBackgroundResultIsTerminal() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let scanId =
            "background-confidence-zero-\(UUID().uuidString.lowercased())"
        let generation = UUID()
        let sourceImageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(scanId).webp")
        try Data(repeating: 0x55, count: 128).write(to: sourceImageURL)
        defer { try? FileManager.default.removeItem(at: sourceImageURL) }

        context.insert(OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .inferencing
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON:
                InferenceGenerationMetadataContract.json(for: generation)
        ))
        try context.save()

        let result = await BackgroundInferenceFinalizationService.live
            .processAndCleanupOfflineScan(
            resultData: Data(
                """
                {
                  "success": true,
                  "data": {
                    "scan_id": "\(scanId)",
                    "is_biological_subject": false,
                    "common_name": "No identification",
                    "confidence_score": 0
                  }
                }
                """.utf8
            ),
            originalImagePaths: [sourceImageURL.path],
            scanId: scanId,
            originalTimestamp: Date(),
            expectedGeneration: generation,
            persistenceActor: actor
        )

        #expect(result.wasCleaned)
        #expect(result.finalScanId == nil)
        #expect(try context.fetch(FetchDescriptor<LocalScanRecord>()).isEmpty)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(FileManager.default.fileExists(atPath: sourceImageURL.path))
    }

    @Test func testSaveLiveScanRecordReplacesCollisionPreservingFieldNotesAndSpeciesId() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let scanId = "live_collision_scan_001"

        context.insert(
            LocalScanRecord(
                id: scanId,
                speciesId: "stable-species-id",
                scientificName: "Cardinalis cardinalis",
                commonName: "Older Cardinal",
                timestamp: Date(timeIntervalSince1970: 100),
                capturedMediaJSON: String(
                    data: try JSONEncoder().encode([SerializedMediaItem.image("old_capture.webp")]),
                    encoding: .utf8
                ),
                coverImagePath: "old_capture.webp",
                isBiological: true,
                isLiveCapture: true,
                fieldNotes: "  feeder call notes  "
            )
        )
        try context.save()

        let mappedData = SpeciesData(
            scanId: scanId,
            commonName: "Northern Cardinal",
            scientificName: "Cardinalis cardinalis",
            insightData: InsightData(aiReasoning: "Fresh visual result.", hazardType: "none"),
            confidenceScore: 0.96,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        let persistenceResult = await actor.saveLiveScanRecord(
            mappedData: mappedData,
            localImagePaths: ["new_capture.webp"]
        )

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let records = try verificationContext.fetch(descriptor)
        let record = try #require(records.first)

        #expect(persistenceResult.wasSaved)
        #expect(
            persistenceResult.isNewDiscovery == false,
            "Replacing a same-species collision must not count as a new discovery"
        )
        #expect(records.count == 1, "Collision replacement must leave exactly one LocalScanRecord for the scan ID")
        #expect(record.speciesId == "stable-species-id", "Shared species lookup must preserve the existing species UUID")
        #expect(record.commonName == "Northern Cardinal")
        #expect(record.fieldNotes == "feeder call notes", "Collision replacement must preserve trimmed user field notes")
        #expect(record.coverImagePath == "new_capture.webp")
    }

    @Test func testSaveLiveScanRecordKeepsExistingDocumentsAudio() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)

        let audioFilename = "live_audio_\(UUID().uuidString).wav"
        let audioURL = URL.documentsDirectory.appendingPathComponent(audioFilename)
        try Data(repeating: 0x33, count: 128).write(to: audioURL)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        let mappedData = SpeciesData(
            scanId: "live_audio_scan_001",
            commonName: "Northern Cardinal",
            scientificName: "Cardinalis cardinalis",
            insightData: InsightData(aiReasoning: "Clear cardinal vocalization.", hazardType: "none"),
            confidenceScore: 0.94,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        _ = await actor.saveLiveScanRecord(
            mappedData: mappedData,
            localImagePaths: ["primary_capture.webp"],
            audioFilePaths: [audioFilename]
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == "live_audio_scan_001" }
        )
        let record = try #require(context.fetch(descriptor).first)
        let capturedMediaJSON = try #require(record.capturedMediaJSON)
        let items = try #require(MediaJSONParser.serializedItems(jsonString: capturedMediaJSON))

        #expect(items.contains(where: {
            if case .audio(let path) = $0 { return path == audioFilename }
            return false
        }), "Live saved scans must retain their already-persisted audio filename in capturedMediaJSON")
        #expect(record.capturedMediaEntries?.count == items.count)
        #expect(record.serializedCapturedMediaItems == items)
        #expect(FileManager.default.fileExists(atPath: audioURL.path) == true, "Audio already stored in Documents must not be deleted during saveLiveScanRecord")
    }

    @Test func testSaveLiveScanRecordPreservesAudioBeforeImageTimeline() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)

        let audioFilename = "ordered_live_audio_\(UUID().uuidString).wav"
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(audioFilename)
        try Data(repeating: 0x44, count: 128).write(to: audioURL)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(audioFilename))
        }

        let mappedData = SpeciesData(
            scanId: "live_ordered_scan_001",
            commonName: "American Robin",
            scientificName: "Turdus migratorius",
            insightData: InsightData(aiReasoning: "Songbird call with matching plumage context.", hazardType: "none"),
            confidenceScore: 0.93,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        _ = await actor.saveLiveScanRecord(
            mappedData: mappedData,
            localImagePaths: ["ordered_capture.webp"],
            audioFilePaths: [audioFilename],
            mediaTimeline: [.audio(audioFilename), .image(index: 0)]
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == "live_ordered_scan_001" }
        )
        let record = try #require(context.fetch(descriptor).first)
        let capturedMediaJSON = try #require(record.capturedMediaJSON)
        let items = try #require(MediaJSONParser.serializedItems(jsonString: capturedMediaJSON))

        #expect(items.count == 2)
        #expect(record.capturedMediaEntries?.count == items.count)
        #expect(record.serializedCapturedMediaItems == items)

        if case .audio(let reference) = items[0] {
            #expect(reference.serializedPath.hasSuffix(".wav"))
            #expect(
                FileManager.default.fileExists(
                    atPath: URL.documentsDirectory.appendingPathComponent(reference.serializedPath).path
                )
            )
            try? FileManager.default.removeItem(
                at: URL.documentsDirectory.appendingPathComponent(reference.serializedPath)
            )
        } else {
            Issue.record("Live save must preserve the audio-first timeline order")
        }

        if case .image(let reference) = items[1] {
            #expect(reference == "ordered_capture.webp")
        } else {
            Issue.record("Live save must preserve the image second in the timeline")
        }
    }

    @Test func testSaveNonVisualRecordPreservesMultipleDescriptionsInOrder() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)

        let firstContext = ObservationContext(freeText: "Small bird at the waterline")
        let secondContext = ObservationContext(freeText: "Repeated sharp chip calls")
        let firstContextJSON = try #require(
            String(data: JSONEncoder().encode(firstContext), encoding: .utf8)
        )
        let secondContextJSON = try #require(
            String(data: JSONEncoder().encode(secondContext), encoding: .utf8)
        )

        let mappedData = SpeciesData(
            scanId: "describe_ordered_scan_001",
            commonName: "Spotted Sandpiper",
            scientificName: "Actitis macularius",
            insightData: InsightData(aiReasoning: "The repeated shoreline behavior and call match a sandpiper.", hazardType: "none"),
            confidenceScore: 0.91,
            isBiological: true,
            isLiveCapture: false,
            isInvasive: false,
            ecologyType: "wild"
        )

        _ = await actor.saveNonVisualRecord(
            mappedData: mappedData,
            observationContextsJSON: [firstContextJSON, secondContextJSON],
            mediaTimeline: [.description(firstContext), .description(secondContext)]
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == "describe_ordered_scan_001" }
        )
        let record = try #require(context.fetch(descriptor).first)
        let capturedMediaJSON = try #require(record.capturedMediaJSON)
        let items = try #require(MediaJSONParser.serializedItems(jsonString: capturedMediaJSON))

        #expect(items.count == 2)

        if case .description(let context) = items[0] {
            #expect(context.freeText == firstContext.freeText)
        } else {
            Issue.record("Describe save must preserve the first staged description")
        }

        if case .description(let context) = items[1] {
            #expect(context.freeText == secondContext.freeText)
        } else {
            Issue.record("Describe save must preserve the second staged description")
        }
    }

    @Test func testSaveNonVisualRecordSupportsAllowedCombinationMatrix() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)

        let loneDescription = ObservationContext(freeText: "single description")
        let pairedDescription = ObservationContext(freeText: "paired description")

        struct Scenario {
            let scanId: String
            let commonName: String
            let scientificName: String
            let audioFilePaths: [String]
            let observationContexts: [ObservationContext]
            let mediaTimeline: [CaptureSubmissionMediaItem]
            let expected: [ExpectedSerializedMedia]
        }

        let audioOnly = try makeTempAudioFilename(prefix: "audio_only")
        let firstAudio = try makeTempAudioFilename(prefix: "audio_pair_1")
        let secondAudio = try makeTempAudioFilename(prefix: "audio_pair_2")
        let audioWithDescription = try makeTempAudioFilename(prefix: "audio_and_description")

        let scenarios: [Scenario] = [
            .init(
                scanId: "nonvisual_audio_only",
                commonName: "Audio Only",
                scientificName: "Audio only",
                audioFilePaths: [audioOnly],
                observationContexts: [],
                mediaTimeline: [.audio(audioOnly)],
                expected: [.audio]
            ),
            .init(
                scanId: "nonvisual_audio_audio",
                commonName: "Audio Pair",
                scientificName: "Audio pair",
                audioFilePaths: [firstAudio, secondAudio],
                observationContexts: [],
                mediaTimeline: [.audio(firstAudio), .audio(secondAudio)],
                expected: [.audio, .audio]
            ),
            .init(
                scanId: "nonvisual_audio_description",
                commonName: "Audio With Description",
                scientificName: "Audio description",
                audioFilePaths: [audioWithDescription],
                observationContexts: [pairedDescription],
                mediaTimeline: [.audio(audioWithDescription), .description(pairedDescription)],
                expected: [.audio, .description(pairedDescription.freeText)]
            ),
            .init(
                scanId: "nonvisual_description_only",
                commonName: "Description Only",
                scientificName: "Description only",
                audioFilePaths: [],
                observationContexts: [loneDescription],
                mediaTimeline: [.description(loneDescription)],
                expected: [.description(loneDescription.freeText)]
            ),
            .init(
                scanId: "nonvisual_description_description",
                commonName: "Description Pair",
                scientificName: "Description pair",
                audioFilePaths: [],
                observationContexts: [loneDescription, pairedDescription],
                mediaTimeline: [.description(loneDescription), .description(pairedDescription)],
                expected: [.description(loneDescription.freeText), .description(pairedDescription.freeText)]
            )
        ]

        for scenario in scenarios {
            let observationContextsJSON = try scenario.observationContexts.map {
                try #require(
                    String(
                        bytes: try JSONEncoder().encode($0),
                        encoding: .utf8
                    )
                )
            }

            let mappedData = SpeciesData(
                scanId: scenario.scanId,
                commonName: scenario.commonName,
                scientificName: scenario.scientificName,
                insightData: InsightData(aiReasoning: "matrix", hazardType: "none"),
                confidenceScore: 0.91,
                isBiological: true,
                isLiveCapture: false,
                isInvasive: false,
                ecologyType: "wild"
            )

            _ = await actor.saveNonVisualRecord(
                mappedData: mappedData,
                observationContextsJSON: observationContextsJSON,
                audioFilePaths: scenario.audioFilePaths.isEmpty ? nil : scenario.audioFilePaths,
                mediaTimeline: scenario.mediaTimeline
            )

            let scanId = scenario.scanId
            let descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == scanId }
            )
            let record = try #require(context.fetch(descriptor).first)
            let capturedMediaJSON = try #require(record.capturedMediaJSON)
            let items = try #require(MediaJSONParser.serializedItems(jsonString: capturedMediaJSON))

            assertSerializedItems(items, match: scenario.expected)
            let audioSourceIndices = items.compactMap { item -> Int? in
                guard case .audio(let reference) = item else { return nil }
                return reference.sourceIndex
            }
            let expectedAudioCount = scenario.expected.reduce(into: 0) { count, item in
                if case .audio = item { count += 1 }
            }
            #expect(audioSourceIndices == Array(0..<expectedAudioCount))
            cleanupSerializedItems(items)
        }
    }

    @Test func testSaveLiveScanRecordSupportsAllowedVisualCombinationMatrix() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)

        let stagedDescription = ObservationContext(freeText: "image companion description")
        let descriptionJSON = try #require(
            String(data: JSONEncoder().encode(stagedDescription), encoding: .utf8)
        )
        let stagedAudio = try makeTempAudioFilename(prefix: "image_audio")

        struct Scenario {
            let scanId: String
            let commonName: String
            let scientificName: String
            let localImagePaths: [String]
            let observationContextsJSON: [String]?
            let audioFilePaths: [String]?
            let mediaTimeline: [CaptureSubmissionMediaItem]
            let expected: [ExpectedSerializedMedia]
        }

        let scenarios: [Scenario] = [
            .init(
                scanId: "visual_image_only",
                commonName: "Image Only",
                scientificName: "Image only",
                localImagePaths: ["image_only.webp"],
                observationContextsJSON: nil,
                audioFilePaths: nil,
                mediaTimeline: [.image(index: 0)],
                expected: [.image("image_only.webp")]
            ),
            .init(
                scanId: "visual_image_image",
                commonName: "Image Pair",
                scientificName: "Image pair",
                localImagePaths: ["image_one.webp", "image_two.webp"],
                observationContextsJSON: nil,
                audioFilePaths: nil,
                mediaTimeline: [.image(index: 0), .image(index: 1)],
                expected: [.image("image_one.webp"), .image("image_two.webp")]
            ),
            .init(
                scanId: "visual_description_image",
                commonName: "Description Image",
                scientificName: "Description image",
                localImagePaths: ["description_image.webp"],
                observationContextsJSON: [descriptionJSON],
                audioFilePaths: nil,
                mediaTimeline: [.description(stagedDescription), .image(index: 0)],
                expected: [.description(stagedDescription.freeText), .image("description_image.webp")]
            ),
            .init(
                scanId: "visual_audio_image",
                commonName: "Audio Image",
                scientificName: "Audio image",
                localImagePaths: ["audio_image.webp"],
                observationContextsJSON: nil,
                audioFilePaths: [stagedAudio],
                mediaTimeline: [.audio(stagedAudio), .image(index: 0)],
                expected: [.audio, .image("audio_image.webp")]
            )
        ]

        for scenario in scenarios {
            let mappedData = SpeciesData(
                scanId: scenario.scanId,
                commonName: scenario.commonName,
                scientificName: scenario.scientificName,
                insightData: InsightData(aiReasoning: "matrix", hazardType: "none"),
                confidenceScore: 0.93,
                isBiological: true,
                isLiveCapture: true,
                isInvasive: false,
                ecologyType: "wild"
            )

            _ = await actor.saveLiveScanRecord(
                mappedData: mappedData,
                localImagePaths: scenario.localImagePaths,
                observationContextsJSON: scenario.observationContextsJSON,
                audioFilePaths: scenario.audioFilePaths,
                mediaTimeline: scenario.mediaTimeline
            )

            let scanId = scenario.scanId
            let descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == scanId }
            )
            let record = try #require(context.fetch(descriptor).first)
            let capturedMediaJSON = try #require(record.capturedMediaJSON)
            let items = try #require(MediaJSONParser.serializedItems(jsonString: capturedMediaJSON))

            assertSerializedItems(items, match: scenario.expected)
            cleanupSerializedItems(items)
        }
    }

    @Test func testOfflineFinalizationRejectsOlderPersistedGeneration() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("stale-finalization.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let firstGeneration = UUID()
        let secondGeneration = UUID()
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: firstGeneration
            )
        )
        #expect(
            await actor.transitionScanToStaged(
                id: scan.id,
                expectedGeneration: firstGeneration
            )
        )
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: secondGeneration
            )
        )

        let staleResult = await BackgroundInferenceFinalizationService.live
            .processAndCleanupOfflineScan(
            resultData: Data("{}".utf8),
            originalImagePaths: [],
            scanId: scan.id,
            originalTimestamp: Date(),
            expectedGeneration: firstGeneration,
            persistenceActor: actor
        )

        #expect(staleResult.wasCleaned == false)
        await ScanInferencePersistenceCoordinator.shared.acquire(
            scanId: scan.id
        )
        let secondGenerationStillOwnsPersistence =
            await actor.inferenceGenerationIsCurrentAssumingPersistenceLock(
                scanId: scan.id,
                expectedGeneration: secondGeneration
            )
        await ScanInferencePersistenceCoordinator.shared.release(
            scanId: scan.id
        )
        #expect(secondGenerationStillOwnsPersistence)
    }

    // MARK: - reconcileOrphanedUploadingScans: startup recovery (V33)

    @Test func pausedScansCannotBeClaimedOrReconciled() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let retryAt = Date().addingTimeInterval(600)
        let pending = OfflineQueuedScan(
            scanState: .pending,
            queueNeedsAttention: true
        )
        let uploading = OfflineQueuedScan(
            scanState: .uploading,
            queueNeedsAttention: true
        )
        let staged = OfflineQueuedScan(
            scanState: .staged,
            queueNeedsAttention: true
        )
        let inferencing = OfflineQueuedScan(
            scanState: .inferencing,
            queueNeedsAttention: true
        )
        let delayedPending = OfflineQueuedScan(
            scanState: .pending,
            queueNextRetryAt: retryAt
        )
        let delayedStaged = OfflineQueuedScan(
            scanState: .staged,
            queueNextRetryAt: retryAt
        )
        for scan in [
            pending,
            uploading,
            staged,
            inferencing,
            delayedPending,
            delayedStaged
        ] {
            context.insert(scan)
        }
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimedUploads = await actor.markScansAsUploading(
            scanIds: [pending.id, delayedPending.id]
        )
        let claimedAttentionInference = await actor.tryClaimForInference(
            scanId: staged.id
        )
        let claimedDelayedInference = await actor.tryClaimForInference(
            scanId: delayedStaged.id
        )
        let resetUploads = await actor.reconcileOrphanedUploadingScans(
            activeScanIds: []
        )
        await actor.reconcileOrphanedInferencingScans(
            activeInferenceScanIds: []
        )
        let serverOwnedInferenceIds =
            await actor.fetchServerOwnedInferencingScanIds(
                excludingScanIds: [],
                observedThrough: Date().addingTimeInterval(1)
            )

        let readContext = ModelContext(container)
        let rows = try readContext.fetch(FetchDescriptor<OfflineQueuedScan>())
        let stateById = Dictionary(uniqueKeysWithValues: rows.map {
            ($0.id, $0.queueState)
        })

        #expect(claimedUploads.isEmpty)
        #expect(!claimedAttentionInference)
        #expect(!claimedDelayedInference)
        #expect(!resetUploads)
        #expect(serverOwnedInferenceIds.isEmpty)
        #expect(stateById[pending.id] == .pending)
        #expect(stateById[uploading.id] == .uploading)
        #expect(stateById[staged.id] == .staged)
        #expect(stateById[inferencing.id] == .inferencing)
        #expect(stateById[delayedPending.id] == .pending)
        #expect(stateById[delayedStaged.id] == .staged)
    }

    // MARK: - Full state machine lifecycle (V33)

    @Test func testFullStateMachineLifecycle() async throws {
        // Walks a single scan through every forward state transition, then validates
        // the transient-retry path, then re-claims and verifies the second claim is blocked.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("lifecycle.webp")]), encoding: .utf8), scanState: .pending)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)

        func fetchState() throws -> Int {
            var d = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            d.fetchLimit = 1
            return (try context.fetch(d).first?.scanStateRaw) ?? -1
        }

        // .pending → .uploading
        let claimedIds = await actor.markScansAsUploading(scanIds: [scanId])
        #expect(claimedIds == Set([scanId]), "pending scan should be claimed before upload dispatch")
        #expect(try fetchState() == ScanQueueState.uploading.rawValue, ".pending must advance to .uploading")

        // .uploading → .staged (with R2 keys persisted)
        let r2Keys = ["staging/user/\(scanId)_lifecycle.webp"]
        await actor.markScanAsStaged(scanId: scanId, r2Keys: r2Keys)
        #expect(try fetchState() == ScanQueueState.staged.rawValue, ".uploading must advance to .staged")
        var d = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        d.fetchLimit = 1
        #expect(try context.fetch(d).first?.stagedR2Keys == r2Keys, "R2 keys must be persisted at staging")

        // .staged → .inferencing (claim)
        let firstClaim = await actor.tryClaimForInference(scanId: scanId)
        #expect(firstClaim == true, ".staged scan must be claimable for inference")
        #expect(try fetchState() == ScanQueueState.inferencing.rawValue, "claimed scan must be .inferencing")

        // Concurrent second claim is blocked
        let secondClaim = await actor.tryClaimForInference(scanId: scanId)
        #expect(secondClaim == false, "second claim on .inferencing scan must fail")

        // Transient failure → retreat to .staged
        await actor.transitionScanToStaged(id: scanId)
        #expect(try fetchState() == ScanQueueState.staged.rawValue, "transient failure must retreat to .staged")

        // Re-claim after retry
        let retryClaim = await actor.tryClaimForInference(scanId: scanId)
        #expect(retryClaim == true, "re-claim on .staged scan must succeed after retry")
        #expect(try fetchState() == ScanQueueState.inferencing.rawValue, "retried scan must be .inferencing again")
    }
}
