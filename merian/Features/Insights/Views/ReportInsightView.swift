import SwiftUI

struct ReportInsightView: View {
    // MARK: - Dependencies
    @Environment(\.dismiss) var dismiss
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(\.modelContext) var modelContext
    
    // MARK: - State
    let scanId: String
    @State private var viewModel = ReportInsightViewModel()

    // MARK: - View
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("What went wrong?")) {
                    Picker("Reason", selection: $viewModel.flagReason) {
                        ForEach(viewModel.reasons, id: \.self) { reason in
                            Text(reason).tag(reason)
                        }
                    }
                }
                
                Section(header: Text("Your suggestion (optional)"), footer: Text("Help us improve Merian by suggesting what you think it actually is.")) {
                    TextField("E.g. Monarch Butterfly", text: $viewModel.userSuggestion)
                }
            }
            .navigationTitle("Report incorrect ID")
            .navigationBarTitleDisplayMode(.inline)
            
            // MARK: Actions
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { 
                        Task { await viewModel.submitFlag(scanId: scanId, engine: inferenceEngine, context: modelContext) }
                    }
                    .disabled(viewModel.isSubmitting)
                }
            }
            .alert("Report status", isPresented: $viewModel.showAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text(viewModel.alertMessage)
            }
        }
    }
}
