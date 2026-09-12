@testable import Merian
import Testing

@Suite("Scanning Phrase Policy")
struct ScanningPhrasePolicyTests {
    @Test func visionAndCadenceThresholdsRetainExactValues() {
        #expect(ScanningPhrasePolicy.visionConfidenceThreshold == 0.65)
        #expect(ScanningPhrasePolicy.visionMarginThreshold == 0.15)
        #expect(
            ScanningPhrasePolicy.rotationIntervalNanoseconds
                == 2_300_000_000
        )
    }
}
