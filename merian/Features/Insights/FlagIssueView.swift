import SwiftUI

struct FlagIssueView: View {
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
            let payload: [String: Any] = [
                "scanId": scanId,
                "userId": userId,
                "flagReason": flagReason,
                "userSuggestion": userSuggestion.isEmpty ? "" : userSuggestion
            ]
            
            do {
                guard let url = URL(string: "\(MerianEnvironment.supabaseUrl)/functions/v1/flag-issue") else {
                    throw URLError(.badURL)
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let jwt = try await SupabaseManager.shared.getActiveJWT()
                request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
                request.setValue(MerianEnvironment.supabaseAnonKey, forHTTPHeaderField: "apikey")
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                
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
