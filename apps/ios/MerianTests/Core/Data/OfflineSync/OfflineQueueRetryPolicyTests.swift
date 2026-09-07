@testable import Merian
import XCTest

final class OfflineQueueRetryPolicyTests: XCTestCase {
    func test_inferencePipeline_transientRetryUsesDurableBackoffInsteadOfTombstoneThreshold() async {
        let firstDelay = OfflineQueueRetryPolicy.delay(forAttempt: 1)
        let laterDelay = OfflineQueueRetryPolicy.delay(forAttempt: 10)

        XCTAssertGreaterThan(firstDelay, 0, "Transient retries should schedule a future retry window.")
        XCTAssertGreaterThan(laterDelay, firstDelay, "Later attempts should back off instead of deleting queued media.")
        XCTAssertEqual(laterDelay, OfflineQueueRetryPolicy.maximumRetryDelay)
    }

    func test_exponentialBackoff_jitterStaysWithinRetryBounds() async {
        for _ in 0..<20 {
            let delay = OfflineQueueRetryPolicy.jitteredDelay(forAttempt: 10)
            XCTAssertGreaterThanOrEqual(delay, 5)
            XCTAssertLessThanOrEqual(delay, OfflineQueueRetryPolicy.maximumRetryDelay)
        }
    }

    func test_retryScopesKeepScansFastWithoutShorteningMaintenance() async {
        XCTAssertEqual(
            OfflineQueueRetryPolicy.delay(
                forAttempt: 20,
                scope: .scanAnalysis
            ),
            30
        )
        XCTAssertEqual(
            OfflineQueueRetryPolicy.delay(
                forAttempt: 20,
                scope: .maintenance
            ),
            15 * 60
        )
        XCTAssertEqual(
            OfflineQueueRetryPolicy.maximumServerDirectedRetryDelay,
            15 * 60
        )
        XCTAssertEqual(
            OfflineQueueRetryPolicy.scanRetryDelay(
                forAttempt: 1,
                serverMinimumDelay: 120
            ),
            120
        )
        XCTAssertEqual(
            OfflineQueueRetryPolicy.scanRetryDelay(
                forAttempt: 1,
                serverMinimumDelay: 3_600
            ),
            15 * 60
        )
    }
    func test_exponentialBackoff_calculatesAndClampsCorrectly() async {
        let firstDelay = OfflineQueueRetryPolicy.delay(forAttempt: 1)
        let cappedDelay = OfflineQueueRetryPolicy.delay(forAttempt: 20)

        XCTAssertEqual(firstDelay, 5)
        XCTAssertEqual(cappedDelay, OfflineQueueRetryPolicy.maximumRetryDelay)
    }
    func test_runInferencePipeline_keepsTransientFailuresRetryable() async {
        let disposition = OfflineQueueRetryPolicy.classifyUpload(
            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost),
            statusCode: nil,
            currentAttempt: 8
        )

        if case .retry = disposition {
            XCTAssertTrue(true)
        } else {
            XCTFail("Transient network failures should remain retryable while automatic retry budget remains.")
        }
    }

    func test_runInferencePipeline_pausesTransientFailuresAfterRetryBudget() async {
        let disposition = OfflineQueueRetryPolicy.classifyUpload(
            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost),
            statusCode: nil,
            currentAttempt: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
        )

        if case .needsAttention(let code, _) = disposition {
            XCTAssertEqual(code, "automatic_retry_limit_reached")
        } else {
            XCTFail("Transient failures should pause for user attention after the automatic retry budget is exhausted.")
        }
    }

    func test_offlineJobRetryBudget_isSharedByDurableOfflineJobs() async {
        XCTAssertTrue(OfflineQueueRetryPolicy.canScheduleAutomaticRetry(currentAttempt: 0))
        XCTAssertTrue(
            OfflineQueueRetryPolicy.canScheduleAutomaticRetry(
                currentAttempt: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts - 1
            )
        )
        XCTAssertFalse(
            OfflineQueueRetryPolicy.canScheduleAutomaticRetry(
                currentAttempt: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
            )
        )
    }
}
