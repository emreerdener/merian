import Foundation

enum DescribeTextComposer {
    static func applying(
        _ tag: GuidedQuestion.Tag,
        to text: String,
        isRemoving: Bool
    ) -> String {
        isRemoving
            ? removing(tag.aiText, from: text)
            : appending(tag.aiText, to: text)
    }

    static func dictationText(
        baseText: String,
        transcription: String
    ) -> String? {
        guard !transcription.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return nil
        }

        let base = baseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? transcription : base + " " + transcription
    }

    private static func appending(_ insertion: String, to text: String) -> String {
        guard !insertion.isEmpty else { return text }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return capitalizedFirstCharacter(insertion)
        }

        let endsWithSentence = trimmed.hasSuffix(".")
            || trimmed.hasSuffix("!")
            || trimmed.hasSuffix("?")
        if endsWithSentence {
            return trimmed + " " + capitalizedFirstCharacter(insertion) + "."
        }
        return trimmed + ", " + insertion
    }

    private static func removing(_ insertion: String, from text: String) -> String {
        guard !insertion.isEmpty else { return text }

        let capitalized = capitalizedFirstCharacter(insertion)
        var updatedText = text
        for candidate in [capitalized + ".", ", " + insertion, insertion, capitalized] {
            if let range = updatedText.range(of: candidate) {
                updatedText.removeSubrange(range)
                break
            }
        }
        return updatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitalizedFirstCharacter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

enum DescribeTagRanking {
    static func ranked(
        _ tags: [GuidedQuestion.Tag],
        frequencies: [String: Int]
    ) -> [GuidedQuestion.Tag] {
        tags.enumerated()
            .sorted { lhs, rhs in
                let lhsFrequency = frequencies[lhs.element.tagId, default: 0]
                let rhsFrequency = frequencies[rhs.element.tagId, default: 0]
                if lhsFrequency != rhsFrequency {
                    return lhsFrequency > rhsFrequency
                }
                if lhs.element.defaultWeight != rhs.element.defaultWeight {
                    return lhs.element.defaultWeight > rhs.element.defaultWeight
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
