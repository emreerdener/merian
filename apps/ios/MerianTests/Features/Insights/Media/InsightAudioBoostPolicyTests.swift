import Foundation
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

    @Test("Boost requires persisted completed standalone audio")
    func boostRequiresPersistedCompletedStandaloneAudio() {
        #expect(InsightAudioBoostAvailability.isAvailable(
            hasPersistedScan: true,
            isProcessing: false,
            hasStandaloneAudio: true
        ))
        #expect(!InsightAudioBoostAvailability.isAvailable(
            hasPersistedScan: false,
            isProcessing: false,
            hasStandaloneAudio: true
        ))
        #expect(!InsightAudioBoostAvailability.isAvailable(
            hasPersistedScan: true,
            isProcessing: true,
            hasStandaloneAudio: true
        ))
        #expect(!InsightAudioBoostAvailability.isAvailable(
            hasPersistedScan: true,
            isProcessing: false,
            hasStandaloneAudio: false
        ))
    }
}
