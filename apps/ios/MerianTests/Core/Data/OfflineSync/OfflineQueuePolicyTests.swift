@testable import Merian
import Testing

@Suite("Offline Queue Policy")
struct OfflineQueuePolicyTests {
    @Test func batchBudgetsRetainExactValues() {
        #expect(OfflineQueueBatchPolicy.uploadBatchSize == 5)
        #expect(OfflineQueueBatchPolicy.pendingScanFetchLimit == 50)
    }

    @Test func storageBudgetsRetainExactValues() {
        #expect(
            OfflineQueueStoragePolicy.minimumFreeDiskBytes
                == 100 * 1_024 * 1_024
        )
        #expect(
            OfflineQueueStoragePolicy.singlePayloadSoftLimitBytes
                == 25 * 1_024 * 1_024
        )
    }
}
