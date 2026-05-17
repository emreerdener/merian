import SwiftUI

// MARK: - Describe Questions Table of Contents
/// A modal sheet that presents the full table of contents for Describe-mode prompts.
///
/// Mutates `promptManager.activeQuestionIndex` directly via @Binding, which
/// triggers a re-render of the parent `DescribeInputView` automatically.
struct DescribeQuestionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var promptManager: DescribePromptManager
    var hasInputs: Bool
    var onReset: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(promptManager.activeQuestions.enumerated()), id: \.element.prompt) { idx, _ in
                    Button(action: {
                        HapticManager.shared.triggerSelectionPulse()
                        promptManager.activeQuestionIndex = idx
                        dismiss()
                    }) {
                        HStack {
                            Text(promptManager.displayPrompt(at: idx))
                                .font(.body)
                                .foregroundColor(.primary)
                            Spacer()
                            if idx == promptManager.activeQuestionIndex {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.primary)
                                    .fontWeight(.bold)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Prompts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if hasInputs {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Reset") {
                            onReset?()
                            dismiss()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .presentationDetents([.medium, .large])
    }
}
