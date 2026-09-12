@testable import Merian
import Testing

@Suite("Inference Lookalike Cache Policy")
struct InferenceLookalikeCachePolicyTests {
    @Test func installedResetVersionRemainsStable() {
        #expect(InferenceLookalikeCachePolicy.resetVersion == 1)
    }
}
