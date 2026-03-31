import SwiftUI

struct FlagIdentificationModal: View {
    // MARK: - Dependencies
    @Environment(\.dismiss) var dismiss
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(\.modelContext) var modelContext
    
    // MARK: - State
    let scanId: String
    @State private var viewModel = FlagIdentificationViewModel()
    @State private var playFlagAnimation = false
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Header Illustration
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "flag.fill")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(.orange)
                                .symbolEffect(.bounce, value: playFlagAnimation)
                                .onAppear { playFlagAnimation.toggle() }
                        }
                        .padding(.top, 24)
                        
                        Text("Flag for Review")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Does this AI identification seem incorrect? By flagging it, you help human moderators review the scan and train better models.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    
                    // Input Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What is it actually? (Optional)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        TextField("e.g. Monarch Butterfly, or 'Just a leaf'", text: $viewModel.userSuggestion)
                            .padding(16)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                            )
                            .font(.body)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.secondary)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        HapticManager.shared.triggerMediumPulse()
                        Task { await viewModel.submitFlag(scanId: scanId, engine: inferenceEngine, context: modelContext) }
                    }) {
                        if viewModel.isSubmitting {
                            ProgressView()
                                .tint(.orange)
                        } else {
                            Text("Submit")
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                    }
                    .disabled(viewModel.isSubmitting)
                }
            }
            // Alert on success
            .alert("Flag Submitted", isPresented: $viewModel.showAlert) {
                Button("Got it", role: .cancel) { dismiss() }
            } message: {
                Text(viewModel.alertMessage)
            }
        }
    }
}
