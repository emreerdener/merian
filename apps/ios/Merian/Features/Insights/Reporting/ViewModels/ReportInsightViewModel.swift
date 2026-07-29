import SwiftData
import SwiftUI
@MainActor
@Observable
final class ReportInsightViewModel {
    typealias IssueSubmitter = @MainActor (
        _ scanId: String,
        _ flagReason: String,
        _ userSuggestion: String,
        _ userId: String
    ) async throws -> Void

    @ObservationIgnored private let issueSubmitter: IssueSubmitter
    
    // MARK: - Input State
    var flagReason: String = "Inappropriate content"
    var userSuggestion: String = ""
    
    // MARK: - UI Flags
    var isSubmitting: Bool = false
    var showAlert: Bool = false
    var alertMessage: String = ""
    
    // MARK: - Constants
    let reasons = ["Inappropriate content", "Bad image quality", "Other"]

    init(
        issueSubmitter: @escaping IssueSubmitter = { scanId, flagReason, userSuggestion, userId in
            try await MerianNetworkClient.shared.submitFlagIssue(
                scanId: scanId,
                flagReason: flagReason,
                userSuggestion: userSuggestion,
                userId: userId
            )
        }
    ) {
        self.issueSubmitter = issueSubmitter
    }
    
    // MARK: - Network Operations
    func submitFlag(scanId: String, engine: InferenceEngine, context: ModelContext) async {
        guard !isSubmitting,
              engine.speciesData?.scanId?.caseInsensitiveCompare(scanId) == .orderedSame else {
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        
        let userId = SupabaseManager.shared.currentUser?.id.uuidString ?? DeviceIdentityManager.shared.deviceId
        let submittedReason = flagReason
        let submittedSuggestion = userSuggestion
        let presentationGeneration = engine.scanPresentationGeneration
        
        // 1. Immediately toggle local UI state and persist offline-first Flag
        await engine.flagAIIdentification(
            expectedScanId: scanId,
            modelContext: context
        )
        
        do {
            try await issueSubmitter(
                scanId,
                submittedReason,
                submittedSuggestion,
                userId
            )
        } catch {
            // If the scan is pending offline upload, `flagged_reviews` FK insertion fails natively.
            // Safely treat the action as accepted because `isFlagged` was toggled on the
            // exact LocalScanRecord and will sync through OfflineQueueManager.
        }

        guard engine.scanPresentationGeneration == presentationGeneration,
              engine.speciesData?.scanId?
                .caseInsensitiveCompare(scanId) == .orderedSame else {
            return
        }

        alertMessage = "Thank you! Your feedback helps us improve Naturebook's AI."
        showAlert = true
    }
}
