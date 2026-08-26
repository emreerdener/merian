import SwiftUI

struct FieldTripPublishedContentDetail: View {
    @Bindable var viewModel: FieldTripPublishedContentViewModel
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.isLoading && viewModel.content == nil {
                    FieldTripPublicationSkeleton()
                } else if let content = viewModel.content {
                    header(content)
                    itemsGrid(content.items)
                    commentsSection
                } else if let errorMessage = viewModel.errorMessage {
                    FieldTripPublicationErrorView(message: errorMessage) {
                        Task { await viewModel.load() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            await viewModel.load()
        }
        .merianSystemFeedback(
            toast: Binding(
                get: { viewModel.toastMessage },
                set: { viewModel.toastMessage = $0 }
            ),
            toastAlignment: .top
        )
    }

    private func header(_ content: FieldTripPublishedContent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(content.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(content.publicAuthorDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let contextTitle = content.contextTitle {
                    Text(contextTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let body = content.body {
                Text(body)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await viewModel.toggleLike() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: content.viewerHasLiked ? "heart.fill" : "heart")
                        Text(content.likeCount.formatted())
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(content.viewerHasLiked ? .red : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isUpdatingLike)

                Label(content.commentCount.formatted(), systemImage: "bubble.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func itemsGrid(_ items: [FieldTripPublishedContentItem]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(items) { item in
                FieldTripPublishedContentItemCard(item: item)
            }
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline.weight(.bold))

            comments

            if let commentErrorMessage = viewModel.commentErrorMessage {
                Text(commentErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Add a comment", text: $viewModel.commentDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )

                submitCommentButton
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var comments: some View {
        if viewModel.isLoadingComments && viewModel.comments.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else if viewModel.comments.isEmpty {
            Text("No comments yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 12) {
                ForEach(viewModel.comments) { comment in
                    FieldTripCommentRow(comment: comment)
                }
            }
        }
    }

    private var submitCommentButton: some View {
        Button {
            Task {
                await viewModel.submitComment()
                isComposerFocused = false
            }
        } label: {
            ZStack {
                Circle()
                    .fill(viewModel.canSubmitComment ? Color.primary : Color.secondary.opacity(0.25))
                    .frame(width: 42, height: 42)

                if viewModel.isSubmittingComment {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color(uiColor: .systemBackground))
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            viewModel.canSubmitComment
                                ? Color(uiColor: .systemBackground)
                                : Color.primary.opacity(0.4)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSubmitComment || viewModel.isSubmittingComment)
    }
}
