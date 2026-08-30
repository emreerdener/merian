import SwiftUI

struct DescribePromptTagsView: View {
    @Bindable var promptViewModel: DescribePromptViewModel
    let tagFrequency: @MainActor (_ tagId: String) -> Int
    let selectionFeedback: @MainActor () -> Void
    let onSelectTag: @MainActor (_ tag: GuidedQuestion.Tag) -> Void
    let onAdvanceQuestion: @MainActor () -> Void

    @State private var pendingAutoAdvance: PendingAutoAdvance?

    private struct PendingAutoAdvance: Equatable {
        let id = UUID()
        let questionIndex: Int
    }

    private var sortedTags: [GuidedQuestion.Tag] {
        guard promptViewModel.activeQuestions.indices.contains(
            promptViewModel.activeQuestionIndex
        ) else {
            return []
        }
        let tags = promptViewModel.activeQuestions[
            promptViewModel.activeQuestionIndex
        ].tags
        let frequencies = tags.reduce(into: [String: Int]()) { result, tag in
            result[tag.tagId] = tagFrequency(tag.tagId)
        }
        return DescribeTagRanking.ranked(tags, frequencies: frequencies)
    }

    var body: some View {
        if promptViewModel.activeQuestions.indices.contains(
            promptViewModel.activeQuestionIndex
        ) {
            Text(promptViewModel.currentPrompt)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 35, alignment: .topLeading)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sortedTags, id: \.self) { tag in
                    let isSelectedSubject =
                        promptViewModel.activeQuestionIndex == 0
                        && tag.tagId == promptViewModel.activeSubjectId
                    Button {
                        selectionFeedback()
                        let questionIndex = promptViewModel.activeQuestionIndex
                        onSelectTag(tag)

                        guard !isSelectedSubject else { return }
                        if !promptViewModel.interactedQuestionIndices.contains(
                            questionIndex
                        ) {
                            promptViewModel.interactedQuestionIndices.insert(
                                questionIndex
                            )
                            pendingAutoAdvance = PendingAutoAdvance(
                                questionIndex: questionIndex
                            )
                        }
                    } label: {
                        DescribeTagView(
                            tag: tag,
                            isSelectedSubject: isSelectedSubject
                        )
                    }
                    .transition(.opacity)
                }
            }
            .animation(
                .easeInOut(duration: 0.3),
                value: promptViewModel.activeQuestionIndex
            )
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .padding(.bottom, 16)
        .task(id: pendingAutoAdvance?.id) {
            guard let request = pendingAutoAdvance else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  pendingAutoAdvance?.id == request.id,
                  promptViewModel.activeQuestionIndex == request.questionIndex
            else {
                return
            }
            pendingAutoAdvance = nil
            onAdvanceQuestion()
        }
    }
}

private struct DescribeTagView: View {
    let tag: GuidedQuestion.Tag
    let isSelectedSubject: Bool

    var body: some View {
        if let imageName = tag.imageName {
            VStack(spacing: 4) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                Text(tag.label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(
                isSelectedSubject
                    ? Color(UIColor.systemBackground)
                    : .primary
            )
            .frame(width: 96, height: 112)
            .background(
                isSelectedSubject
                    ? Color.primary
                    : Color(UIColor.secondarySystemBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Text(tag.label)
                .font(.subheadline)
                .foregroundStyle(
                    isSelectedSubject
                        ? Color(UIColor.systemBackground)
                        : .primary
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    isSelectedSubject
                        ? Color.primary
                        : Color(UIColor.secondarySystemBackground)
                )
                .clipShape(Capsule())
        }
    }
}
