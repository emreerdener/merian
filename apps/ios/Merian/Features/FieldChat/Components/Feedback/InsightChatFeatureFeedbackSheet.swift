import SwiftUI

struct InsightChatFeatureFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var textIsFocused: Bool
    @State private var selectedSentiment: InsightChatFeatureFeedbackSentiment?
    @State private var feedbackText = ""

    let onSelectionFeedback: () -> Void
    let onSubmit: (InsightChatFeatureFeedbackSentiment?, String) -> Void

    private var trimmedFeedbackText: String {
        feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        selectedSentiment != nil || !trimmedFeedbackText.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("How is Field chat working?")
                    .font(.title3.weight(.semibold))

                sentimentPicker

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $feedbackText)
                        .focused($textIsFocused)
                        .frame(minHeight: 150)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                        )

                    if feedbackText.isEmpty {
                        Text("Tell us what felt good, confusing, wrong, or missing.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .navigationTitle("Give feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        onSubmit(selectedSentiment, trimmedFeedbackText)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSubmit)
                }
            }
            .onAppear {
                textIsFocused = true
            }
        }
        .presentationBackground(Color(uiColor: .systemBackground))
    }

    private var sentimentPicker: some View {
        HStack(spacing: 10) {
            ForEach(InsightChatFeatureFeedbackSentiment.allCases, id: \.self) { sentiment in
                Button {
                    onSelectionFeedback()
                    selectedSentiment = sentiment
                } label: {
                    Label(sentiment.title, systemImage: sentiment.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(sentiment == selectedSentiment
                                      ? Color.accentColor.opacity(0.16)
                                      : Color(uiColor: .secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    sentiment == selectedSentiment
                                        ? Color.accentColor.opacity(0.45)
                                        : Color.primary.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(sentiment == selectedSentiment ? Color.accentColor : Color.primary)
            }
        }
    }
}
