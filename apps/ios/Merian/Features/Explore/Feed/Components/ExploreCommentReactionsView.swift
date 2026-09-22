import SwiftUI

struct ExploreCommentReactionsView: View {
    let comment: ExploreComment
    @Binding var reactingCommentId: String?
    let onToggleReaction: (ExploreComment, String, Bool) -> Void
    var onLoadMore: () -> Void = {}
    @State private var revealEmoji: String?
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 20

    var body: some View {
        HStack(spacing: 6) {
            Button {
                HapticManager.shared.triggerSheetSpring(source: "explore.reaction.comment.open")
                reactingCommentId = comment.id
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "face.smiling")
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                }
                .font(.system(size: iconSize))
                .padding(.horizontal, 6)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Add reaction to comment")
            ExploreReactionStrip(
                reactions: comment.reactions ?? [], hasMore: comment.reactionsNextCursor != nil,
                onToggle: { onToggleReaction(comment, $0, $1) }, onLoadMore: onLoadMore, revealEmoji: revealEmoji)
        }
        .sheet(
            isPresented: Binding(
                get: { reactingCommentId == comment.id },
                set: { if !$0 { reactingCommentId = nil } }
            )
        ) {
            ExploreEmojiPicker(selectedEmojis: Set((comment.reactions ?? []).filter(\.viewerHasReacted).map(\.emoji))) { emoji in
                revealEmoji = emoji
                onToggleReaction(comment, emoji, true)
                reactingCommentId = nil
            }
        }
    }
}
