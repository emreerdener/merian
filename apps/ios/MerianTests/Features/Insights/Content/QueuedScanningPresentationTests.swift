import Testing

@testable import Merian

struct QueuedScanningPresentationTests {
    @Test func liveQueueHandoffKeepsAnalysisCopyUserFacing() {
        let contextualPhrases = [
            "Analyzing gray and green colors",
            "Reviewing mostly muted colors",
            "Noting broad smooth areas"
        ]
        let genericPhrases = ["Scanning subject", "Reviewing details"]
        let onlinePhrases = QueuedScanningPresentation
            .liveVisualHandoffPhrases(
                isOnline: true,
                contextualPhrases: contextualPhrases,
                genericPhrases: genericPhrases
            )

        #expect(onlinePhrases == contextualPhrases)
        #expect(!onlinePhrases.contains { phrase in
            phrase.localizedCaseInsensitiveContains("automatically")
        })
        #expect(!onlinePhrases.contains { phrase in
            phrase.localizedCaseInsensitiveContains("saved to scans")
        })
        #expect(QueuedScanningPresentation.liveVisualHandoffPhrases(
            isOnline: false,
            contextualPhrases: contextualPhrases,
            genericPhrases: genericPhrases
        ) == ["Waiting for connection"])
        #expect(QueuedScanningPresentation.liveVisualHandoffPhrases(
            isOnline: true,
            contextualPhrases: [],
            genericPhrases: genericPhrases
        ) == genericPhrases)
    }

    @Test func liveVisualHandoffKeepsPhraseCursorAcrossConnectivityChanges() {
        let online = QueuedScanningPresentation.rotationID(
            scanID: "cursor-scan",
            isLiveVisualHandoff: true,
            queueState: .inferencing,
            isOnline: true,
            serverJobStatus: .processing,
            needsAttention: false,
            hasScheduledRetry: false
        )
        let offline = QueuedScanningPresentation.rotationID(
            scanID: "cursor-scan",
            isLiveVisualHandoff: true,
            queueState: .staged,
            isOnline: false,
            serverJobStatus: .failedRetryable,
            needsAttention: false,
            hasScheduledRetry: true
        )
        #expect(online == offline)

        let ordinaryOffline = QueuedScanningPresentation.rotationID(
            scanID: "cursor-scan",
            isLiveVisualHandoff: false,
            queueState: .staged,
            isOnline: false,
            serverJobStatus: .failedRetryable,
            needsAttention: false,
            hasScheduledRetry: true
        )
        #expect(ordinaryOffline != online)
    }

    @Test func queuedPhrasesDescribeDurableStateWithoutImplementationCopy() {
        let phrases = QueuedScanningPresentation.phrases(
            queueState: .staged,
            isOnline: true,
            serverJobStatus: nil,
            needsAttention: false,
            hasScheduledRetry: true,
            hasVideo: false,
            isLiveVisualHandoff: false,
            contextualPhrases: [],
            genericPhrases: ["Scanning subject"]
        )

        #expect(phrases == ["Scan safely queued", "Waiting to retry"])
        #expect(!phrases.joined().localizedCaseInsensitiveContains("rpc"))
    }
}
