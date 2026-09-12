@testable import Merian
import Testing

@Suite("Historical Sync Policy")
struct HistoricalSyncPolicyTests {
    @Test func paginationAndCheckpointBudgetsRetainExactValues() {
        #expect(HistoricalSyncPolicy.scanPageSize == 200)
        #expect(HistoricalSyncPolicy.collectionPageSize == 100)
        #expect(HistoricalSyncPolicy.ingestCheckpointInterval == 100)
    }
}
