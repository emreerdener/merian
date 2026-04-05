import SwiftUI

struct ReportInsightView: View {
    // MARK: - Dependencies
    @Environment(\.dismiss) var dismiss
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(\.modelContext) var modelContext
    
    // MARK: - State
    let scanId: String
    var onSubmitted: (() -> Void)?
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
                
                Section(header: Text("Additional details (optional)"), footer: Text("Help us understand the issue so we can fix it.")) {
                    TextField("E.g. The map is showing the wrong location", text: $viewModel.userSuggestion)
                }
            }
            .navigationTitle("Report an issue")
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
            .onChange(of: viewModel.showAlert) { _, isShowing in
                if isShowing {
                    dismiss()
                    onSubmitted?()
                }
            }
        }
    }
}
