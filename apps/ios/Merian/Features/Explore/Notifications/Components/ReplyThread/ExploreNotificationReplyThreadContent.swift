import SwiftUI

struct ExploreNotificationReplyThreadContent: View {
    @Bindable var viewModel: ExploreNotificationReplyThreadViewModel
    let route: ExploreNotificationReplyThreadRoute

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let parentComment = viewModel.parentComment {
                    originalComment(parentComment)
                }

                if viewModel.replies.isEmpty {
                    Text("No replies were found for this thread.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 48)
                        .padding(.vertical, 8)
                } else {
                    repliesContent
                }
            }
            .padding(16)
        }
        .refreshable {
            await viewModel.load(route: route)
        }
    }

    private var repliesContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(viewModel.replies) { reply in
                commentCard(reply)
            }

            if viewModel.isLoadingMoreReplies {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(.leading, 48)
                    .padding(.vertical, 8)
            } else if !viewModel.hasReachedEndOfReplies {
                Button {
                    Task { await viewModel.loadMoreReplies() }
                } label: {
                    Text("Load more replies")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 48)
            }
        }
    }

    private func originalComment(_ comment: ExploreComment) -> some View {
        commentContent(comment)
            .padding(.horizontal, 2)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commentCard(_ comment: ExploreComment) -> some View {
        commentContent(comment)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    private func commentContent(_ comment: ExploreComment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            commentHeader(comment)

            Text(comment.body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            ExploreCommentReactionsView(
                comment: comment,
                reactingCommentId: $viewModel.reactingCommentId,
                onToggleReaction: { comment, emoji in
                    viewModel.toggleReaction(for: comment, emoji: emoji)
                }
            )
        }
    }

    private func commentHeader(_ comment: ExploreComment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            authorAvatarView(for: comment)

            VStack(alignment: .leading, spacing: 3) {
                Text(comment.displayAuthorName)
                    .font(.subheadline.weight(.semibold))

                if let createdAtText = createdAtText(for: comment) {
                    Text(createdAtText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func authorAvatarView(for comment: ExploreComment) -> some View {
        if let avatarURL = viewModel.authorAvatarURL(for: comment) {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    fallbackAuthorAvatar
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                @unknown default:
                    fallbackAuthorAvatar
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        } else {
            fallbackAuthorAvatar
        }
    }

    private var fallbackAuthorAvatar: some View {
        Image(systemName: "person.crop.circle")
            .font(.system(size: 32, weight: .regular))
            .foregroundStyle(.primary)
    }

    private func createdAtText(for comment: ExploreComment) -> String? {
        guard let createdAtDate = comment.createdAtDate else { return nil }
        return createdAtDate.formatted(date: .abbreviated, time: .shortened)
    }
}
