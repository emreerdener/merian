import SwiftUI

struct ExploreCommentReactionsView: View {
    let comment: ExploreComment
    @Binding var reactingCommentId: String?
    let onToggleReaction: (ExploreComment, String, Bool) -> Void
    var onLoadMore: () -> Void = {}
    @State private var revealEmoji: String?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                HapticManager.shared.triggerSheetSpring(source: "explore.reaction.comment.open")
                reactingCommentId = comment.id
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "face.smiling")
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 14))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1))
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
