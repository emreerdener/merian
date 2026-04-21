import Testing
@testable import Merian
import SwiftData
import Foundation

// Serialized to prevent concurrent mutations on OfflineQueueManager.shared.
@Suite(.serialized)
@MainActor
struct OfflineQueueManagerAudioTests {

    private func createInMemoryContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // MARK: - enqueueAudio

    @Test func testEnqueueAudioCreatesStagedRecord() async throws {
        let manager = OfflineQueueManager.shared
        let context = try createInMemoryContext()

        let originalContext = manager.modelContext
        defer { manager.modelContext = originalContext }
        manager.modelContext = context

        // Write a dummy WAV to tmp so enqueueAudio can move it.
        let fileName = "\(UUID().uuidString).wav"
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try Data(repeating: 0x00, count: 64).write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let scanId = UUID().uuidString.lowercased()
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil,
            gpsElevation: nil, locationName: nil, weatherCondition: nil,
            weatherTemperatureF: nil, timeOfDay: nil,
            timestamp: DateUtilities.iso8601Formatter.string(from: Date()),
            zoomFactor: nil, estimatedSizeCm: nil
        )

        manager.enqueueAudio(audioFileName: fileName, telemetry: telemetry, scanId: scanId)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let record = try context.fetch(descriptor).first
        #expect(record != nil, "enqueueAudio must create an OfflineQueuedScan")
        #expect(record?.queueState == .staged, "Audio scans must enter queue as .staged (no upload phase)")
        #expect(record?.audioFilePaths?.first == fileName, "audioFilePaths must contain the recorded file name")
        #expect(record?.localImagePaths.isEmpty == true, "Audio scans must have no image paths")

