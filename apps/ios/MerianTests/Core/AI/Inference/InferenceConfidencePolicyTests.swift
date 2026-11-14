import Foundation
@testable import Merian
import Testing

@Suite("Inference Confidence Policy")
struct InferenceConfidencePolicyTests {
    @Test func confidenceBandsResolveByExactTier() {
        let proBands = InferenceConfidencePolicy.bands(forInferenceTier: "pro")
        let flashBands = InferenceConfidencePolicy.bands(
            forInferenceTier: "flash"
        )

        #expect(proBands?.strong == 0.85)
        #expect(proBands?.possible == 0.65)
        #expect(proBands?.diagnosticTrigger == 0.99)
        #expect(flashBands?.strong == 0.95)
        #expect(flashBands?.possible == 0.75)
        #expect(flashBands?.diagnosticTrigger == 0.99)
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
    @Test func generationThreeUsesSharedProvisionalDisplayWithoutMetricQualification() throws {
        var object: [String: Any] = [
            "version": 3, "provider": "gemini", "binding": "gemini_generation3_v1",
            "model": "gemini-3.8-flash", "returned_model": "gemini-3.8-flash",
            "variant": "multimodal", "operation": "scan_identification", "policy_version": 2,
            "prompt": "identify_text_v1", "schema": "merian_identify_v1", "confidence": "gemini_identify_v1",
            "diagnostic_trigger": 0.99, "prompt_diagnostic_trigger": NSNull(), "safety": NSNull(),
            "timeout_ms": 90000, "generation": ["max_output_tokens": 8192, "thinking_level": "medium"]
        ]
        func provenance() throws -> IdentificationResultProvenance {
            IdentificationResultProvenance(storedData: try JSONSerialization.data(withJSONObject: object))
        }
        for tier in ["flash", "pro"] {
            let saved = try provenance()
            #expect(InferenceConfidencePolicy.displayBands(forInferenceTier: tier, provenance: saved) == .init(strong: 0.85, possible: 0.65))
            #expect(InferenceConfidencePolicy.bands(forInferenceTier: tier, provenance: saved) == nil)
        }
        object["returned_model"] = "gemini-2.5-pro"
        #expect(try !provenance().supportsGemini3DisplayBands)
        object["returned_model"] = "gemini-3.8-flash"
        object["prompt"] = "future_prompt"
        #expect(try !provenance().supportsGemini3DisplayBands)
    }

}
