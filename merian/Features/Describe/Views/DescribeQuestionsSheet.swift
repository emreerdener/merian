import SwiftUI

// MARK: - Describe Questions Table of Contents
/// A modal sheet that presents the full table of contents for Describe-mode prompts.
///
/// Users can select a specific question from the list, which immediately
/// synchronizes with the `DescribePromptManager` to update the central UI block,
/// acting as a quick-jump mechanism for the identification interview.
struct DescribeQuestionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var promptManager: DescribePromptManager
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(guidedQuestions.enumerated()), id: \.offset) { idx, question in
                    Button(action: {
                        HapticManager.shared.triggerSelectionPulse()
                        withAnimation(.easeInOut(duration: 0.4)) {
                            promptManager.activeQuestionIndex = idx
                        }
                        dismiss()
                    }) {
                        HStack {
                            Text(question.prompt)
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
            .listStyle(.insetGrouped)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                   Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
