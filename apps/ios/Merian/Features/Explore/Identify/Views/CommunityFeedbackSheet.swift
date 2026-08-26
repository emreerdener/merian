import SwiftUI

struct CommunityFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CommunityFeedbackViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                if viewModel.showSuccess {
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
                    .disabled(viewModel.isSubmitting)
                }
            }
            .alert(
                "Submission Failed",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Please check your network and try again.")
            }
            .onChange(of: viewModel.feedbackText) { _, _ in
                if viewModel.validationError != nil {
                    withAnimation(.snappy(duration: 0.2)) {
                        viewModel.feedbackDidChange()
                    }
                }
            }
        }
    }

    private var formContent: some View {
        @Bindable var viewModel = viewModel

        return ScrollView {
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
                    TextField(
                        "Share your thoughts, suggestions, or issues...",
                        text: $viewModel.feedbackText,
                        axis: .vertical
                    )
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
                        Text(
                            "\(viewModel.feedbackText.count)/\(CommunityFeedbackViewModel.maxCharacterLimit)"
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            viewModel.feedbackText.count > CommunityFeedbackViewModel.maxCharacterLimit
                                ? .red
                                : .secondary
                        )
                        .monospacedDigit()
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)

                if let validationError = viewModel.validationError {
                    Text(validationError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Button(action: submitFeedback) {
                    HStack {
                        if viewModel.isSubmitting {
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
                .disabled(viewModel.isSubmitting)
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
        let isPrepared = withAnimation(.snappy(duration: 0.2)) {
            viewModel.prepareSubmission()
        }
        guard isPrepared else { return }
        viewModel.beginSubmission()

        Task {
            guard await viewModel.submitPreparedFeedback() else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                viewModel.showSubmissionSuccess()
            }
        }
    }
}
