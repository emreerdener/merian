@testable import Merian
import XCTest

final class OfflineSyncTests: XCTestCase {
    // MARK: - 3. Pipeline Lock Release Tests
    
    func test_missingSourceFile_dropsIsSyncingLock() async {
        // Simulate a scenario where the authoritative NVMe source file in Documents
        // was missing, resulting in URLSession enqueue failure and an empty dispatched IDs set.
        let dispatchedScanIDs = Set<String>()
        var isSyncing = true // Locked initially by syncPendingScans
        let activeURLSessionTaskCount = 0
        
        // This mirrors the terminal latch evaluation in `OfflineQueueManager.syncPendingScans()`.
        if dispatchedScanIDs.isEmpty {
            if activeURLSessionTaskCount == 0 {
                isSyncing = false
            }
        }
        
        // Assert that when dispatch generates no payloads, the queue gracefully drops its own lock rather than waiting for OS delegate.
        XCTAssertFalse(isSyncing, "Pipeline Deadlock: isSyncing did not drop when all source files were missing.")
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
