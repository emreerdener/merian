@testable import Merian
import Testing

@Suite("Non-Biological Retention Policy")
struct NonBiologicalRetentionPolicyTests {
    @Test func retentionAndPurgeBudgetsRetainExactValues() {
        #expect(NonBiologicalRetentionPolicy.retentionDays == 30)
        #expect(NonBiologicalRetentionPolicy.purgeBatchSize == 250)
    }
}
