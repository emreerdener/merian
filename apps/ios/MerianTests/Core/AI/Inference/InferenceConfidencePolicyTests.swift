@testable import Merian
import Testing

@Suite("Inference Confidence Policy")
struct InferenceConfidencePolicyTests {
    @Test func confidenceBandsResolveByExactTier() {
        let proBands = InferenceConfidencePolicy.bands(forInferenceTier: "pro")
        let flashBands = InferenceConfidencePolicy.bands(
            forInferenceTier: "flash"
        )

        #expect(proBands.strong == 0.85)
        #expect(proBands.possible == 0.65)
        #expect(proBands.diagnosticTrigger == 0.99)
        #expect(flashBands.strong == 0.95)
        #expect(flashBands.possible == 0.75)
        #expect(flashBands.diagnosticTrigger == 0.99)
    }

    @Test func unknownAndMissingTiersUseFlashBands() {
        #expect(
            InferenceConfidencePolicy.bands(forInferenceTier: nil)
                == InferenceConfidencePolicy.flash
        )
        #expect(
            InferenceConfidencePolicy.bands(forInferenceTier: "legacy")
                == InferenceConfidencePolicy.flash
        )
    }
}
