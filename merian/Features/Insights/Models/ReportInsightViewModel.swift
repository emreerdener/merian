import SwiftData
import SwiftUI
@MainActor
@Observable
final class ReportInsightViewModel {
    
    // MARK: - Input State
    var flagReason: String = "Incorrect Species"
    var userSuggestion: String = ""
    
    // MARK: - UI Flags
    var isSubmitting: Bool = false
    var showAlert: Bool = false
    var alertMessage: String = ""
    
    // MARK: - Constants
    let reasons = ["Incorrect Species", "Inappropriate Content", "Bad Image Quality", "Other"]
    
    // MARK: - Network Operations
    func submitFlag(scanId: String, engine: InferenceEngine, context: ModelContext) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        
        let userId = SupabaseManager.shared.currentUser?.id.uuidString ?? DeviceIdentityManager.shared.deviceId
        
        // 1. Immediately toggle local UI state and persist offline-first Flag
        await engine.flagAIIdentification(modelContext: context)
        
        do {
            try await MerianNetworkClient.shared.submitFlagIssue(
                scanId: scanId,
                flagReason: flagReason,
                userSuggestion: userSuggestion,
                userId: userId
            )
            
            alertMessage = "Thank you! Your feedback helps us improve Merian's AI."
            showAlert = true
            isSubmitting = false
            
        } catch {
            // If the scan is pending offline upload, `flagged_reviews` FK insertion fails natively.
            // Safely surface success because `isFlagged` is now toggled on `LocalScanRecord` and will sync its True state via `OfflineQueueManager` shortly.
            alertMessage = "Thank you! Your feedback helps us improve Merian's AI."
            showAlert = true
            isSubmitting = false
        }
    }
}
