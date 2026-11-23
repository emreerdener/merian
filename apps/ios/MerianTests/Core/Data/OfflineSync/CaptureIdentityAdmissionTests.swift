import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Capture identity admission", .serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureIdentityAdmissionTests {
    @Test(arguments: ["count", "bounds", "role"])
    func malformedVisualEvidenceNeverClaimsFunding(_ failure: String) async throws {
        let harness = CaptureAdmissionTests()
        harness.enableUnlimitedFreeScansForTest()
        defer { harness.restoreFreeScanLimitForTest() }
        let manager = OfflineQueueManager.shared
        let snapshot = CaptureAdmissionTests.ManagerSnapshot(manager)
        defer { snapshot.restore(manager) }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = false
        let id = UUID().uuidString.lowercased()
        let remaining = UsageManager.shared.freeScansRemaining
        let items: [IdentifyVisualMediaItem]
        switch failure {
        case "count": items = []
        case "bounds": items = [.image(sourceIndex: 0, focusRegion: .init(x: 0.8, y: 0, width: 0.5, height: 1, source: .userSelection))]
        default: items = [.videoFrame(clipIndex: -1, frameIndex: 0)]
        }
        let accepted = await withCheckedContinuation { continuation in
            manager.enqueueCapture(imageDatas: [Data("fixture".utf8)], telemetry: harness.dummyTelemetry,
                scanId: id, visualMediaItems: items, startSyncImmediately: false,
                onQueued: { continuation.resume(returning: $0) })
        }
        #expect(!accepted)
        #expect(!manager.inFlightInitialCaptureIDs.contains(id))
        #expect(EntitlementManager.shared.fundingReservation(scanId: id) == nil)
        #expect(UsageManager.shared.freeScansRemaining == remaining)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func identityFenceClosingDuringMediaStagingRejectsPersistence() async throws {
        let harness = CaptureAdmissionTests()
        harness.enableUnlimitedFreeScansForTest()
        defer { harness.restoreFreeScanLimitForTest() }
        let manager = OfflineQueueManager.shared
        let snapshot = CaptureAdmissionTests.ManagerSnapshot(manager)
        defer { snapshot.restore(manager) }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = false
        // Admission succeeds before staging; the final owner check represents
        // an identity transition closing the fence during the file-write await.
        manager.captureLibraryAdmission = { expectedOwner in expectedOwner == nil }
        let accepted = await withCheckedContinuation { continuation in
            manager.enqueueCapture(
                imageDatas: [Data("fenced_capture".utf8)], telemetry: harness.dummyTelemetry,
                startSyncImmediately: false,
                onQueued: { continuation.resume(returning: $0) }
            )
        }
        #expect(!accepted)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func concurrentSameIdentityCannotClaimFundingOrReplaceSeedTwice() async throws {
        let harness = CaptureAdmissionTests()
        harness.enableUnlimitedFreeScansForTest()
        defer { harness.restoreFreeScanLimitForTest() }
        let manager = OfflineQueueManager.shared
        let snapshot = CaptureAdmissionTests.ManagerSnapshot(manager)
        defer { snapshot.restore(manager) }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = false
        let id = UUID().uuidString.lowercased()
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(try harness.makeTempAudioFilename())
        defer { try? FileManager.default.removeItem(at: audioURL) }
        #expect(InferenceAudioPreparer.isQueueEligibleInferenceAudioPath(audioURL.path))
        let accepted = await withCheckedContinuation { continuation in
            manager.enqueueCapture(imageDatas: [Data("first_capture".utf8)], telemetry: harness.dummyTelemetry,
                scanId: id, observationContexts: [.init(freeText: "First evidence")], startSyncImmediately: false,
                onQueued: { continuation.resume(returning: $0) })
            #expect(manager.inFlightInitialCaptureIDs.contains(id))
            manager.enqueueCapture(imageDatas: [Data("duplicate".utf8)], telemetry: harness.dummyTelemetry,
                scanId: id, observationContexts: [.init(freeText: "Replacement")], startSyncImmediately: false,
                onQueued: { #expect(!$0) })
            #expect(!manager.enqueueNonVisualCapture(audioFileNames: [audioURL.path],
                observationContexts: [], telemetry: harness.dummyTelemetry, scanId: id))
            #expect(manager.inFlightInitialCaptureIDs.contains(id))
        }
        #expect(accepted)
        #expect(!manager.inFlightInitialCaptureIDs.contains(id))
        let rows = try context.fetch(FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == id }))
        #expect(rows.count == 1)
        #expect(rows.first?.fieldNotes == "First evidence")
        #expect(!manager.beginInitialCaptureAdmission(id))
    }

    @Test func durableCollisionAfterFileStagingPreservesNotesAndFunding() async throws {
        let harness = CaptureAdmissionTests()
        harness.enableUnlimitedFreeScansForTest()
        defer { harness.restoreFreeScanLimitForTest() }
        let manager = OfflineQueueManager.shared
        let snapshot = CaptureAdmissionTests.ManagerSnapshot(manager)
        let priorAdmission = manager.captureLibraryAdmission
        defer {
            snapshot.restore(manager)
            manager.captureLibraryAdmission = priorAdmission
        }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = false
        let id = UUID().uuidString.lowercased()
        let documents = URL.documentsDirectory
        let beforeFiles = Set(try FileManager.default.contentsOfDirectory(atPath: documents.path))
        var writtenFiles = Set<String>()
        var reservedSource: ScanFundingSource?
        var remainingAfterClaim: Int?
        // The existing owner callback runs after the asynchronous file writes,
        // immediately before the durable-identity check. Insert the competing
        // durable row there, without replacing the queue's persistence code.
        manager.captureLibraryAdmission = { owner in
            guard owner != nil else { return true }
            writtenFiles = Set((try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []).subtracting(beforeFiles)
            reservedSource = EntitlementManager.shared.fundingReservation(scanId: id)?.source
            remainingAfterClaim = UsageManager.shared.freeScansRemaining
            let existing = LocalScanRecord(id: id, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
            existing.fieldNotes = "Edited existing notes"
            context.insert(existing)
            return true
        }
        let accepted = await withCheckedContinuation { continuation in
            manager.enqueueCapture(imageDatas: [Data("collision_capture".utf8)], telemetry: harness.dummyTelemetry,
                scanId: id, observationContexts: [.init(freeText: "Do not reseed")], startSyncImmediately: false,
                onQueued: { continuation.resume(returning: $0) })
        }
        #expect(!accepted)
        #expect(!writtenFiles.isEmpty)
        #expect(writtenFiles.allSatisfy { !FileManager.default.fileExists(atPath: documents.appendingPathComponent($0).path) })
        #expect(!manager.inFlightInitialCaptureIDs.contains(id))
        #expect(reservedSource != nil)
        #expect(EntitlementManager.shared.fundingReservation(scanId: id)?.source == reservedSource)
        #expect(UsageManager.shared.freeScansRemaining == remainingAfterClaim)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try context.fetch(FetchDescriptor<LocalScanRecord>()).first?.fieldNotes == "Edited existing notes")
    }

}
