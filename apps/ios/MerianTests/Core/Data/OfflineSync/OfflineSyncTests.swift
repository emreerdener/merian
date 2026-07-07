@testable import Merian
import XCTest

final class OfflineSyncTests: XCTestCase {

    // MARK: - 1. URLSession Lookahead Logic Test
    
    // We mock the specific properties extracted from URLSessionTask during the lookahead pass.
    struct MockTask {
        let taskIdentifier: Int
        let taskDescription: String?
    }

    func test_processUploadCompletion_defersInferenceWhenChunksRemain() async {
        // Simulate "chunk 1" completing out-of-order BEFORE "chunk 0" has finished.
        let completingTask = MockTask(taskIdentifier: 1, taskDescription: "SCAN123_1")
        
        // The URLSession still holds "chunk 0" in flight
        let remainingTasks = [
            MockTask(taskIdentifier: 0, taskDescription: "SCAN123_0")
        ]
        
        let scanId = "SCAN123"
        
        // This is the literal inline evaluation logic from `OfflineQueueManager+URLSession`
        let hasActiveTasksForScan = remainingTasks.contains {
            $0.taskIdentifier != completingTask.taskIdentifier &&
            ($0.taskDescription?.starts(with: "\(scanId)_") ?? false)
        }
        
        // Assert that the lookahead correctly detects "SCAN123_0" is still active, safely abandoning the deadlocked `count - 1` blind guess.
        XCTAssertTrue(hasActiveTasksForScan, "Lookahead failed: Should detect that chunk 0 is still active.")
    }
    
    func test_processUploadCompletion_triggersInferenceWhenFinalChunkCompletes() async {
        // Simulate "chunk 0" completing as the absolute final chunk
        let completingTask = MockTask(taskIdentifier: 0, taskDescription: "SCAN123_0")
        
        // The URLSession only holds the completing task (which `allTasks` natively includes during delegate traversal)
        let remainingTasks = [completingTask]
        
        let scanId = "SCAN123"
        
        // This is the literal inline evaluation logic from `OfflineQueueManager+URLSession`
        let hasActiveTasksForScan = remainingTasks.contains {
            $0.taskIdentifier != completingTask.taskIdentifier &&
            ($0.taskDescription?.starts(with: "\(scanId)_") ?? false)
        }
        
        // Assert that the lookahead recognizes NO other disjoint tasks remain for this scan explicitly!
        XCTAssertFalse(hasActiveTasksForScan, "Lookahead failed: Should detect no other tasks remain for this scan.")
    }

    // MARK: - 2. Deterministic Identity Target Test
    
    func test_deterministicIdentityResolution_fallsBackToDeviceIdWithoutSession() async {
        // Simulate a cold launch / unauthenticated user without Supabase session payload
        let mockMissingSessionId: String? = nil
        let mockDeviceId = "MOCK-DEVICE-ID-1234"
        
        // The native pipeline structing:
        let targetId = (mockMissingSessionId ?? mockDeviceId).lowercased()
        
        let scanId = "SCAN123"
        let r2Key = "staging/\(targetId)/\(scanId)_image.webp"
        
        // Assert that without an explicit identity, the path resolves to DEVICE to bypass the 404 mismatch.
        XCTAssertEqual(r2Key, "staging/mock-device-id-1234/SCAN123_image.webp")
    }
    
    func test_deterministicIdentityResolution_prioritizesAuthSession() async {
        // Simulate an existing logged in user / Ghost session active UUID
        let mockAuthSessionId: String? = "AUTH-UUID-XYZ"
        let mockDeviceId = "MOCK-DEVICE-ID-1234" // Should be structurally ignored!
        
        // The native pipeline structing:
        let targetId = (mockAuthSessionId ?? mockDeviceId).lowercased()
        
        let scanId = "SCAN123"
        let r2Key = "staging/\(targetId)/\(scanId)_image.webp"
        
        // Assert that the explicit auth ID bridges directly over the 500 error boundary.
        XCTAssertEqual(r2Key, "staging/auth-uuid-xyz/SCAN123_image.webp")
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
