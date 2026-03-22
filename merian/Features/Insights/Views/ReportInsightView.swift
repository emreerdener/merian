import SwiftUI

struct ReportInsightView: View {
    @Environment(\.dismiss) var dismiss
    
    let scanId: String
    
    @State private var flagReason: String = "Incorrect Species"
    @State private var userSuggestion: String = ""
    @State private var isSubmitting: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    let reasons = ["Incorrect Species", "Inappropriate Content", "Bad Image Quality", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("What went wrong?")) {
                    Picker("Reason", selection: $flagReason) {
                        ForEach(reasons, id: \.self) { reason in
                            Text(reason).tag(reason)
                        }
                    }
                }
                
                Section(header: Text("Your Suggestion (Optional)"), footer: Text("Help us improve Merian by suggesting what you think it actually is.")) {
                    TextField("E.g. Monarch Butterfly", text: $userSuggestion)
                }
            }
            .navigationTitle("Report Incorrect ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submitFlag() }
                        .disabled(isSubmitting)
                }
            }
            .alert("Report Status", isPresented: $showAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func submitFlag() {
        isSubmitting = true
        
        Task {
            let userId = DeviceIdentityManager.shared.deviceId
            do {
                try await MerianNetworkClient.shared.submitFlagIssue(
                    scanId: scanId,
                    flagReason: flagReason,
                    userSuggestion: userSuggestion,
                    userId: userId
                )
                
                await MainActor.run {
                    alertMessage = "Thank you! Your feedback helps us improve Merian's AI."
                    showAlert = true
                    isSubmitting = false
                }
                
            } catch {
                await MainActor.run {
                    alertMessage = "Failed to submit report. Please try again later."
                    showAlert = true
                    isSubmitting = false
                }
            }
        }
    }
}
