import SwiftUI

struct ExplorePostDetailView: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let postId: String
    let shouldFocusCommentComposer: Bool

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isComposerFocused: Bool
    @State private var detail: ExplorePostDetail?
    @State private var isLoadingDetail = false
    @State private var detailErrorMessage: String?
    @State private var reactingCommentId: String?

    private let commentsSectionId = "explore-comments-section"
    private let commentsComposerId = "explore-comments-composer"

    private var currentPost: ExplorePost? {
        viewModel.post(id: postId)
    }

    var body: some View {
        Group {
            if let post = currentPost {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            headerRow(for: post)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 12)

                            heroImage(for: post)

                            actionRow(for: post, scrollProxy: scrollProxy)
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                                .padding(.bottom, 12)

                            VStack(spacing: 24) {
                                speciesSection(for: post)

                                insightCardsSection(for: post)

                                ExploreObservationContextCard(post: post)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 16)

                            commentsSection
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                                .padding(.bottom, 24)
                                .id(commentsSectionId)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .background(
                        ScrollViewKeyboardDismissTapRecognizer(
                            isEnabled: isComposerFocused,
                            onTap: dismissCommentComposer
                        )
                    )
                    .background(Color(uiColor: .systemBackground))
                    .navigationTitle(post.resolvedSpeciesCommonName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            detailMenuButton(for: post)
                        }
                    }
                    .task(id: post.id) {
                        async let detailTask: Void = loadPostDetail()
                        async let commentsTask: Void = viewModel.openComments(for: post)
                        _ = await (detailTask, commentsTask)

                        if shouldFocusCommentComposer {
                            focusComments(using: scrollProxy, animated: false)
                        }
                    }
                    .onChange(of: currentPost?.id) { _, newValue in
                        if newValue == nil {
                            dismiss()
                        }
                    }
                }
            } else {
                if !viewModel.hasLoadedFeedOnce || viewModel.isLoadingInitialFeed {
                    Skeleton()
                } else {
                    Color.clear
                        .task {
                            dismiss()
                        }
                }
            }
        }
        .onChange(of: viewModel.commentDraft) { _, newValue in
            if newValue.count > 500 {
                viewModel.commentDraft = String(newValue.prefix(500))
            }
        }
    }

    private func headerRow(for post: ExplorePost) -> some View {
        HStack(alignment: .center, spacing: 8) {
            authorAvatarView(for: post)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.authorName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if let locationText = locationText(for: post) {
                    Text(locationText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func authorAvatarView(for post: ExplorePost) -> some View {
        if let avatarUrl = resolvedAuthorAvatarUrl(for: post) {
            AsyncImage(url: avatarUrl) { phase in
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
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            fallbackAuthorAvatar
        }
    }

    private var fallbackAuthorAvatar: some View {
        Image(systemName: "person.crop.circle")
            .font(.system(size: 40, weight: .regular))
            .foregroundStyle(.primary)
    }

    private func heroImage(for post: ExplorePost) -> some View {
        ExploreDetailMediaView(
            imageUrl: post.heroImageUrl,
            reloadGeneration: viewModel.mediaReloadGeneration
        )
    }

    private func actionRow(for post: ExplorePost, scrollProxy: ScrollViewProxy) -> some View {
        HStack(spacing: 20) {
            ExploreDetailActionButton(
                systemImage: post.viewerHasLiked ? "heart.fill" : "heart",
                value: compactCount(post.likeCount),
                isHighlighted: post.viewerHasLiked,
                action: {
                    Task { await viewModel.toggleLike(for: post) }
                }
            )

            ExploreDetailActionButton(
                systemImage: "bubble.right",
                value: compactCount(post.commentCount),
                isHighlighted: false,
                action: {
                    focusComments(using: scrollProxy)
                }
            )

            Spacer(minLength: 12)

            Button(action: { viewModel.share(post) }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share post")
        }
    }

    private func speciesSection(for post: ExplorePost) -> some View {
        let aiReasoning = detail?.trimmedAiReasoning
        let referenceGalleryImages = detail?.referenceGalleryImages ?? []

        return VStack(alignment: .center, spacing: 24) {
            VStack(alignment: .center, spacing: 8) {
                // Scientific name
                if !post.speciesScientificName.isEmpty && post.speciesScientificName.lowercased() != post.speciesCommonName.lowercased() && post.speciesScientificName != "Taxonomy Unavailable" {
                    Text(post.speciesScientificName.replacingOccurrences(of: "'", with: "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\n", with: " "))
                        .font(.system(.title3))
                        .italic()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                // Species Common Name with Emoji
                Text(post.resolvedSpeciesCommonName)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                // AI Reasoning
                if let aiReasoning {
                    Text(styledAiReasoning(text: aiReasoning, scientificName: post.speciesScientificName))
                        .font(.system(.body))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, 8)
                }
            }

            // Reference Gallery Images
            if !referenceGalleryImages.isEmpty {
                ExploreReferenceGallery(
                    scientificName: post.speciesScientificName,
                    images: referenceGalleryImages
                )
                .padding(.top, aiReasoning == nil ? 8 : 16)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func insightCardsSection(for post: ExplorePost) -> some View {
        let shouldShowSection = isLoadingDetail
            || detail != nil
            || detailErrorMessage != nil

        if shouldShowSection {
            VStack(alignment: .leading, spacing: 24) {
                if isLoadingDetail && detail == nil {
                    ExploreLoadingInsightCard()
                } else {
                    if let detail, detail.hasOverviewContent {
                        ExploreOverviewCard(
                            scientificName: post.speciesScientificName,
                            iucnRedListStatus: detail.iucnRedListStatus,
                            wikipediaOverview: detail.wikipediaOverview
                        )
                    }

                    if let taxonomyData = detail?.taxonomyData {
                        TaxonomyCard(
                            taxonomyData: taxonomyData,
                            scientificName: post.speciesScientificName
                        )
                    }

                    if let detail, detail.hasHabitatDistributionContent {
                        ExploreHabitatDistributionCard(
                            scientificName: post.speciesScientificName,
                            habitatDescription: detail.habitatDescription,
                            gbifTaxonKey: detail.gbifTaxonKey
                        )
                    }
                }

                if let detailErrorMessage, detail == nil {
                    Text(detailErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.right")
                        .foregroundColor(.secondary)
                    Text("Comments")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }

                Spacer()

                if let currentPost {
                    Text(compactCount(currentPost.commentCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isCommentsLoading && viewModel.comments.isEmpty {
                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Loading comments...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else if viewModel.comments.isEmpty {
                EmptyStateView(
                    iconName: "bubble.left.and.bubble.right",
                    title: "No comments yet",
                    message: "Be the first to leave a note on this discovery."
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 220)
            } else {
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
            }

            composer
                .padding(.top, 8)
                .id(commentsComposerId)
        }
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
                            .frame(width: 40, height: 40)
                    } placeholder: {
                        Color(uiColor: .tertiarySystemFill)
                            .frame(width: 40, height: 40)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .padding(.bottom, 1)
                }

                TextField("Add a comment", text: $viewModel.commentDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .submitLabel(.done)
                    .onSubmit { dismissCommentComposer() }
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
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var canSubmitComment: Bool {
        !viewModel.commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commentRow(_ comment: ExploreComment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                authorAvatarView(for: comment)
                
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

    private func detailMenuButton(for post: ExplorePost) -> some View {
        Menu {
            if post.isOwnedByViewer {
                Button(role: .destructive) {
                    Task { await viewModel.unshare(post) }
                } label: {
                    Label("Remove post", systemImage: "trash")
                }
                .tint(.red)
            } else {
                Button(role: .destructive) {
                    Task { await viewModel.blockAuthor(of: post) }
                } label: {
                    Label("Block user", systemImage: "person.crop.circle.badge.xmark")
                }
                .tint(.red)

                Button(role: .destructive) {
                    Task { await viewModel.report(post) }
                } label: {
                    Label("Report post", systemImage: "flag")
                }
                .tint(.red)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(.primary)
    }

    private func focusComments(using scrollProxy: ScrollViewProxy, animated: Bool = true) {
        let scrollBlock = {
            scrollProxy.scrollTo(commentsComposerId, anchor: .bottom)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.22), scrollBlock)
        } else {
            scrollBlock()
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            isComposerFocused = true
        }
    }

    private func dismissCommentComposer() {
        isComposerFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func loadPostDetail() async {
        guard !isLoadingDetail else { return }

        isLoadingDetail = true
        detailErrorMessage = nil
        detail = nil

        defer { isLoadingDetail = false }

        do {
            detail = try await MerianNetworkClient.shared.getExplorePostDetail(postId: postId)
        } catch {
            detailErrorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private func resolvedAuthorAvatarUrl(for post: ExplorePost) -> URL? {
        if let avatarUrlString = post.authorAvatarUrl,
           let avatarUrl = URL(string: avatarUrlString) {
            return avatarUrl
        }

        let currentUserId = SupabaseManager.shared.currentUser?.id.uuidString
        let isCurrentUsersPost = post.isOwnedByViewer || currentUserId == post.authorUserId
        if isCurrentUsersPost {
            return SupabaseManager.shared.currentUserAvatarUrl
        }

        return nil
    }

    private func locationText(for post: ExplorePost) -> String? {
        guard let publicLocationLabel = post.publicLocationLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !publicLocationLabel.isEmpty else {
            return nil
        }

        return publicLocationLabel
    }

    private func compactCount(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }

    private func createdAtText(for comment: ExploreComment) -> String? {
        guard let createdAtDate = comment.createdAtDate else { return nil }
        return createdAtDate.formatted(date: .abbreviated, time: .shortened)
    }

    @ViewBuilder
    private func authorAvatarView(for comment: ExploreComment) -> some View {
        if let avatarUrl = resolvedAuthorAvatarUrl(for: comment) {
            AsyncImage(url: avatarUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    fallbackCommentAuthorAvatar
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                @unknown default:
                    fallbackCommentAuthorAvatar
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        } else {
            fallbackCommentAuthorAvatar
        }
    }

    private var fallbackCommentAuthorAvatar: some View {
        Image(systemName: "person.crop.circle")
            .font(.system(size: 32, weight: .regular))
            .foregroundStyle(.primary)
    }

    private func resolvedAuthorAvatarUrl(for comment: ExploreComment) -> URL? {
        if let avatarUrlString = comment.authorAvatarUrl,
           let avatarUrl = URL(string: avatarUrlString) {
            return avatarUrl
        }

        let currentUserId = SupabaseManager.shared.currentUser?.id.uuidString
        if currentUserId?.lowercased() == comment.authorUserId.lowercased() {
            return SupabaseManager.shared.currentUserAvatarUrl
        }

        if let currentPost,
           currentPost.authorUserId.lowercased() == comment.authorUserId.lowercased(),
           let postAvatarUrlString = currentPost.authorAvatarUrl,
           let postAvatarUrl = URL(string: postAvatarUrlString) {
            return postAvatarUrl
        }

        return nil
    }

    private func styledAiReasoning(text: String, scientificName: String) -> AttributedString {
        let cleanText = text
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
        var result = AttributedString(cleanText)

        let normalizedScientificName = scientificName
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !normalizedScientificName.isEmpty {
            var searchRange = result.startIndex..<result.endIndex
            while let range = result[searchRange].range(of: normalizedScientificName, options: .caseInsensitive) {
                result[range].font = .system(.body, design: .monospaced)
                result[range].backgroundColor = Color.secondary.opacity(0.15)
                searchRange = range.upperBound..<result.endIndex
            }
        }

        return result
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

// SwiftUI exposes scroll-driven keyboard dismissal, but not a passive tap-outside hook
// for this inline composer, so this probe attaches a non-blocking recognizer to the
// backing UIScrollView and resigns first responder when the user taps elsewhere.
private struct ScrollViewKeyboardDismissTapRecognizer: UIViewRepresentable {
    let isEnabled: Bool
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onTap = onTap
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: uiView)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = false
        var onTap: (() -> Void)?

        private lazy var tapRecognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        func attachIfNeeded(from probeView: UIView) {
            var current: UIView? = probeView.superview
            while let view = current {
                if let scrollView = view as? UIScrollView {
                    guard tapRecognizer.view !== scrollView else { return }
                    tapRecognizer.view?.removeGestureRecognizer(tapRecognizer)
                    scrollView.addGestureRecognizer(tapRecognizer)
                    return
                }
                current = view.superview
            }
        }

        @objc
        private func handleTap() {
            guard isEnabled else { return }
            onTap?()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isEnabled else { return false }
            guard let touchedView = touch.view else { return true }
            return !touchedView.hasAncestor(ofType: UITextField.self)
                && !touchedView.hasAncestor(ofType: UITextView.self)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private extension UIView {
    func hasAncestor<T: UIView>(ofType type: T.Type) -> Bool {
        var current: UIView? = self
        while let view = current {
            if view is T {
                return true
            }
            current = view.superview
        }
        return false
    }
}

extension ExplorePostDetailView {
    struct Skeleton: View {
        @Environment(\.colorScheme) private var colorScheme
        @State private var isGlowing = false

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 12)

                    mediaView

                    actionRow
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 12)

                    VStack(spacing: 32) {
                        speciesSection

                        insightCardsSection

                        insightCardsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
            }
            .opacity(isGlowing ? 1.0 : 0.6)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isGlowing = true
                }
            }
            .accessibilityHidden(true)
        }

        private var headerRow: some View {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemFill))
                    .frame(width: 112, height: 16)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(placeholderFill(secondary: true))
                        .frame(width: 88, height: 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var mediaView: some View {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    placeholderFill(secondary: true),
                                    placeholderFill()
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .clipped()
        }

        private var actionRow: some View {
            HStack(spacing: 20) {
                actionGroup
                actionGroup

                Spacer(minLength: 12)

                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 24, height: 24)
            }
        }

        private var actionGroup: some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(placeholderFill(secondary: true))
                    .frame(width: 24, height: 24)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(placeholderFill())
                    .frame(width: 18, height: 14)
            }
        }
        
        private var speciesSection: some View {
            VStack(alignment: .center, spacing: 8) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(placeholderFill(secondary: true))
                    .frame(width: 140, height: 16)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(placeholderFill())
                    .frame(width: 220, height: 28)
            }
            .frame(maxWidth: .infinity)
        }
        
        private var insightCardsSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            }
        }

        private func placeholderFill(secondary: Bool = false) -> Color {
            if colorScheme == .dark {
                return secondary
                    ? Color(uiColor: .secondarySystemFill)
                    : Color(uiColor: .tertiarySystemFill)
            }

            let base = secondary
                ? Color(uiColor: .secondarySystemFill)
                : Color(uiColor: .tertiarySystemFill)
            return base.opacity(isGlowing ? 0.86 : 0.66)
        }
    }
}

private struct ExploreReferenceGallery: View {
    let scientificName: String
    let images: [ExploreReferenceGalleryImage]
    @State private var selectedImageId: String?

    private var carouselHeight: CGFloat {
        min(UIScreen.main.bounds.width * 0.96, 420)
    }

    private var currentImageId: String? {
        selectedImageId ?? images.first?.id
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(images) { image in
                        ExploreReferenceGalleryPage(
                            scientificName: scientificName,
                            image: image,
                            height: carouselHeight
                        )
                        .frame(height: carouselHeight)
                        .containerRelativeFrame(.horizontal)
                        .id(image.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(
                get: { currentImageId },
                set: { selectedImageId = $0 }
            ))
            .frame(height: carouselHeight)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipped()

            if images.count > 1 {
                HStack(spacing: 8) {
                    ForEach(images) { image in
                        Circle()
                            .fill(image.id == currentImageId ? Color.primary : Color.primary.opacity(0.18))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, -16)
        .onAppear {
            if selectedImageId == nil {
                selectedImageId = images.first?.id
            }
        }
    }
}

private struct ExploreReferenceGalleryPage: View {
    let scientificName: String
    let image: ExploreReferenceGalleryImage
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            AsyncLocalImageView(
                path: nil,
                fallbackImageUrl: image.url,
                fillHeight: true
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(image.source.label) reference image for \(scientificName)")
    }
}
