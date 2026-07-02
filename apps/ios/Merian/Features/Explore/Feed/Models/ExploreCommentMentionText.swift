import Foundation
import SwiftUI

struct ExploreMentionTrigger: Equatable {
    let query: String
    let range: Range<String.Index>
}

enum ExploreCommentMentionText {
    static let mentionURLScheme = "merian-mention"

    static func trailingMentionTrigger(in text: String) -> ExploreMentionTrigger? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        let tokenStart = atIndex == text.startIndex ? atIndex : text.index(before: atIndex)
        if atIndex != text.startIndex {
            let preceding = text[tokenStart]
            guard preceding.isWhitespace || preceding.isNewline else { return nil }
        }

        let queryStart = text.index(after: atIndex)
        let query = String(text[queryStart...])
        guard query.range(of: #"^[A-Za-z0-9_]{0,24}$"#, options: .regularExpression) != nil else {
            return nil
        }

        return ExploreMentionTrigger(
            query: query.lowercased(),
            range: atIndex..<text.endIndex
        )
    }

    static func replacingTrailingMention(
        in text: String,
        with suggestion: ExploreMentionSuggestion
    ) -> String {
        guard let trigger = trailingMentionTrigger(in: text) else {
            let separator = text.last?.isWhitespace == true || text.isEmpty ? "" : " "
            return "\(text)\(separator)\(suggestion.displayUsername) "
        }

        var updated = text
        updated.replaceSubrange(trigger.range, with: "\(suggestion.displayUsername) ")
        return updated
    }

    static func attributedBody(
        _ body: String,
        mentions: [ExploreCommentMention],
        accentColor: Color
    ) -> AttributedString {
        var attributed = AttributedString(body)
        let mentionsByUsername = Dictionary(
            uniqueKeysWithValues: mentions.map { ($0.username.lowercased(), $0) }
        )
        guard !mentionsByUsername.isEmpty else { return attributed }

        let nsBody = body as NSString
        let regex = try? NSRegularExpression(
            pattern: #"(^|[^A-Za-z0-9_])@([A-Za-z][A-Za-z0-9_]{1,22}[A-Za-z0-9])"#,
            options: []
        )
        let matches = regex?.matches(
            in: body,
            range: NSRange(location: 0, length: nsBody.length)
        ) ?? []

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let usernameRange = Range(match.range(at: 2), in: body),
                  let mention = mentionsByUsername[String(body[usernameRange]).lowercased()] else {
                continue
            }

            let nsMentionRange = NSRange(
                location: max(match.range(at: 2).location - 1, 0),
                length: match.range(at: 2).length + 1
            )
            guard let bodyMentionRange = Range(nsMentionRange, in: body),
                  let attributedRange = Range(bodyMentionRange, in: attributed),
                  let url = mentionURL(for: mention) else {
                continue
            }

            attributed[attributedRange].link = url
            attributed[attributedRange].foregroundColor = accentColor
        }

        return attributed
    }

    static func mentionURL(for mention: ExploreCommentMention) -> URL? {
        URL(string: "\(mentionURLScheme)://user/\(mention.userId)")
    }

    static func userId(from url: URL) -> String? {
        guard url.scheme == mentionURLScheme,
              url.host == "user" else { return nil }
        let value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return value.isEmpty ? nil : value
    }
}