        // Clean up Documents copy
        try? FileManager.default.removeItem(
            at: URL.documentsDirectory.appendingPathComponent(fileName)
        )
    }

    @Test func testEnqueueAudioRejectsEmptyFileName() async throws {
        let manager = OfflineQueueManager.shared
        let context = try createInMemoryContext()

        let originalContext = manager.modelContext
        defer { manager.modelContext = originalContext }
        manager.modelContext = context

        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil,
            gpsElevation: nil, locationName: nil, weatherCondition: nil,
            weatherTemperatureF: nil, timeOfDay: nil,
            timestamp: DateUtilities.iso8601Formatter.string(from: Date()),
            zoomFactor: nil, estimatedSizeCm: nil
        )

        manager.enqueueAudio(audioFileName: "", telemetry: telemetry)

        let descriptor = FetchDescriptor<OfflineQueuedScan>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        #expect(count == 0, "enqueueAudio must reject empty file names")
    }

    // MARK: - deleteQueuedScan audio cleanup

    @Test func testDeleteQueuedScanRemovesAudioFile() async throws {
        let manager = OfflineQueueManager.shared
        let context = try createInMemoryContext()

        let originalContext = manager.modelContext
        defer { manager.modelContext = originalContext }
        manager.modelContext = context

        // Create a dummy audio file in Documents to simulate a persisted recording.
        let fileName = "\(UUID().uuidString).wav"
        let destURL = URL.documentsDirectory.appendingPathComponent(fileName)
        try Data(repeating: 0x00, count: 64).write(to: destURL)

        let scanId = UUID().uuidString.lowercased()
        let scan = OfflineQueuedScan(
            id: scanId,
            localImagePaths: [],
            scanState: .staged,
            audioFilePaths: [fileName]
        )
        context.insert(scan)
        try context.save()

        await manager.deleteQueuedScan(scanId: scanId)

        // Both the SwiftData record and the audio file must be gone.
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let remaining = (try? context.fetchCount(descriptor)) ?? -1
        #expect(remaining == 0, "deleteQueuedScan must remove the OfflineQueuedScan record")
        #expect(!FileManager.default.fileExists(atPath: destURL.path),
                "deleteQueuedScan must delete the audio file from Documents")
    }

    // MARK: - replayInferenceStagedScans dispatches audio scans

    @Test func testAudioScansArePickedUpByReplayPipeline() async throws {
        let manager = OfflineQueueManager.shared
        let context = try createInMemoryContext()

        let originalContext    = manager.modelContext
        let originalOnline     = manager.isOnline
        let originalReconciled = manager.hasReconciledStartupState
        let originalCount      = manager.replayedStagedScanCount
        defer {
            manager.modelContext              = originalContext
            manager.isOnline                  = originalOnline
            manager.hasReconciledStartupState = originalReconciled
        }

        // Create a dummy audio file so buildAudioRequest won't fail on missing file.
        let fileName = "\(UUID().uuidString).wav"
        let destURL = URL.documentsDirectory.appendingPathComponent(fileName)
        try Data(repeating: 0x00, count: 64).write(to: destURL)
        defer { try? FileManager.default.removeItem(at: destURL) }

        let scan = OfflineQueuedScan(
            localImagePaths: [],
            scanState: .staged,
            audioFilePaths: [fileName]
        )
        context.insert(scan)
        try context.save()

        manager.modelContext              = context
        manager.isOnline                  = true
        manager.hasReconciledStartupState = true

        manager.replayInferenceForUploadedScans()

        // Poll for the replayedStagedScanCount increment (set before any network work).
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && manager.replayedStagedScanCount == originalCount {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(
            manager.replayedStagedScanCount > originalCount,
            "Audio-only staged scans must be dispatched by the replay pipeline (replayedStagedScanCount must increment)"
        )

        // Clean up the scan record so subsequent tests see a clean context.
        let id = scan.id
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == id })
        if let record = try? context.fetch(descriptor).first {
            context.delete(record)
            try? context.save()
        }
    }

    // MARK: - purgeSoftDeletedRecords audio cleanup

    @Test func testPurgeSoftDeletedRemovesAudioFile() async throws {
        let manager = OfflineQueueManager.shared
        let context = try createInMemoryContext()

        let originalContext = manager.modelContext
        defer { manager.modelContext = originalContext }
        manager.modelContext = context

        let fileName = "\(UUID().uuidString).wav"
        let destURL = URL.documentsDirectory.appendingPathComponent(fileName)
        try Data(repeating: 0x00, count: 64).write(to: destURL)

        let scan = OfflineQueuedScan(
            localImagePaths: [],
            scanState: .failed,
            audioFilePaths: [fileName]
        )
        context.insert(scan)
        try context.save()

        manager.purgeSoftDeletedRecords()

        let deadline = Date().addingTimeInterval(3)
        var purged = false
        while Date() < deadline {
            let id = scan.id
            let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == id })
            if (try? context.fetchCount(descriptor)) == 0 {
                purged = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(purged, "purgeSoftDeletedRecords must remove .failed audio scan records")
        #expect(!FileManager.default.fileExists(atPath: destURL.path),
                "purgeSoftDeletedRecords must delete the audio file from Documents")
    }

    // MARK: - Multi-path deletion

    @Test func testDeleteQueuedScanRemovesAllAudioFilePaths() async throws {
        let manager = OfflineQueueManager.shared
        let context = try createInMemoryContext()

        let originalContext = manager.modelContext
        defer { manager.modelContext = originalContext }
        manager.modelContext = context

        let fileNames = ["\(UUID().uuidString).wav", "\(UUID().uuidString).wav"]
        let destURLs = fileNames.map { URL.documentsDirectory.appendingPathComponent($0) }
        for url in destURLs {
            try Data(repeating: 0x00, count: 64).write(to: url)
        }

        let scanId = UUID().uuidString.lowercased()
        let scan = OfflineQueuedScan(
            id: scanId,
            localImagePaths: [],
            scanState: .staged,
            audioFilePaths: fileNames
        )
        context.insert(scan)
        try context.save()

        await manager.deleteQueuedScan(scanId: scanId)

        for url in destURLs {
            #expect(
                !FileManager.default.fileExists(atPath: url.path),
                "deleteQueuedScan must delete every path in audioFilePaths"
            )
        }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        #expect((try? context.fetchCount(descriptor)) == 0,
                "deleteQueuedScan must remove the SwiftData record")
    }

    @Test func testPurgeSoftDeletedRemovesAllAudioFilePaths() async throws {
        let manager = OfflineQueueManager.shared
        let context = try createInMemoryContext()

        let originalContext = manager.modelContext
        defer { manager.modelContext = originalContext }
        manager.modelContext = context

        let fileNames = ["\(UUID().uuidString).wav", "\(UUID().uuidString).wav"]
        let destURLs = fileNames.map { URL.documentsDirectory.appendingPathComponent($0) }
        for url in destURLs {
            try Data(repeating: 0x00, count: 64).write(to: url)
        }

        let scan = OfflineQueuedScan(
            localImagePaths: [],
            scanState: .failed,
            audioFilePaths: fileNames
        )
        context.insert(scan)
        try context.save()

        manager.purgeSoftDeletedRecords()

        let id = scan.id
        let deadline = Date().addingTimeInterval(3)
        var purged = false
        while Date() < deadline {
            let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == id })
            if (try? context.fetchCount(descriptor)) == 0 {
                purged = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(purged, "purgeSoftDeletedRecords must remove the SwiftData record")
        for url in destURLs {
            #expect(
                !FileManager.default.fileExists(atPath: url.path),
                "purgeSoftDeletedRecords must delete every path in audioFilePaths"
            )
        }
    }
}
