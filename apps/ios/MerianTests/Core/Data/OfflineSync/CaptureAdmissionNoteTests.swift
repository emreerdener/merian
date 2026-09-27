import Foundation
@testable import Merian
import SwiftData
import Testing

extension CaptureAdmissionTests {
    @Test(arguments: [false, true], [false, true])
    func mediaPlusNoteUsesRemainingFreeAllowanceAndRetriesSameScan(
        audio: Bool, noteFirst: Bool
    ) async throws {
        enableUnlimitedFreeScansForTest()
        UsageManager.debugFreeScanLimitOverride = false
        UsageManager.shared.evaluateDailyRefresh()
        RevenueCatManager.shared.isSubscribed = false
        RevenueCatManager.shared.isProActive = false
        defer { restoreFreeScanLimitForTest() }
        let account = try #require(EntitlementManager.shared.activeAccountID)
        let entitlementData = try JSONSerialization.data(withJSONObject: [
            "current_plan": "free", "current_tier": "free", "is_paid": false,
            "scans_remaining": 0, "scans_available_to_start": 0,
            "in_flight_count": 0, "entitlement_version": 1
        ])
        let entitlement = try JSONDecoder().decode(EntitlementSnapshotDTO.self, from: entitlementData)
        #expect(EntitlementManager.shared.apply(entitlement, for: account))
        #expect(!EntitlementManager.shared.canStartProFundedScan)
        #expect(UsageManager.shared.freeScansRemaining == 1)

        let manager = OfflineQueueManager.shared
        let original = ManagerSnapshot(manager)
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = false
        let scanID = UUID().uuidString.lowercased()
        let source = audio ? try makeTempAudioFilename() : nil
        defer {
            manager.deferredLiveUploadScanIds.remove(scanID)
            EntitlementManager.shared.releaseFundingAfterProvenLocalFailure(scanId: scanID)
            UsageManager.shared.refundScan(scanId: scanID)
            if let source {
                try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent(source))
            }
            original.restore(manager)
        }
        let note = ObservationContext(freeText: "Calling from reeds")
        let media: CaptureSubmissionMediaItem = audio ? .audio(try #require(source)) : .image(index: 0)
        let timeline: [CaptureSubmissionMediaItem] = noteFirst ? [.description(note), media] : [media, .description(note)]
        #expect(CaptureSubmissionPolicy.isFlashFallbackEligible(timeline))
        let accepted: Bool
        if audio {
            accepted = manager.enqueueNonVisualCapture(
                audioFileNames: [try #require(source)], observationContexts: [note],
                mediaTimeline: timeline, telemetry: dummyTelemetry, scanId: scanID
            )
        } else {
            accepted = await withCheckedContinuation { continuation in
                manager.enqueueCapture(
                    imageDatas: [Data("synthetic image".utf8)],
                    telemetry: dummyTelemetry, scanId: scanID,
                    observationContexts: [note], mediaTimeline: timeline, startSyncImmediately: false,
                    onQueued: { continuation.resume(returning: $0) }
                )
            }
        }
        #expect(accepted)
        let scan = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        let items = scan.serializedCapturedMediaItems
        defer { cleanupSerializedItems(items) }
        #expect(items.count == 2)
        #expect(items[noteFirst ? 0 : 1] == .description(note))
        #expect(OfflineScanJobMetadataContract.funding(in: job.metadataJSON)?.source == .immediateFlash)
        #expect(UsageManager.shared.freeScansRemaining == 0)

        // Exercise recipient preflight with the persisted evidence, preserving its profile.
        let body = try JSONSerialization.data(withJSONObject: [
            "client_scan_id": scanID,
            audio ? "audioR2ObjectKeys" : "r2ObjectKeys": ["synthetic-object"],
            "observation_contexts": [["freeText": note.freeText]]
        ])
        let preflight = try IdentificationPreflightInput(body: body, function: "identify-multimodal")
        #expect(preflight.flashFallbackEligible)
        #expect(preflight.inputProfile == (audio ? .audio : .photo))

        // A proven pre-dispatch failure refunds funding; retry reclaims it on the same row.
        EntitlementManager.shared.releaseFundingAfterProvenLocalFailure(scanId: scanID)
        UsageManager.shared.refundScan(scanId: scanID)
        job.metadataJSON = OfflineScanJobMetadataContract.markingFundingReleased(in: job.metadataJSON)
        scan.queueState = .failed
        scan.queueNeedsAttention = true
        try context.save()
        #expect(manager.retryQueuedScanNow(scanId: scanID))
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(scan.id == scanID)
        #expect(scan.serializedCapturedMediaItems == items)
        #expect(OfflineScanJobMetadataContract.funding(in: job.metadataJSON)?.source == .immediateFlash)
        #expect(UsageManager.shared.freeScansRemaining == 0)
    }

}
