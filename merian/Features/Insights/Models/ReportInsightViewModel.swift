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
    func submitFlag(scanId: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        
        let userId = DeviceIdentityManager.shared.deviceId
        
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
            alertMessage = "Failed to submit report. Please try again later."
            showAlert = true
            isSubmitting = false
        }
    }
}
