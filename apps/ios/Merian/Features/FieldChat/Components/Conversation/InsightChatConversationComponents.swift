import SwiftUI

struct InsightChatIdentificationReviewActions {
    let onReviewAlternatives: (() -> Void)?
    let onReanalyzeSpecies: (() -> Void)?
}

struct InsightChatBubble: View {
    let message: InsightChatMessage
    let scientificNames: [String]
    let isLastMessage: Bool
    let feedbackRating: InsightChatFeedbackRating?
    let identificationReviewActions: InsightChatIdentificationReviewActions?
    let onAction: (InsightChatReplyAction) -> Void
    let onPositiveFeedback: () -> Void
    let onNegativeFeedback: () -> Void

    private var isUser: Bool {
        message.role == .user
    }

    private var formattedText: AttributedString {
        InsightChatMessageFormatter.formattedText(
            message.text,
            scientificNames: scientificNames
        )
    }

    var body: some View {
        if isUser {
            HStack {
                Spacer(minLength: 44)

                Text(formattedText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if message.isRefusal {
                    Label("Safe field guidance", systemImage: "shield.lefthalf.filled")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(formattedText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if let identificationReviewActions {
                    InsightChatIdentificationReviewPanel(actions: identificationReviewActions)
                        .padding(.top, 4)
                }

                InsightChatAnswerControls(
                    feedbackRating: feedbackRating,
                    onPositiveFeedback: onPositiveFeedback,
                    onNegativeFeedback: onNegativeFeedback,
                    onCopy: {
                        onAction(.copyAnswer)
                    }
                )

                if isLastMessage {
                    Text("Naturebook AI can make mistakes.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

}

private struct InsightChatIdentificationReviewPanel: View {
    let actions: InsightChatIdentificationReviewActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Review identification", systemImage: "checkmark.seal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Compare the saved alternatives or add more evidence for a fresh pass.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let onReviewAlternatives = actions.onReviewAlternatives {
                    actionButton(
                        title: "Review alternatives",
                        systemImage: "person.fill.checkmark.and.xmark",
                        action: onReviewAlternatives
                    )
                }

                if let onReanalyzeSpecies = actions.onReanalyzeSpecies {
                    actionButton(
                        title: "Reanalyze species",
                        systemImage: "arrow.2.circlepath",
                        action: onReanalyzeSpecies
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
    }

    private func actionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

struct InsightChatPendingUserBubble: View {
    let message: PendingInsightChatMessage
    let scientificNames: [String]
    let onRetry: () -> Void
    let onEdit: () -> Void

    private var formattedText: AttributedString {
        InsightChatMessageFormatter.formattedText(
            message.text,
            scientificNames: scientificNames
        )
    }

    var body: some View {
        HStack {
            Spacer(minLength: 44)

            VStack(alignment: .trailing, spacing: 6) {
                Text(formattedText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                    )
                    .textSelection(.enabled)

                if case .failed(let reason) = message.deliveryState {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("Edit", action: onEdit)
                            Button("Try again", action: onRetry)
                                .fontWeight(.semibold)
                        }
                        .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct InsightChatAnswerControls: View {
    let feedbackRating: InsightChatFeedbackRating?
    let onPositiveFeedback: () -> Void
    let onNegativeFeedback: () -> Void
    let onCopy: () -> Void

    @State private var copyConfirmationToken: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                copyControl

                feedbackControls
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
        .task(id: copyConfirmationToken) {
            guard let copyConfirmationToken else { return }
            do {
                try await Task.sleep(for: .milliseconds(1_400))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  self.copyConfirmationToken == copyConfirmationToken else {
                return
            }
            withAnimation(.easeOut(duration: 0.18)) {
                self.copyConfirmationToken = nil
            }
        }
    }

    private var copyControl: some View {
        HStack(spacing: 8) {
            Button {
                showCopyConfirmation()
                onCopy()
            } label: {
                Image(systemName: "square.on.square")
            }
            .accessibilityLabel("Copy answer")

            if copyConfirmationToken != nil {
                Text("Copied")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var feedbackControls: some View {
        if let feedbackRating {
            Label(feedbackRating == .helpful ? "Helpful" : "Feedback sent", systemImage: "checkmark.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 14) {
                Button(action: onPositiveFeedback) {
                    Image(systemName: "hand.thumbsup")
                }
                .accessibilityLabel("Mark answer helpful")

                Button(action: onNegativeFeedback) {
                    Image(systemName: "hand.thumbsdown")
                }
                .accessibilityLabel("Report answer")
            }
        }
    }

    private func showCopyConfirmation() {
        withAnimation(.easeOut(duration: 0.16)) {
            copyConfirmationToken = UUID()
        }
    }
}

private enum InsightChatMessageFormatter {
    static func formattedText(_ text: String, scientificNames: [String]) -> AttributedString {
        let cleaned = textByRemovingScientificNameMarkers(from: text)
        var result = AttributedString(cleaned.text)

        for scientificName in uniqueNames(scientificNames + cleaned.markedScientificNames) {
            applyMonospacedStyle(to: &result, matching: scientificName)
        }

        return result
    }

    private static func textByRemovingScientificNameMarkers(
        from text: String
    ) -> (text: String, markedScientificNames: [String]) {
        var output = ""
        var markedScientificNames: [String] = []
        var cursor = text.startIndex

        while let opening = text[cursor...].firstIndex(of: "*") {
            let afterOpening = text.index(after: opening)
            guard let closing = text[afterOpening...].firstIndex(of: "*") else { break }

            let candidate = String(text[afterOpening..<closing])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            output += String(text[cursor..<opening])
            if isLikelyScientificName(candidate) {
                output += candidate
                markedScientificNames.append(candidate)
            } else {
                output += "*" + candidate + "*"
            }

            cursor = text.index(after: closing)
        }

        output += String(text[cursor...])
        return (output, markedScientificNames)
    }

    private static func isLikelyScientificName(_ text: String) -> Bool {
        let words = text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard (2...4).contains(words.count),
              let firstCharacter = words.first?.first,
              firstCharacter.isUppercase else {
            return false
        }

        return words.dropFirst().allSatisfy { word in
            let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]{}"))
            guard let firstCharacter = trimmed.first else { return false }
            return firstCharacter.isLowercase || firstCharacter == "x" || firstCharacter == "×"
        }
    }

    private static func uniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.compactMap { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private static func applyMonospacedStyle(to text: inout AttributedString, matching scientificName: String) {
        var searchRange = text.startIndex..<text.endIndex
        while let range = text[searchRange].range(of: scientificName, options: .caseInsensitive) {
            text[range].font = .system(.body, design: .monospaced)
            searchRange = range.upperBound..<text.endIndex
        }
    }
}

struct InsightChatAssistantLoadingBubble: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text("Thinking")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Field chat is thinking")
    }
}
