import Foundation
import Testing

@testable import Merian

@MainActor
struct ScansSharedPolicyTests {
    @Test func queuedSnapshotRecoveryRespectsDurableAndNetworkPolicy() {
        let attention = snapshot(
            id: "needs-attention",
            state: .failed,
            needsAttention: true
        )
        let staged = snapshot(id: "staged", state: .staged)
        let legacyImport = snapshot(
            id: "legacy-import",
            state: .externalImport,
            needsAttention: true
        )
        let pendingVideo = snapshot(
            id: "pending-video",
            state: .pending,
            capturedMediaJSON: CapturedMediaSnapshot(items: [
                .video(
                    StoredVideoMediaReference(
                        .documents("queued-video.mp4")
                    )
                )
            ]).jsonString
        )

        #expect(!attention.isAutomaticRecoveryEligible)
        #expect(attention.canRetryNow)
        #expect(staged.isAutomaticRecoveryEligible)
        #expect(!legacyImport.isAutomaticRecoveryEligible)
        #expect(!legacyImport.canRetryNow)
        #expect(!pendingVideo.isAutomaticRecoveryEligibleForCurrentNetwork(
            isOnline: false,
            isConstrained: false,
            allowsVideoUploads: true,
            isForcedVideoUpload: false
        ))
        #expect(!pendingVideo.isAutomaticRecoveryEligibleForCurrentNetwork(
            isOnline: true,
            isConstrained: true,
            allowsVideoUploads: true,
            isForcedVideoUpload: true
        ))
        #expect(!pendingVideo.isAutomaticRecoveryEligibleForCurrentNetwork(
            isOnline: true,
            isConstrained: false,
            allowsVideoUploads: false,
            isForcedVideoUpload: false
        ))
        #expect(pendingVideo.isAutomaticRecoveryEligibleForCurrentNetwork(
            isOnline: true,
            isConstrained: false,
            allowsVideoUploads: false,
            isForcedVideoUpload: true
        ))
        #expect(pendingVideo.isAutomaticRecoveryEligibleForCurrentNetwork(
            isOnline: true,
            isConstrained: false,
            allowsVideoUploads: true,
            isForcedVideoUpload: false
        ))
        #expect(staged.isAutomaticRecoveryEligibleForCurrentNetwork(
            isOnline: true,
            isConstrained: false,
            allowsVideoUploads: false,
            isForcedVideoUpload: false
        ))
    }

    @Test func queuedSnapshotRestoresLegacyImageValue() {
        let queued = QueuedScanSnapshot(
            id: "legacy-image",
            imagePath: " legacy.webp ",
            capturedMediaJSON: nil,
            queueState: .pending,
            timestamp: Date(timeIntervalSince1970: 1),
            queueNextRetryAt: nil,
            queueLastErrorMessage: nil,
            queueNeedsAttention: false,
            approximateQueuedBytes: 1
        )

        #expect(queued.gridId == "q_legacy-image")
        #expect(queued.capturedMediaItems.count == 1)
        guard case .image(let reference) = queued.capturedMediaItems.first else {
            Issue.record("Expected the legacy image fallback")
            return
        }
        #expect(reference.serializedPath == "legacy.webp")
    }

    @Test func manualRetryEligibilityMatchesQueuedInsightContext() {
        let retryDate = Date(timeIntervalSince1970: 2)
        let cases: [ManualRetryCase] = [
            ManualRetryCase(
                state: .failed,
                needsAttention: false,
                nextRetryAt: nil,
                expected: true
            ),
            ManualRetryCase(
                state: .uploading,
                needsAttention: true,
                nextRetryAt: nil,
                expected: true
            ),
            ManualRetryCase(
                state: .pending,
                needsAttention: false,
                nextRetryAt: retryDate,
                expected: true
            ),
            ManualRetryCase(
                state: .staged,
                needsAttention: false,
                nextRetryAt: retryDate,
                expected: true
            ),
            ManualRetryCase(
                state: .inferencing,
                needsAttention: false,
                nextRetryAt: nil,
                expected: false
            ),
            ManualRetryCase(
                state: .externalImport,
                needsAttention: true,
                nextRetryAt: retryDate,
                expected: false
            )
        ]

        for testCase in cases {
            let queued = snapshot(
                id: "snapshot-\(testCase.state.rawValue)",
                state: testCase.state,
                nextRetryAt: testCase.nextRetryAt,
                needsAttention: testCase.needsAttention
            )
            let context = QueuedScanContext(
                id: "context-\(testCase.state.rawValue)",
                capturedMediaItems: [],
                queueState: testCase.state,
                timestamp: Date(timeIntervalSince1970: 1),
                queueNextRetryAt: testCase.nextRetryAt,
                queueNeedsAttention: testCase.needsAttention
            )

            #expect(queued.canRetryNow == testCase.expected)
            #expect(context.canRetryNow == testCase.expected)
        }
    }

    @Test func gridInteractionsEmitFeedbackBeforeCallbacks() {
        let events = EventRecorder()
        let interactions = ScansGridInteractions(
            dependencies: .init(
                triggerQueuedSelection: {
                    events.values.append("queued.feedback")
                },
                triggerCompletedSelection: {
                    events.values.append("completed.feedback")
                },
                triggerAddSelection: {
                    events.values.append("add.feedback")
                }
            )
        )
        let queued = snapshot(id: "queued", state: .pending)
        let record = LocalScanRecord(
            id: "completed",
            speciesId: "species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )

        interactions.selectQueuedScan(queued) { snapshot in
            events.values.append("queued.callback.\(snapshot.id)")
        }
        interactions.selectCompletedScan(record) { selected in
            events.values.append("completed.callback.\(selected.id)")
        }
        interactions.selectAddScans {
            events.values.append("add.callback")
        }

        #expect(events.values == [
            "queued.feedback",
            "queued.callback.queued",
            "completed.feedback",
            "completed.callback.completed",
            "add.feedback",
            "add.callback"
        ])
    }

    private func snapshot(
        id: String,
        state: ScanQueueState,
        capturedMediaJSON: String? = nil,
        nextRetryAt: Date? = nil,
        needsAttention: Bool = false
    ) -> QueuedScanSnapshot {
        QueuedScanSnapshot(
            id: id,
            imagePath: nil,
            capturedMediaJSON: capturedMediaJSON,
            queueState: state,
            timestamp: Date(timeIntervalSince1970: 1),
            queueNextRetryAt: nextRetryAt,
            queueLastErrorMessage: nil,
            queueNeedsAttention: needsAttention,
            approximateQueuedBytes: 0
        )
    }
}

private struct ManualRetryCase {
    let state: ScanQueueState
    let needsAttention: Bool
    let nextRetryAt: Date?
    let expected: Bool
}

@MainActor
private final class EventRecorder {
    var values: [String] = []
}
