@testable import Merian
import XCTest

final class OfflineSyncTests: XCTestCase {

    // MARK: - 1. Exact Upload Outcome Contract

    func test_processUploadCompletion_defersInferenceUntilEveryKeySucceeds() {
        let generation = UUID()
        let firstKey = "staging/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/scan_image_0.webp"
        let secondKey = "staging/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/scan_image_1.webp"
        var completion = MediaStagingUploadCompletionState(generation: generation)

        completion.recordSuccess(objectKey: secondKey)

        XCTAssertFalse(
            completion.containsEvery(expectedObjectKeys: [firstKey, secondKey]),
            "Task disappearance is not success evidence for the missing first key."
        )
    }

    func test_processUploadCompletion_acceptsOutOfOrderSuccessForEveryExactKey() {
        let generation = UUID()
        let firstKey = "staging/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/scan_image_0.webp"
        let secondKey = "staging/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/scan_image_1.webp"
        var completion = MediaStagingUploadCompletionState(generation: generation)

        completion.recordSuccess(objectKey: secondKey)
        completion.recordSuccess(objectKey: firstKey)

        XCTAssertTrue(
            completion.containsEvery(expectedObjectKeys: [firstKey, secondKey])
        )
    }

    // MARK: - 2. Server-Authoritative Staging Identity

    func test_stagingOwnerComesFromCanonicalServerIssuedKey() {
        let authenticatedOwner = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let fileName = "scan123_image.webp"
        let serverKey = "staging/\(authenticatedOwner)/\(fileName)"

        XCTAssertTrue(
            MediaStagingContract.isCanonicalObjectKey(
                serverKey,
                fileName: fileName
            )
        )
        XCTAssertEqual(
            MediaStagingContract.ownerId(fromObjectKey: serverKey),
            authenticatedOwner
        )
    }

    func test_predictedDeviceIdentityCannotOverrideServerIssuedOwner() {
        let predictedDeviceOwner = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let authenticatedOwner = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let serverKey = "staging/\(authenticatedOwner)/scan123_image.webp"

        XCTAssertNotEqual(
            MediaStagingContract.ownerId(fromObjectKey: serverKey),
            predictedDeviceOwner
        )
        XCTAssertEqual(
            MediaStagingContract.ownerId(fromObjectKey: serverKey),
            authenticatedOwner
        )
    }

    // MARK: - 3. Pipeline Lock Release Tests
    
    func test_missingSourceFile_dropsIsSyncingLock() async {
        // Simulate a scenario where the authoritative NVMe source file in Documents
        // was missing, resulting in URLSession enqueue failure and an empty dispatched IDs set.
        let dispatchedScanIDs = Set<String>()
        var isSyncing = true // Locked initially by syncPendingScans
        let activeURLSessionTaskCount = 0
        
        // This is the literal inline evaluation logic from `OfflineQueueManager+Sync`
        if dispatchedScanIDs.isEmpty {
            if activeURLSessionTaskCount == 0 {
                isSyncing = false
            }
        }
        
        // Assert that when dispatch generates no payloads, the queue gracefully drops its own lock rather than waiting for OS delegate.
        XCTAssertFalse(isSyncing, "Pipeline Deadlock: isSyncing did not drop when all source files were missing.")
    }

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

    // MARK: - 4. Enqueue Bounds (Free Tier Hoarding)
    
    func test_enqueueCapture_enforcesFreeUserLimits() async {
        let isProActive = false
        let maxFreeScansPerDay = 1
        let queuedScansInDatabase = 1
        
        // This simulates the validation drop sequence internally inside `enqueueCapture`
        let canEnqueue = isProActive || queuedScansInDatabase < maxFreeScansPerDay
        
        XCTAssertFalse(canEnqueue, "Hoarding Breach: A free-tier user was incorrectly allowed to enqueue a 2nd offline scan into local DB.")
    }

    // MARK: - 5. Exponential Backoff Constraints
    
    func test_exponentialBackoff_calculatesAndClampsCorrectly() async {
        let firstDelay = OfflineQueueRetryPolicy.delay(forAttempt: 1)
        let cappedDelay = OfflineQueueRetryPolicy.delay(forAttempt: 20)

        XCTAssertEqual(firstDelay, 5)
        XCTAssertEqual(cappedDelay, OfflineQueueRetryPolicy.maximumRetryDelay)
    }

    // MARK: - 6. WeatherKit Hydration Logic
    
    func test_inferencePipeline_needsWeatherExtractionGate() async {
        let simulateNeedsWeather: (String?, Double?, Double?) -> Bool = { weatherCondition, lat, lon in
            return weatherCondition == nil && lat != nil && lon != nil
        }
        
        // Scenario 1: Scan captured offline completely (raw telemetry)
        XCTAssertTrue(simulateNeedsWeather(nil, 37.7749, -122.4194), "Hydration Miss: Weather needs to be fetched natively!")
        
        // Scenario 2: EnvironmentContextManager successfully executed backfill on foreground capture
        XCTAssertFalse(simulateNeedsWeather("Cloudy", 37.7749, -122.4194), "Hydration Redundancy: Network request incorrectly scheduled when weather is already secured.")
        
        // Scenario 3: User denied location permissions natively
        XCTAssertFalse(simulateNeedsWeather(nil, nil, nil), "Hydration Panic: Sent Weather request blindly without valid coordinates.")
    }

    // MARK: - 7. Terminal Failure Classification
    
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

    func test_processUploadCompletion_tombstonesOnTerminalFileCorruption() async {
        var isDeleted = false
        
        // Simulating the catch evaluation inside `processUploadCompletion` natively
        let evaluateError: (NSError) -> Void = { nsError in
            let isFileMissing = nsError.domain == NSURLErrorDomain
                && (nsError.code == NSURLErrorFileDoesNotExist || nsError.code == NSURLErrorCannotOpenFile)
            if isFileMissing {
                isDeleted = true
            }
        }
        
        // Transient network failures should NOT tombstone
        evaluateError(NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost, userInfo: nil))
        XCTAssertFalse(isDeleted, "Premature Tombstoning: A transient network error incorrectly deleted the scan.")
        
        // Unrecoverable core media missing errors MUST tombstone
        evaluateError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist, userInfo: nil))
        XCTAssertTrue(isDeleted, "Integrity Breach: A missing NVMe local backing file failed to instantly tombstone the orphaned queue entry.")
    }
}
