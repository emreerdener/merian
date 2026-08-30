import SwiftUI

// MARK: - Describe Questions Table of Contents
/// A modal sheet that presents the full table of contents for Describe-mode prompts.
///
/// Mutates the observable prompt view model, which re-renders the page and sheet.
struct DescribeQuestionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let promptViewModel: DescribePromptViewModel
    let hasInputs: Bool
    let onReset: (() -> Void)?
    private let selectionFeedback: @MainActor () -> Void

    @MainActor
    init(
        promptViewModel: DescribePromptViewModel,
        hasInputs: Bool,
        onReset: (() -> Void)?
    ) {
        self.init(
            promptViewModel: promptViewModel,
            hasInputs: hasInputs,
            onReset: onReset,
            selectionFeedback: DescribePresentationDependencies.live
                .selectionFeedback
        )
    }

    @MainActor
    init(
        promptViewModel: DescribePromptViewModel,
        hasInputs: Bool,
        onReset: (() -> Void)?,
        selectionFeedback: @escaping @MainActor () -> Void
    ) {
        self.promptViewModel = promptViewModel
        self.hasInputs = hasInputs
        self.onReset = onReset
        self.selectionFeedback = selectionFeedback
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(
                    Array(promptViewModel.activeQuestions.enumerated()),
                    id: \.element.prompt
                ) { index, _ in
                    Button(action: {
                        selectionFeedback()
                        promptViewModel.activeQuestionIndex = index
                        dismiss()
                    }) {
                        HStack {
                            Text(promptViewModel.displayPrompt(at: index))
                                .font(.body)
                                .foregroundColor(.primary)
                            Spacer()
                            if index == promptViewModel.activeQuestionIndex {
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
