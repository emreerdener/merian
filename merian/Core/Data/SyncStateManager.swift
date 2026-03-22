import Foundation
import Observation

// MARK: - Core Cloud Synchronization State
@MainActor
@Observable final class SyncStateManager {
    // MARK: - Singleton Architecture
    static let shared = SyncStateManager()
    
    // MARK: - State Management
    var isSyncing: Bool = false
    var pendingUploadCount: Int = 0
    
    // MARK: - Lifecycle
    private init() {}
    
    // MARK: - Sync Pipelines
    func beginSync(itemCount: Int) {
        self.pendingUploadCount = itemCount
        self.isSyncing = true
    }
    
    func completeSync() {
        self.isSyncing = false
        self.pendingUploadCount = 0
    }
}
