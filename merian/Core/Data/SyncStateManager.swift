import Foundation

@MainActor
final class SyncStateManager: ObservableObject {
    static let shared = SyncStateManager()
    
    @Published var isSyncing: Bool = false
    @Published var pendingUploadCount: Int = 0
    
    private init() {}
    
    func beginSync(itemCount: Int) {
        self.pendingUploadCount = itemCount
        self.isSyncing = true
    }
    
    func completeSync() {
        self.isSyncing = false
        self.pendingUploadCount = 0
    }
}
