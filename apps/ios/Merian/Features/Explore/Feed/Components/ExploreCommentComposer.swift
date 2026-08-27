import SwiftUI

struct ExploreCommentComposer: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let post: ExplorePost
    let isComposerFocused: FocusState<Bool>.Binding
    let onDismissComposer: () -> Void

    @State private var suggestions: [ExploreMentionSuggestion] = []
    @State private var suggestionTask: Task<Void, Never>?
    @State private var activeTrigger: ExploreMentionTrigger?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let commentErrorMessage = viewModel.commentErrorMessage {
                Text(commentErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            replyBanner

            if !suggestions.isEmpty {
                suggestionsList
            }

            HStack(alignment: .bottom, spacing: 12) {
                currentUserAvatar

                TextField(composerPlaceholder, text: $viewModel.commentDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused(isComposerFocused)
                    .id(viewModel.composerResetToken)
                    .submitLabel(.done)
                    .onSubmit { onDismissComposer() }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )

                submitButton
            }

            Text("\(viewModel.commentDraft.count)/500")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { value in
                    if isComposerFocused.wrappedValue && value.translation.height > 10 {
                        onDismissComposer()
                    }
                }
        )
        .onChange(of: viewModel.commentDraft) { _, newValue in
            scheduleMentionSuggestions(for: newValue)
        }
        .onChange(of: viewModel.replyingToComment?.id) { _, _ in
            scheduleMentionSuggestions(for: viewModel.commentDraft)
        }
        .onDisappear {
            suggestionTask?.cancel()
        }
    }

    @ViewBuilder
    private var replyBanner: some View {
        if let replyingToComment = viewModel.replyingToComment {
            HStack(spacing: 8) {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("Replying to \(replyingToComment.displayAuthorName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button(action: { viewModel.cancelReply() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var currentUserAvatar: some View {
        if let avatarUrl = viewModel.currentUserCommentAvatarURL {
            AsyncImage(url: avatarUrl) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
            } placeholder: {
                Color(uiColor: .tertiarySystemFill)
                    .frame(width: 40, height: 40)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .padding(.bottom, 1)
        }
    }

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(suggestions) { suggestion in
                Button {
                    apply(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        suggestionAvatar(suggestion)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.displayUsername)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(suggestion.displayName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func suggestionAvatar(_ suggestion: ExploreMentionSuggestion) -> some View {
        if let avatarUrl = SecureTransportPolicy.httpsURL(
            from: suggestion.avatarUrl
        ) {
            AsyncImage(url: avatarUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    fallbackSuggestionAvatar
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                @unknown default:
                    fallbackSuggestionAvatar
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
        } else {
            fallbackSuggestionAvatar
        }
    }

    private var fallbackSuggestionAvatar: some View {
        Image(systemName: "person.crop.circle")
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(.secondary)
    }

    private var submitButton: some View {
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

    private var canSubmitComment: Bool {
        !viewModel.commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composerPlaceholder: String {
        if let replyingToComment = viewModel.replyingToComment {
            return "Reply to \(replyingToComment.displayAuthorName)"
        }
        return "Add a comment"
    }

    private func scheduleMentionSuggestions(for text: String) {
        suggestionTask?.cancel()
        guard let trigger = ExploreCommentMentionText.trailingMentionTrigger(in: text) else {
            activeTrigger = nil
            suggestions = []
            return
        }

        activeTrigger = trigger
        let postId = post.id
        let parentCommentId = viewModel.replyingToComment?.id
        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            do {
                let loaded = try await viewModel.loadMentionSuggestions(
                    postId: postId,
                    parentCommentId: parentCommentId,
                    query: trigger.query,
                    limit: 6
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if activeTrigger == trigger {
                        suggestions = loaded
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if activeTrigger == trigger {
                        suggestions = []
                    }
                }
            }
        }
    }

    private func apply(_ suggestion: ExploreMentionSuggestion) {
        viewModel.commentDraft = ExploreCommentMentionText.replacingTrailingMention(
            in: viewModel.commentDraft,
            with: suggestion
        )
        suggestions = []
        activeTrigger = nil
        HapticManager.shared.triggerSelectionPulse()
    }
}
