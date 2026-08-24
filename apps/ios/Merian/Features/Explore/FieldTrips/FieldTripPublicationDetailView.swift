import SwiftUI

struct FieldTripPublicationDetailView: View {
    let publicationId: String

    @State private var viewModel: FieldTripPublicationViewModel
    @FocusState private var isComposerFocused: Bool

    init(publicationId: String) {
        self.publicationId = publicationId
        _viewModel = State(initialValue: FieldTripPublicationViewModel(publicationId: publicationId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.isLoading && viewModel.detail == nil {
                    FieldTripPublicationSkeleton()
                } else if let detail = viewModel.detail {
                    header(detail)
                    itemsGrid(detail.items)
                    commentsSection(detail)
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
        .navigationTitle("Field trip")
        .navigationBarTitleDisplayMode(.inline)
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

    private func header(_ detail: FieldTripPublicationDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(detail.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail.publicAuthorDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let description = detail.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let aiSummary = detail.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !aiSummary.isEmpty {
                Text(aiSummary)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await viewModel.toggleLike() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: detail.viewerHasLiked ? "heart.fill" : "heart")
                        Text(detail.likeCount.formatted())
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(detail.viewerHasLiked ? .red : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isUpdatingLike)

                Label(detail.commentCount.formatted(), systemImage: "bubble.left")
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

    private func itemsGrid(_ items: [FieldTripPublicationItem]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(items) { item in
                FieldTripPublicationItemCard(item: item)
            }
        }
    }

    private func commentsSection(_ detail: FieldTripPublicationDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline.weight(.bold))

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

                Button {
                    Task {
                        await viewModel.submitComment()
                        isComposerFocused = false
                    }
                } label: {
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
                .buttonStyle(.plain)
                .disabled(!canSubmitComment || viewModel.isSubmittingComment)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var canSubmitComment: Bool {
        !viewModel.commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct FieldTripChallengeEntryDetailView: View {
    let entryId: String

    @State private var viewModel: FieldTripChallengeEntryViewModel
    @FocusState private var isComposerFocused: Bool

    init(entryId: String) {
        self.entryId = entryId
        _viewModel = State(initialValue: FieldTripChallengeEntryViewModel(entryId: entryId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.isLoading && viewModel.detail == nil {
                    FieldTripPublicationSkeleton()
                } else if let detail = viewModel.detail {
                    header(detail)
                    itemsGrid(detail.items)
                    commentsSection(detail)
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
        .navigationTitle("Challenge Entry")
        .navigationBarTitleDisplayMode(.inline)
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

    private func header(_ detail: FieldTripChallengeEntryDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(detail.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail.publicAuthorDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(detail.challengeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let description = detail.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await viewModel.toggleLike() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: detail.viewerHasLiked ? "heart.fill" : "heart")
                        Text(detail.likeCount.formatted())
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(detail.viewerHasLiked ? .red : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isUpdatingLike)

                Label(detail.commentCount.formatted(), systemImage: "bubble.left")
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

    private func itemsGrid(_ items: [FieldTripChallengeEntryItem]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(items) { item in
                FieldTripChallengeEntryItemCard(item: item)
            }
        }
    }

    private func commentsSection(_ detail: FieldTripChallengeEntryDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline.weight(.bold))

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

                Button {
                    Task {
                        await viewModel.submitComment()
                        isComposerFocused = false
                    }
                } label: {
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
                .buttonStyle(.plain)
                .disabled(!canSubmitComment || viewModel.isSubmittingComment)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var canSubmitComment: Bool {
        !viewModel.commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct FieldTripPublicationItemCard: View {
    let item: FieldTripPublicationItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldTripRemoteImage(urlString: item.heroImageUrl ?? item.referenceImageUrl)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.prompt)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(item.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct FieldTripChallengeEntryItemCard: View {
    let item: FieldTripChallengeEntryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldTripRemoteImage(urlString: item.heroImageUrl ?? item.referenceImageUrl)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.prompt)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(item.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct FieldTripRemoteImage: View {
    let urlString: String?

    var body: some View {
        if let url = SecureTransportPolicy.httpsURL(from: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    placeholder
                        .redacted(reason: .placeholder)
                @unknown default:
                    placeholder
                }
            }
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemGroupedBackground)
            Image(systemName: "leaf")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct FieldTripCommentRow: View {
    let comment: ExploreComment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(comment.displayAuthorName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                ExploreCommentBodyText(comment: comment, onMentionTap: { _ in })
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = SecureTransportPolicy.httpsURL(
            from: comment.authorAvatarUrl
        ) {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    fallbackAvatar
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                @unknown default:
                    fallbackAvatar
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        Image(systemName: "person.crop.circle")
            .font(.system(size: 34))
            .foregroundStyle(.secondary)
    }
}

private struct FieldTripPublicationErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FieldTripPublicationSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(0..<4, id: \.self) { _ in
                    itemCard
                }
            }

            comments
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 220, height: 24)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 112, height: 13)
            }

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(maxWidth: .infinity)
                    .frame(height: 15)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 236, height: 15)
            }

            HStack(spacing: 10) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 70, height: 34)

                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 70, height: 34)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var itemCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 72, height: 10)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(maxWidth: 116)
                    .frame(height: 14)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 104, height: 18)

            ForEach(0..<2, id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.14))
                            .frame(width: index == 0 ? 96 : 122, height: 12)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.09))
                            .frame(maxWidth: .infinity)
                            .frame(height: 11)
                    }
                }
            }

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)

                Circle()
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 42, height: 42)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}
