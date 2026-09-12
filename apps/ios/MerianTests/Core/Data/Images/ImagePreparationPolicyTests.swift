@testable import Merian
import Testing

@Suite("Image Preparation Policy")
struct ImagePreparationPolicyTests {
    @Test func inferenceDimensionsResolveByTier() {
        #expect(ImagePreparationPolicy.proInferenceMaxDimension == 1_024)
        #expect(ImagePreparationPolicy.flashInferenceMaxDimension == 768)
        #expect(ImagePreparationPolicy.maximumInferenceDimension == 1_024)
        #expect(
            ImagePreparationPolicy.inferenceMaxDimension(isProActive: true)
                == 1_024
        )
        #expect(
            ImagePreparationPolicy.inferenceMaxDimension(isProActive: false)
                == 768
        )
    }

    @Test func storedImagePolicyRetainsExactBudgets() {
        #expect(ImagePreparationPolicy.compressionQuality == 0.85)
        #expect(ImagePreparationPolicy.displayMaxDimension == 2_048)
        #expect(ScanMediaPayloadPolicy.maxStagedImageBytes == 5 * 1_024 * 1_024)
    }
}
