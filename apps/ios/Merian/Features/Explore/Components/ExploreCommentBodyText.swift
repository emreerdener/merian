import SwiftUI

struct ExploreCommentBodyText: View {
    let comment: ExploreComment
    let onMentionTap: (ExploreCommentMention) -> Void

    var body: some View {
        Text(attributedBody)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    guard let userId = ExploreCommentMentionText.userId(from: url),
                          let mention = comment.mentions?.first(where: { $0.userId == userId }) else {
                        return .systemAction
                    }
                    onMentionTap(mention)
                    return .handled
                }
            )
    }

    private var attributedBody: AttributedString {
        ExploreCommentMentionText.attributedBody(
            comment.body,
            mentions: comment.mentions ?? [],
            accentColor: .accentColor
        )
    }
}
