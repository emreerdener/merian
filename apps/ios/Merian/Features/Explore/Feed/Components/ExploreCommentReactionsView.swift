import SwiftUI

struct ExploreCommentReactionsView: View {
    let comment: ExploreComment
    @Binding var reactingCommentId: String?
    let onToggleReaction: (ExploreComment, String) -> Void

    private let availableEmojis = ["\u{2764}\u{FE0F}", "\u{1F44D}", "\u{1F602}", "\u{1F389}", "\u{1F632}", "\u{1F33F}"]

    var body: some View {
        let reactions = comment.reactions ?? []
        let hasAvailableReactions = availableEmojis.contains { emoji in
            !(reactions.first(where: { $0.emoji == emoji })?.viewerHasReacted ?? false)
        }

        FlowLayout(spacing: 8) {
            ForEach(reactions) { reaction in
                Button {
                    onToggleReaction(comment, reaction.emoji)
                } label: {
                    HStack(spacing: 4) {
                        Text(reaction.emoji)
                            .font(.subheadline)
                        Text("\(reaction.count)")
                            .font(.footnote)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(
                        Capsule()
                            .fill(reaction.viewerHasReacted ? Color.blue.opacity(0.15) : Color(uiColor: .tertiarySystemFill))
                    )
                    .overlay(
                        Capsule()
                            .stroke(reaction.viewerHasReacted ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                    .foregroundColor(reaction.viewerHasReacted ? .blue : .primary)
                }
                .buttonStyle(.plain)
            }

            if hasAvailableReactions {
                Button {
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
                    .background(
                        Capsule()
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(
                    get: { reactingCommentId == comment.id },
                    set: { if !$0 { reactingCommentId = nil } }
                )) {
                    reactionPicker
                }
            }
        }
        .padding(.top, 4)
    }

    private var reactionPicker: some View {
        HStack(spacing: 8) {
            ForEach(availableEmojis, id: \.self) { emoji in
                let hasReacted = comment.reactions?.first(where: { $0.emoji == emoji })?.viewerHasReacted ?? false

                Button {
                    onToggleReaction(comment, emoji)
                    reactingCommentId = nil
                } label: {
                    Text(verbatim: emoji)
                        .font(.system(size: 28))
                        .padding(6)
                        .background(
                            Circle()
                                .fill(hasReacted ? Color.blue.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .presentationCompactAdaptation(.popover)
    }
}
