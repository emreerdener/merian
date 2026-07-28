import SwiftUI

struct CommunityFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackText = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var validationError: String?

    private let maxCharacterLimit = 4000

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                if showSuccess {
                    successContent
                } else {
                    formContent
                }
            }
            .navigationTitle("Feature feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .disabled(isSubmitting)
                }
            }
            .alert("Submission Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please check your network and try again.")
            }
            .onChange(of: feedbackText) { _, _ in
                if validationError != nil {
                    withAnimation(.snappy(duration: 0.2)) {
                        validationError = nil
                    }
                }
            }
        }
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Help improve community identification")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("What would make this section more helpful, clearer, or easier to use?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Share your thoughts, suggestions, or issues...", text: $feedbackText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .lineLimit(6...12)
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )

                    HStack {
                        Spacer()
                        Text("\(feedbackText.count)/\(maxCharacterLimit)")
                            .font(.caption2)
                            .foregroundStyle(feedbackText.count > maxCharacterLimit ? .red : .secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)

                if let validationError {
                    Text(validationError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Button(action: submitFeedback) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Submit feedback")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSubmitting)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }

    private var successContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Thank you!")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                Text("Your feedback has been saved and shared with the Naturebook team.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func submitFeedback() {
        let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            withAnimation(.snappy(duration: 0.2)) {
                validationError = "Feedback cannot be empty."
            }
            HapticManager.shared.triggerErrorThump()
            return
        }
        if feedbackText.count > maxCharacterLimit {
            withAnimation(.snappy(duration: 0.2)) {
                validationError = "Feedback is too long (maximum \(maxCharacterLimit) characters)."
            }
            HapticManager.shared.triggerErrorThump()
            return
        }

        withAnimation(.snappy(duration: 0.2)) {
            validationError = nil
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                try await MerianNetworkClient.shared.submitCommunityFeedback(feedback: trimmed)
                await MainActor.run {
                    isSubmitting = false
                    HapticManager.shared.triggerSuccessPulse()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showSuccess = true
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    HapticManager.shared.triggerErrorThump()
                    errorMessage = ExploreErrorFormatter.message(for: error)
                }
            }
        }
    }
}
