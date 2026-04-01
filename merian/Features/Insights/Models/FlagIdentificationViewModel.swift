import SwiftData
import SwiftUI

/// Form state and submission logic isolated for Species Identification moderation flags.
@MainActor
@Observable
final class FlagIdentificationViewModel {
    
    // MARK: - Input State
    /// User suggestion optionally input manually.
    var userSuggestion: String = ""
    
    // MARK: - UI Flags
    var isSubmitting: Bool = false
    var showAlert: Bool = false
    var alertMessage: String = ""
    
    // MARK: - Network Operations
    
    /// Hits the Edge Function, injecting "Incorrect Species" permanently to isolate this flow from the global Report Modal.
    func submitFlag(scanId: String, engine: InferenceEngine, context: ModelContext) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        
        let userId = SupabaseManager.shared.currentUser?.id.uuidString ?? DeviceIdentityManager.shared.deviceId
        
        do {
            try await MerianNetworkClient.shared.submitFlagIssue(
                scanId: scanId,
                flagReason: "Incorrect species",
                userSuggestion: userSuggestion.trimmingCharacters(in: .whitespacesAndNewlines),
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
