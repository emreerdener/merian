import Foundation
import SwiftData
import Testing

@testable import Merian

@Suite("Insight audio boost policy")
struct InsightAudioBoostPolicyTests {
    @Test("Preferences are per scan and separate from Explore posts")
    func preferencesArePerScanAndSeparateFromExplorePosts() throws {
        let suite = "InsightAudioBoostPreferenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let insightStore = InsightAudioBoostPreferenceStore(defaults: defaults)
        let exploreStore = ExploreAudioBoostPreferenceStore(defaults: defaults)

        insightStore.setEnabled(true, for: "scan-cardinal")

        #expect(insightStore.isEnabled(for: "scan-cardinal"))
        #expect(!insightStore.isEnabled(for: "scan-frog"))
        #expect(!exploreStore.isEnabled(for: "scan-cardinal"))
    }

    @Test("Boost requires a scan identity and standalone audio")
    func boostRequiresScanIdentityAndStandaloneAudio() {
        #expect(InsightAudioBoostAvailability.isAvailable(
            hasScanIdentity: true,
            hasStandaloneAudio: true
        ))
        #expect(!InsightAudioBoostAvailability.isAvailable(
            hasScanIdentity: false,
            hasStandaloneAudio: true
        ))
        #expect(!InsightAudioBoostAvailability.isAvailable(
            hasScanIdentity: true,
            hasStandaloneAudio: false
        ))
    }

    @MainActor
    @Test("Visible boost toggles during foreground analysis without a result record")
    func boostDuringForegroundAnalysis() {
        let engine = InferenceEngine()
        engine.activeScanId = "analyzing-audio"
        engine.isProcessing = true
        engine.activeMedia = ActiveScanMedia(items: [.audio("analysis.wav")])
        let viewModel = InsightSheetViewModel(inferenceEngine: engine)
        let generation = viewModel.scanBoundActionGeneration
        let binding = viewModel.audioBoostBinding(
            expectedScanId: "analyzing-audio", expectedGeneration: generation
        )

        #expect(viewModel.presentedLocalRecordScanId == nil)
        #expect(viewModel.audioBoostEligibleScanId == "analyzing-audio")
        viewModel.toggleAudioBoostFromMedia(
            expectedScanId: "analyzing-audio", expectedGeneration: generation
        )
        #expect(binding.wrappedValue)
        #expect(viewModel.state.audioBoostActionToken != nil)
        binding.wrappedValue = false
        #expect(!viewModel.state.isAudioBoostEnabled)
    }

    @MainActor
    @Test("Queued boost rejects callbacks from an older presentation, including A to B to A")
    func queuedBoostFencesStaleCallbacks() {
        let first = queuedAudio(id: "audio-a")
        let viewModel = InsightSheetViewModel(queuedContext: first)
        let generation = viewModel.scanBoundActionGeneration
        let oldBinding = viewModel.audioBoostBinding(
            expectedScanId: first.id, expectedGeneration: generation
        )
        viewModel.toggleAudioBoostFromMedia(
            expectedScanId: first.id, expectedGeneration: generation
        )
        #expect(viewModel.isProcessing)
        #expect(oldBinding.wrappedValue)

        viewModel.bindQueuedPresentation(queuedAudio(id: "audio-b"))
        #expect(!viewModel.state.isAudioBoostEnabled)
        viewModel.bindQueuedPresentation(first)
        oldBinding.wrappedValue = true
        viewModel.toggleAudioBoostFromMedia(
            expectedScanId: first.id, expectedGeneration: generation
        )
        #expect(!oldBinding.wrappedValue)
        #expect(!viewModel.state.isAudioBoostEnabled)
        #expect(viewModel.state.audioBoostActionToken == nil)

        viewModel.toggleAudioBoostFromMedia(
            expectedScanId: first.id,
            expectedGeneration: viewModel.scanBoundActionGeneration
        )
        #expect(viewModel.state.isAudioBoostEnabled)
    }

    @MainActor
    @Test("Same-scan foreground to queue handoff preserves boost selection")
    func foregroundToQueuePreservesBoost() {
        let engine = InferenceEngine()
        engine.activeScanId = "audio-handoff"
        engine.isProcessing = true
        engine.activeMedia = ActiveScanMedia(items: [.audio("analysis.wav")])
        let viewModel = InsightSheetViewModel(inferenceEngine: engine)
        viewModel.toggleAudioBoostFromMedia(
            expectedScanId: "audio-handoff",
            expectedGeneration: viewModel.scanBoundActionGeneration
        )
        viewModel.bindQueuedPresentation(queuedAudio(id: "audio-handoff"))
        #expect(viewModel.state.isAudioBoostEnabled)
        #expect(viewModel.audioBoostEligibleScanId == "audio-handoff")
    }

    @MainActor
    @Test("Completion preserves boost while rejecting the retired queue binding")
    func completionPreservesBoost() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "audio-test-species",
            scientificName: "Strix varia",
            commonName: "Barred Owl"
        )
        record.capturedMediaJSON = try #require(String(
            data: JSONEncoder().encode([SerializedMediaItem.audio("analysis.wav")]),
            encoding: .utf8
        ))
        context.insert(record)
        try context.save()
        let engine = InferenceEngine()
        let viewModel = InsightSheetViewModel(
            queuedContext: queuedAudio(id: record.id), inferenceEngine: engine
        )
        let oldBinding = viewModel.audioBoostBinding(
            expectedScanId: record.id,
            expectedGeneration: viewModel.scanBoundActionGeneration
        )
        oldBinding.wrappedValue = true
        #expect(viewModel.promoteQueuedScanIfLocalRecordExists(
            scanId: record.id, modelContext: context, inferenceEngine: engine
        ))
        #expect(viewModel.audioBoostEligibleScanId == record.id)
        #expect(viewModel.state.isAudioBoostEnabled)
        oldBinding.wrappedValue = false
        #expect(viewModel.state.isAudioBoostEnabled)
        let currentBinding = viewModel.audioBoostBinding(
            expectedScanId: record.id,
            expectedGeneration: viewModel.scanBoundActionGeneration
        )
        #expect(currentBinding.wrappedValue)
        currentBinding.wrappedValue = false
        #expect(!viewModel.state.isAudioBoostEnabled)
    }

    private func queuedAudio(id: String) -> QueuedScanContext {
        QueuedScanContext(
            id: id,
            capturedMediaItems: [.audio(.documents("analysis.wav"))],
            queueState: .inferencing,
            timestamp: Date(timeIntervalSince1970: 1)
        )
    }
}
