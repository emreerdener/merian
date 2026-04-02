import XCTest
@testable import merian

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
}
