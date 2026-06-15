import SwiftUI
import XCTest
@testable import Merian

final class ExploreCommentMentionTextTests: XCTestCase {
    func testTrailingMentionTriggerFindsAtToken() {
        let trigger = ExploreCommentMentionText.trailingMentionTrigger(in: "Thanks @Fern_")

        XCTAssertEqual(trigger?.query, "fern_")
    }

    func testTrailingMentionTriggerRejectsEmailLikeText() {
        XCTAssertNil(ExploreCommentMentionText.trailingMentionTrigger(in: "hello@fern"))
        XCTAssertNil(ExploreCommentMentionText.trailingMentionTrigger(in: "Tag @fern!"))
    }

    func testReplacingTrailingMentionUsesSelectedUsername() {
        let suggestion = ExploreMentionSuggestion(
            userId: "user-1",
            username: "fern_field",
            displayName: "Fern Field",
            avatarUrl: nil,
            source: .thread
        )

        let updated = ExploreCommentMentionText.replacingTrailingMention(
            in: "Thanks @fe",
            with: suggestion
        )

        XCTAssertEqual(updated, "Thanks @fern_field ")
    }

    func testAttributedBodyAddsMentionLinkOnlyForResolvedMentions() {
        let mention = ExploreCommentMention(
            userId: "123E4567-E89B-12D3-A456-426614174000",
            username: "fern_field",
            displayName: "Fern Field",
            avatarUrl: nil
        )

        let attributed = ExploreCommentMentionText.attributedBody(
            "Hi @fern_field and @unknown_user",
            mentions: [mention],
            accentColor: .blue
        )
        let rendered = String(attributed.characters)
        guard let mentionRange = rendered.range(of: "@fern_field"),
              let attributedRange = Range(mentionRange, in: attributed) else {
            XCTFail("Expected attributed mention range")
            return
        }

        XCTAssertEqual(attributed[attributedRange].link, ExploreCommentMentionText.mentionURL(for: mention))
        XCTAssertEqual(
            ExploreCommentMentionText.userId(from: attributed[attributedRange].link!),
            mention.userId
        )
    }
}
