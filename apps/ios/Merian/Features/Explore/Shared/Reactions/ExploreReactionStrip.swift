import SwiftUI

private struct ReactionContentFrame: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct ExploreReactionStrip: View {
    let reactions: [ExploreCommentReaction]
    let hasMore: Bool
    let onToggle: (String, Bool) -> Void
    let onLoadMore: () -> Void
    var revealEmoji: String?
    @ScaledMetric(relativeTo: .title3) private var rowHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var chipHeight: CGFloat = 28
    @State private var contentFrame = CGRect.zero
    @State private var viewportWidth: CGFloat = 0
    @Namespace private var scrollSpace

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(reactions) { reaction in
                        Button {
                            HapticManager.shared.triggerSelectionPulse(source: "explore.reaction.chip.toggle")
                            onToggle(reaction.emoji, !reaction.viewerHasReacted)
                        } label: {
                            HStack(spacing: 4) {
                                Text(reaction.emoji).font(.subheadline)
                                Text(reaction.count.formatted(.number.notation(.compactName))).font(.caption)
                            }
                            .foregroundStyle(reaction.viewerHasReacted ? Color.accentColor : Color.primary)
                            .padding(.horizontal, 6)
                            .frame(minHeight: chipHeight)
                            .background(
                                reaction.viewerHasReacted
                                    ? Color.accentColor.opacity(0.15) : Color(uiColor: .tertiarySystemFill),
                                in: Capsule()
                            )
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(reaction.emoji)
                        .accessibilityLabel(
                            "\(ExploreEmojiCatalog.name(for: reaction.emoji)), \(reaction.count) reactions"
                        )
                        .accessibilityAddTraits(reaction.viewerHasReacted ? .isSelected : [])
                        .accessibilityValue(reaction.viewerHasReacted ? "Selected" : "Not selected")
                        .accessibilityHint(reaction.viewerHasReacted ? "Remove your reaction" : "Add your reaction")
                    }
                    if hasMore {
                        Button("More") {
                            HapticManager.shared.triggerSelectionPulse(source: "explore.reaction.more")
                            onLoadMore()
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Load more reactions")
                    }
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ReactionContentFrame.self, value: geometry.frame(in: .named(scrollSpace)))
                    })
            }
            .contentShape(Rectangle())
            .coordinateSpace(name: scrollSpace)
            .background(
                GeometryReader { geometry in
                    Color.clear.onAppear { viewportWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, width in viewportWidth = width }
                }
            )
            .onPreferenceChange(ReactionContentFrame.self) { frame in
                contentFrame = frame
            }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [contentFrame.minX < -1 ? .clear : .black, .black], startPoint: .leading,
                        endPoint: .trailing
                    ).frame(width: 10)
                    Rectangle()
                    LinearGradient(
                        colors: [.black, contentFrame.maxX > viewportWidth + 1 ? .clear : .black], startPoint: .leading,
                        endPoint: .trailing
                    ).frame(width: 14)
                }
            }
            .onChange(of: reactions) { previous, current in
                guard let revealEmoji,
                      current.first(where: { $0.emoji == revealEmoji })?.viewerHasReacted == true,
                      previous.first(where: { $0.emoji == revealEmoji })?.viewerHasReacted != true else { return }
                proxy.scrollTo(revealEmoji, anchor: .trailing)
            }
        }
        .frame(height: rowHeight)
    }
}

struct ExplorePostReactionActions: View {
    let post: ExplorePost
    let onComments: () -> Void
    let onLike: () -> Void
    let onAddReaction: () -> Void
    let onReaction: (String, Bool) -> Void
    let onLoadMore: () -> Void
    let onShare: () -> Void
    var revealEmoji: String?
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var usesSecondRow: Bool { dynamicType.isAccessibilitySize || dynamicType == .xxxLarge }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                action("bubble.right", count: post.commentCount, label: "Comments", action: onComments)
                action(
                    post.viewerHasLiked ? "heart.fill" : "heart", count: post.likeCount,
                    label: post.viewerHasLiked ? "Unlike post" : "Like post", highlighted: post.viewerHasLiked,
                    action: onLike)
                Button {
                    HapticManager.shared.triggerSheetSpring(source: "explore.reaction.post.open")
                    onAddReaction()
                } label: {
                    Image(systemName: "face.smiling").overlay(alignment: .bottomTrailing) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 9)).background(
                            .background, in: Circle()
                        ).offset(x: 4, y: 2)
                    }
                    .font(.system(size: 20)).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("Add reaction")
                if !usesSecondRow { strip } else { Spacer(minLength: 0) }
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 20)).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("Share post")
            }
            if usesSecondRow { strip }
        }
    }
    private var strip: some View {
        ExploreReactionStrip(
            reactions: post.reactions ?? [], hasMore: post.reactionsNextCursor != nil,
            onToggle: onReaction, onLoadMore: onLoadMore, revealEmoji: revealEmoji
        )
        .frame(maxWidth: .infinity)
    }
    private func action(
        _ symbol: String, count: Int, label: String, highlighted: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(highlighted ? .red : .primary)
                if !dynamicType.isAccessibilitySize {
                    Text(count.formatted(.number.notation(.compactName))).font(.caption)
                }
            }.frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain).accessibilityLabel("\(label), \(count)")
    }
}

struct ExplorePostReactionBar: View {
    let post: ExplorePost
    let onComments: () -> Void
    let onLike: () -> Void
    let onReaction: (String, Bool) -> Void
    let onLoadMore: () -> Void
    let onShare: () -> Void
    @State private var picker: PickerRoute?
    @State private var revealEmoji: String?
    private struct PickerRoute: Identifiable { let id: String }

    var body: some View {
        ExplorePostReactionActions(
            post: post, onComments: onComments, onLike: onLike,
            onAddReaction: { picker = PickerRoute(id: post.id) }, onReaction: onReaction,
            onLoadMore: onLoadMore, onShare: onShare, revealEmoji: revealEmoji
        )
        .sheet(item: $picker) { _ in
            ExploreEmojiPicker(
                selectedEmojis: Set((post.reactions ?? []).filter(\.viewerHasReacted).map(\.emoji)).union(
                    post.viewerHasLiked ? ["❤️"] : [])
            ) { emoji in
                revealEmoji = emoji
                onReaction(emoji, true)
            }
        }
    }
}
