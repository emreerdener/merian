import Foundation

enum UserTagAdditionDecision: Equatable {
    case unchanged
    case add(String)
    case rejected
}

enum UserTagValidation {
    static let maximumTagCount = 50
    static let maximumTagCharacters = 64
    static let maximumTagUTF8Bytes = 256

    static func additionDecision(
        for candidate: String,
        existingTags: [String]
    ) -> UserTagAdditionDecision {
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .unchanged }
        guard !existingTags.contains(trimmed) else { return .unchanged }
        guard existingTags.count < maximumTagCount,
              trimmed.count <= maximumTagCharacters,
              trimmed.utf8.count <= maximumTagUTF8Bytes,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil else {
            return .rejected
        }
        return .add(trimmed)
    }
}
