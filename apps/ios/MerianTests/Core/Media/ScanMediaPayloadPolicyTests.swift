@testable import Merian
import Testing

@Suite("Scan Media Payload Policy")
struct ScanMediaPayloadPolicyTests {
    @Test func payloadAndPlaybackBudgetsRetainExactValues() {
        #expect(
            ScanMediaPayloadPolicy.maxStagedImageBytes
                == 5 * 1_024 * 1_024
        )
        #expect(ScanMediaPayloadPolicy.maxInferenceAudioBytes == 2_700_000)
        #expect(
            ScanMediaPayloadPolicy.maxSavedVideoBytes
                == 12 * 1_024 * 1_024
        )
        #expect(ScanMediaPayloadPolicy.videoPlaybackLongEdgeMaxPixels == 1_280)
        #expect(
            ScanMediaPayloadPolicy.videoPlaybackExpectedMaxBytes
                == 3 * 1_024 * 1_024
        )
    }
}
