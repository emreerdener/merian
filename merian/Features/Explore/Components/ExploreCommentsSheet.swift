import SwiftUI

struct ExploreCommentsSheet: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let post: ExplorePost

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isComposerFocused: Bool
    @State private var reactingCommentId: String?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isCommentsLoading && viewModel.comments.isEmpty {
                    loadingState
                } else if viewModel.comments.isEmpty {
                    emptyState
                } else {
                    commentsScrollView
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Comments")
                            .font(.headline)
                        Text(post.resolvedSpeciesCommonName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                composer
                    .background(
                        Color(uiColor: .systemBackground)
                            .ignoresSafeArea(edges: .bottom)
                            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4)
                    )
            }
        }
        .presentationDetents([.fraction(0.6), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemBackground))
        .onChange(of: viewModel.commentDraft) { _, newValue in
            if newValue.count > 500 {
                viewModel.commentDraft = String(newValue.prefix(500))
            }
        }
    }

    private var commentsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(viewModel.comments) { comment in
                    commentRow(comment)
                        .onAppear {
                            Task { await viewModel.loadMoreCommentsIfNeeded(currentComment: comment) }
                        }
                }

                if viewModel.isLoadingMoreComments {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading comments...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        EmptyStateView(
            iconName: "bubble.left.and.bubble.right",
            title: "No comments yet",
            message: "Be the first to leave a note on this discovery."
        )
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let commentErrorMessage = viewModel.commentErrorMessage {
                Text(commentErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(alignment: .bottom, spacing: 12) {
                if SupabaseManager.shared.isAuthenticated, let avatarUrl = SupabaseManager.shared.currentUserAvatarUrl {
                    AsyncImage(url: avatarUrl) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Color(uiColor: .tertiarySystemFill)
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .padding(.bottom, 6)
                }

                TextField("Add a comment", text: $viewModel.commentDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .submitLabel(.done)
                    .onSubmit { isComposerFocused = false }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )

                Button(action: {
                    Task { await viewModel.submitComment() }
                }) {
                    ZStack {
                        Circle()
                            .fill(canSubmitComment ? Color.primary : Color.secondary.opacity(0.25))
                            .frame(width: 42, height: 42)

                        if viewModel.isSubmittingComment {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color(uiColor: .systemBackground))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(canSubmitComment ? Color(uiColor: .systemBackground) : Color.primary.opacity(0.4))
                        }
                    }
                }
                .disabled(!canSubmitComment || viewModel.isSubmittingComment)
                .buttonStyle(.plain)
            }

            Text("\(viewModel.commentDraft.count)/500")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var canSubmitComment: Bool {
        !viewModel.commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commentRow(_ comment: ExploreComment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(comment.authorName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if let createdAtText = createdAtText(for: comment) {
                        Text(createdAtText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if comment.hasOverflowActions {
                    Menu {
                        if comment.viewerCanDelete || comment.viewerCanModerate {
                            Button(role: .destructive) {
                                Task { await viewModel.removeComment(comment) }
                            } label: {
                                Label(comment.removalActionTitle, systemImage: "trash")
                            }
                            .tint(.red)
                        }

                        if comment.viewerCanReport {
                            Button(role: .destructive) {
                                Task { await viewModel.reportComment(comment) }
                            } label: {
                                Label("Report comment", systemImage: "flag")
                            }
                            .tint(.red)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 28, height: 28)
                    }
                    .tint(.primary)
                }
            }

            Text(comment.body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                
            reactionsView(for: comment)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func createdAtText(for comment: ExploreComment) -> String? {
        guard let createdAtDate = comment.createdAtDate else { return nil }
        return createdAtDate.formatted(date: .abbreviated, time: .shortened)
    }

    // EMOJIS
    private let availableEmojis = ["\u{2764}\u{FE0F}", "\u{1F44D}", "\u{1F602}", "\u{1F389}", "\u{1F632}", "\u{1F33F}"]

    @ViewBuilder
    private func reactionsView(for comment: ExploreComment) -> some View {
        let reactions = comment.reactions ?? []
        let hasAvailableReactions = availableEmojis.contains { emoji in
            !(reactions.first(where: { $0.emoji == emoji })?.viewerHasReacted ?? false)
        }
        
        FlowLayout(spacing: 8) {
                ForEach(reactions) { reaction in
                    Button(action: {
                        viewModel.toggleReaction(for: comment, emoji: reaction.emoji)
                    }) {
                        HStack(spacing: 4) {
                            Text(reaction.emoji)
                                .font(.subheadline)
                            Text("\(reaction.count)")
                                .font(.footnote)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
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
                    .padding(.vertical, 6)
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
                    HStack(spacing: 8) {
                        ForEach(availableEmojis, id: \.self) { emoji in
                            let hasReacted = comment.reactions?.first(where: { $0.emoji == emoji })?.viewerHasReacted ?? false
                            
                            Button {
                                viewModel.toggleReaction(for: comment, emoji: emoji)
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
            }
        .padding(.top, 4)
    }
}
