import SwiftData
import SwiftUI

struct ExplorePostDetailView: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let postId: String
    let shouldFocusCommentComposer: Bool
    let shouldOpenInsight: Bool
    let targetCommentId: String?
    let targetReplyParentCommentId: String?
    let notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget?
    let allowsInsightPresentation: Bool
    let onOpenOwnedPostInsight: ((String) -> Bool)?
    let allowsAuthorProfilePresentation: Bool
    let authorProfileDepth: Int
    let onOpenAuthorProfile: ((ExploreAuthorProfileRoute) -> Void)?
    let onOpenCommunityIdentificationRequest: ((String) -> Void)?

    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(ExploreVideoPlaybackCoordinator.self) private var playbackCoordinator: ExploreVideoPlaybackCoordinator?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isComposerFocused: Bool
    @State private var detail: ExplorePostDetail?
    @State private var isLoadingDetail = false
    @State private var detailErrorMessage: String?
    @State private var isUpdatingFieldNotesVisibility = false
    @State private var showFieldNotesEditor = false
    @State private var showPostComposer = false
    @State private var isSavingPostContent = false
    @State private var postComposerMediaItems: [ExplorePostComposerMediaDraft] = []
    @State private var localFieldNotes: String?
    @State private var selectedInsightRoute: ScanInsightRoute?
    @State private var selectedAuthorProfileRoute: ExploreAuthorProfileRoute?
    @State private var selectedNotificationReplyThreadRoute: ExploreNotificationReplyThreadRoute?
    @State private var isRefreshingAfterInsightDismiss = false
    @State private var didAutoOpenInsight = false
    @State private var didPresentNotificationReplyThread = false
    @State private var isCommonNameScrolledPast = false
    @State private var postToUnpublish: ExplorePost?
    @State private var commentsSectionMinY: CGFloat = .infinity
    @State private var viewportHeight: CGFloat = 0
    @State private var didFocusTargetComment = false
    @State private var focusedComposerIsSticky: Bool?

    private var isComposerSticky: Bool {
        commentsSectionMinY <= viewportHeight - 150
    }

    private var presentedComposerIsSticky: Bool {
        focusedComposerIsSticky ?? isComposerSticky
    }

    private var hasPresentedOverlay: Bool {
        selectedInsightRoute != nil ||
            selectedAuthorProfileRoute != nil ||
            selectedNotificationReplyThreadRoute != nil ||
            showFieldNotesEditor ||
            showPostComposer
    }

    private var canOpenAuthorProfileRoutes: Bool {
        allowsAuthorProfilePresentation &&
            ExploreAuthorProfileNavigationPolicy.canOpenProfile(from: authorProfileDepth)
    }

    private let commentsSectionId = "explore-comments-section"
    private let commentsComposerId = "explore-comments-composer"

    init(
        viewModel: ExploreFeedViewModel,
        postId: String,
        shouldFocusCommentComposer: Bool,
        shouldOpenInsight: Bool,
        targetCommentId: String? = nil,
        targetReplyParentCommentId: String? = nil,
        notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget? = nil,
        allowsInsightPresentation: Bool,
        onOpenOwnedPostInsight: ((String) -> Bool)? = nil,
        allowsAuthorProfilePresentation: Bool = true,
        authorProfileDepth: Int = 0,
        onOpenAuthorProfile: ((ExploreAuthorProfileRoute) -> Void)? = nil,
        onOpenCommunityIdentificationRequest: ((String) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.postId = postId
        self.shouldFocusCommentComposer = shouldFocusCommentComposer
        self.shouldOpenInsight = shouldOpenInsight
        self.targetCommentId = targetCommentId
        self.targetReplyParentCommentId = targetReplyParentCommentId
        self.notificationReplyThreadTarget = notificationReplyThreadTarget
        self.allowsInsightPresentation = allowsInsightPresentation
        self.onOpenOwnedPostInsight = onOpenOwnedPostInsight
        self.allowsAuthorProfilePresentation = allowsAuthorProfilePresentation
        self.authorProfileDepth = authorProfileDepth
        self.onOpenAuthorProfile = onOpenAuthorProfile
        self.onOpenCommunityIdentificationRequest = onOpenCommunityIdentificationRequest
    }

    private var currentPost: ExplorePost? {
        viewModel.post(id: postId)
    }

    private var fieldNotesArePublicOnExplore: Bool {
        detail?.trimmedFieldNotes != nil
    }

    private var canOpenOwnedPostInsight: Bool {
        allowsInsightPresentation || onOpenOwnedPostInsight != nil
    }

    var body: some View {
        Group {
            if let post = currentPost {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ExplorePostDetailAuthorHeader(
                                post: post,
                                avatarUrl: resolvedAuthorAvatarUrl(for: post),
                                locationText: locationText(for: post),
                                opensAuthorProfile: canOpenAuthorProfileRoutes,
                                onOpenAuthorProfile: {
                                    openAuthorProfile(ExploreAuthorProfileRoute(post: post))
                                }
                            )
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 12)

                            ExploreDetailMediaView(
                                imageUrl: post.heroImageUrl,
                                mediaItems: post.resolvedMediaItems,
                                reloadGeneration: viewModel.mediaReloadGeneration
                            )

                            ExplorePostDetailActionRow(
                                viewerHasLiked: post.viewerHasLiked,
                                likeCountText: compactCount(post.likeCount),
                                commentCountText: compactCount(post.commentCount),
                                onLike: {
                                    Task { await viewModel.toggleLike(for: post) }
                                },
                                onComments: {
                                    focusComments(using: scrollProxy)
                                },
                                onShare: {
                                    viewModel.share(post, playbackCoordinator: playbackCoordinator)
                                }
                            )
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                                .padding(.bottom, 12)

                            VStack(spacing: 24) {
                                ExplorePostDetailSpeciesSummary(
                                    scientificName: post.speciesScientificName,
                                    postCommonName: post.speciesCommonName,
                                    displayCommonName: viewModel.resolvedSpeciesCommonName(for: post),
                                    aiReasoning: detail?.trimmedAiReasoning.map {
                                        styledAiReasoning(text: $0, scientificName: post.speciesScientificName)
                                    },
                                    onCommonNameMaxYChange: {
                                        evaluateCommonNameScrollOffset(maxY: $0)
                                    }
                                )

                                hashtagRow

                                toxicityBanner

                                fieldNotesSection(for: post)

                                ExplorePostDetailInsightSection(
                                    post: post,
                                    scientificName: post.speciesScientificName,
                                    displayCommonName: viewModel.resolvedSpeciesCommonName(for: post),
                                    alternativeCommonNames: detail?.alternativeCommonNames ?? [],
                                    detail: detail,
                                    isLoading: isLoadingDetail,
                                    errorMessage: detailErrorMessage
                                )
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 16)

                             ExplorePostDetailCommentsSection(
                                viewModel: viewModel,
                                post: post,
                                composerId: commentsComposerId,
                                targetCommentId: targetCommentId,
                                targetReplyParentCommentId: targetReplyParentCommentId,
                                isComposerFocused: $isComposerFocused,
                                onDismissComposer: dismissCommentComposer,
                                isComposerSticky: false,
                                hideInlineComposer: presentedComposerIsSticky,
                                allowsAuthorProfilePresentation: canOpenAuthorProfileRoutes,
                                onOpenAuthorProfile: onOpenAuthorProfile
                            )
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                                .padding(.bottom, 24)
                                .id(commentsSectionId)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .onChange(
                                                of: geo.frame(in: .named("ExplorePostDetailScrollSpace")).minY,
                                                initial: true
                                            ) { _, newMinY in
                                                commentsSectionMinY = newMinY
                                            }
                                    }
                                )
                        }
                    }
                    .coordinateSpace(name: "ExplorePostDetailScrollSpace")
                    .safeAreaInset(edge: .bottom) {
                        if presentedComposerIsSticky {
                            ExplorePostDetailCommentsSection(
                                viewModel: viewModel,
                                post: post,
                                composerId: commentsComposerId,
                                targetCommentId: targetCommentId,
                                targetReplyParentCommentId: targetReplyParentCommentId,
                                isComposerFocused: $isComposerFocused,
                                onDismissComposer: dismissCommentComposer,
                                isComposerSticky: true,
                                allowsAuthorProfilePresentation: canOpenAuthorProfileRoutes,
                                onOpenAuthorProfile: onOpenAuthorProfile
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: presentedComposerIsSticky)
                    .onChange(of: presentedComposerIsSticky) { _, _ in
                        HapticManager.shared.triggerLightImpact(intensity: 0.8)
                    }
                    .onChange(of: isComposerFocused) { _, newValue in
                        if newValue {
                            let composerWasSticky = isComposerSticky
                            focusedComposerIsSticky = composerWasSticky
                            scrollFocusedInlineComposerIntoViewIfNeeded(
                                using: scrollProxy,
                                composerWasSticky: composerWasSticky
                            )
                        } else {
                            focusedComposerIsSticky = nil
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .background(
                        ExploreKeyboardDismissTapRecognizer(
                            isEnabled: isComposerFocused,
                            onTap: dismissCommentComposer
                        )
                    )
                    .background(Color(uiColor: .systemBackground))
                    .navigationTitle(viewModel.resolvedSpeciesCommonName(for: post))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            ScrollAwareToolbarTitleBadge(
                                title: viewModel.resolvedSpeciesCommonName(for: post),
                                isVisible: isCommonNameScrolledPast
                            )
                        }

                        ToolbarItem(placement: .topBarTrailing) {
                            ExplorePostDetailMenuButton(
                                isOwnedByCurrentUser: isOwnedByCurrentUser(post),
                                allowsInsightPresentation: canOpenOwnedPostInsight,
                                onOpenInsight: { openInsight(for: post) },
                                onEditPost: { openPostComposer(for: post) },
                                onUnpublish: { postToUnpublish = post },
                                onBlockAuthor: {
                                    Task { await viewModel.blockAuthor(of: post) }
                                },
                                onReportPost: {
                                    Task { await viewModel.report(post) }
                                }
                            )
                        }
                    }
                    .task(id: post.id) {
                        async let detailTask: Void = loadPostDetail()
                        async let commentsTask: Void = viewModel.openComments(for: post)
                        _ = await (detailTask, commentsTask)
                        await viewModel.expandPendingReplyThreadIfNeeded()
                        await focusTargetCommentIfNeeded(using: scrollProxy)
                        syncLocalFieldNotes(for: post)
                        presentNotificationReplyThreadIfNeeded(for: post)

                        if shouldFocusCommentComposer {
                            focusComments(using: scrollProxy, animated: false)
                        }

                        if canOpenOwnedPostInsight && shouldOpenInsight && !didAutoOpenInsight {
                            didAutoOpenInsight = true
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 250_000_000)
                                guard !Task.isCancelled else { return }
                                openInsight(for: post)
                            }
                        }
                    }
                    .onChange(of: currentPost?.id) { _, newValue in
                        if newValue == nil {
                            dismiss()
                        }
                    }
                    .onChange(of: post.id, initial: true) { _, _ in
                        isCommonNameScrolledPast = false
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
        .onReceive(AppEventPublisher.shared.publisher) { event in
            switch event {
            case .explorePostNeedsRefresh(let changedPostId) where changedPostId == postId:
                Task {
                    await viewModel.refreshPost(postId: changedPostId)
                    await loadPostDetail()
                }
            case .publicAuthorIdentityChanged(let previousUserId, let currentUserId):
                guard let post = currentPost,
                      authorIdentityChangeAffects(
                        post.authorUserId,
                        previousUserId: previousUserId,
                        currentUserId: currentUserId
                      ) else { return }
                Task {
                    await viewModel.refreshPost(postId: post.id)
                    await loadPostDetail()
                }
            default:
                break
            }
        }
        .exploreVideoOverlayLifecycle(
            isPresented: hasPresentedOverlay,
            reason: "explore-post-detail-sheet"
        )
        .sheet(item: $selectedInsightRoute, onDismiss: {
            isRefreshingAfterInsightDismiss = true
            Task {
                if let post = currentPost {
                    await reconcileFieldNotesAfterInsightDismiss(for: post)
                } else {
                    await loadPostDetail()
                }
                isRefreshingAfterInsightDismiss = false
            }
        }) { route in
            InsightSheetView(
                isPresented: Binding(
                    get: { selectedInsightRoute != nil },
                    set: { if !$0 { selectedInsightRoute = nil } }
                ),
                initialScanId: route.scanId,
                inferenceEngine: inferenceEngine,
                allowsExplorePresentation: false,
                onOpenCommunityIdentificationRequest: { requestId in
                    selectedInsightRoute = nil
                    onOpenCommunityIdentificationRequest?(requestId)
                }
            )
        }
        .sheet(item: $selectedAuthorProfileRoute) { route in
            ExploreAuthorProfileSheet(viewModel: viewModel, route: route)
        }
        .sheet(item: $selectedNotificationReplyThreadRoute) { route in
            ExploreNotificationReplyThreadSheet(viewModel: viewModel, route: route)
        }
        .sheet(isPresented: $showFieldNotesEditor, onDismiss: {
            Task {
                if let post = currentPost {
                    syncLocalFieldNotes(for: post)
                    await loadPostDetail()
                } else {
                    await loadPostDetail()
                }
            }
        }) {
            if let post = currentPost {
                FieldNotesSheet(
                    text: Binding(
                        get: { localFieldNotes ?? detail?.trimmedFieldNotes ?? "" },
                        set: { updateLocalFieldNotes($0) }
                    ),
                    promptContext: .resolved(subjectId: nil),
                    visibilityConfiguration: FieldNotesVisibilityConfiguration(
                        initialIsPublic: fieldNotesArePublicOnExplore,
                        onSave: { text, isPublic in
                            await saveFieldNotesDraft(text, isPublic: isPublic, for: post)
                        }
                    )
                )
            }
        }
        .sheet(isPresented: $showPostComposer) {
            if let post = currentPost {
                ExplorePostComposerView(
                    mode: .edit,
                    speciesName: postSnapshotCommonName(for: post),
                    scientificName: post.speciesScientificName,
                    heroImageUrl: post.heroImageUrl,
                    publicLocationLabel: post.publicDisplayLocationLabel,
                    commonNameOptions: commonNameOptions(for: post),
                    initialSelectedCommonName: postSnapshotCommonName(for: post),
                    initialFieldNotes: detail?.trimmedFieldNotes ?? localFieldNotes,
                    initialFieldNotesArePublic: fieldNotesArePublicOnExplore,
                    initialHashtags: detail?.hashtags ?? post.hashtags ?? [],
                    initialLocationSharing: detail?.locationSharing ?? post.locationSharing ?? .obscured,
                    mediaItems: postComposerMediaItems,
                    isSaving: isSavingPostContent,
                    onSubmit: { draft in
                        Task { await savePostContent(draft, for: post) }
                    }
                )
            }
        }
        .alert(
            "Unpublish Post?",
            isPresented: Binding(
                get: { postToUnpublish != nil },
                set: { if !$0 { postToUnpublish = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Unpublish", role: .destructive) {
                if let post = postToUnpublish {
                    Task { await viewModel.unshare(post) }
                }
            }
        } message: {
            Text("This will remove the post from Explore. Your original scan will remain safely in your library.")
        }
        .background(
            GeometryReader { outerGeo in
                Color.clear
                    .onChange(of: outerGeo.size.height, initial: true) { _, newHeight in
                        viewportHeight = newHeight
                    }
            }
        )
    }

    private func evaluateCommonNameScrollOffset(maxY: CGFloat) {
        guard maxY != .infinity else { return }

        let isPast = maxY < 44
        guard isCommonNameScrolledPast != isPast else { return }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isCommonNameScrolledPast = isPast
        }
    }

    @ViewBuilder
    private func fieldNotesSection(for post: ExplorePost) -> some View {
        let isOwner = isOwnedByCurrentUser(post)
        let fieldNotes = detail?.trimmedFieldNotes
            ?? (isOwner ? FieldNotesRepository.trimmedNonEmptyText(localFieldNotes) : nil)

        if !isRefreshingAfterInsightDismiss, let fieldNotes {
            ExploreFieldNotesCard(
                fieldNotes: fieldNotes,
                visibility: isOwner
                    ? (fieldNotesArePublicOnExplore ? .published : .privateNotes)
                    : nil,
                canEdit: isOwner,
                onEdit: { openFieldNotesEditor(for: post) }
            )
        }
    }

    @ViewBuilder
    private var toxicityBanner: some View {
        if let hazardType = detail?.hazardType {
            ToxicityBanner(hazardType: hazardType)
        }
    }

    @ViewBuilder
    private var hashtagRow: some View {
        if let hashtags = detail?.hashtags, !hashtags.isEmpty {
            FlowLayout(spacing: 8, lineAlignment: .center) {
                ForEach(hashtags, id: \.self) { hashtag in
                    NavigationLink {
                        ExploreHashtagPostsView(
                            viewModel: viewModel,
                            route: ExploreHashtagRoute(hashtag: hashtag),
                            allowsInsightPresentation: allowsInsightPresentation,
                            onOpenOwnedPostInsight: onOpenOwnedPostInsight,
                            allowsAuthorProfilePresentation: canOpenAuthorProfileRoutes,
                            authorProfileDepth: authorProfileDepth,
                            onOpenAuthorProfile: onOpenAuthorProfile
                        )
                    } label: {
                        ExploreHashtagPill(hashtag: hashtag)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, -8)
            .padding(.bottom, 2)
        }
    }

    private func openAuthorProfile(_ route: ExploreAuthorProfileRoute) {
        guard canOpenAuthorProfileRoutes else { return }
        HapticManager.shared.triggerSelectionPulse()
        if let onOpenAuthorProfile {
            onOpenAuthorProfile(route)
        } else {
            selectedAuthorProfileRoute = route
        }
    }

    private func focusComments(using scrollProxy: ScrollViewProxy, animated: Bool = true) {
        let scrollBlock = {
            scrollProxy.scrollTo(commentsSectionId, anchor: .top)
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

    private func scrollFocusedInlineComposerIntoViewIfNeeded(
        using scrollProxy: ScrollViewProxy,
        composerWasSticky: Bool
    ) {
        guard !composerWasSticky else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, isComposerFocused, focusedComposerIsSticky == false else { return }

            withAnimation(.easeInOut(duration: 0.18)) {
                scrollProxy.scrollTo(commentsComposerId, anchor: .bottom)
            }
        }
    }

    private func presentNotificationReplyThreadIfNeeded(for post: ExplorePost) {
        guard !didPresentNotificationReplyThread,
              let notificationReplyThreadTarget else { return }

        didPresentNotificationReplyThread = true
        selectedNotificationReplyThreadRoute = ExploreNotificationReplyThreadRoute(
            post: post,
            parentCommentId: notificationReplyThreadTarget.parentCommentId,
            targetReplyId: notificationReplyThreadTarget.targetReplyId,
            fallbackReply: notificationReplyThreadTarget.fallbackReply
        )
    }

    private func focusTargetCommentIfNeeded(using scrollProxy: ScrollViewProxy) async {
        guard let targetCommentId, !didFocusTargetComment else { return }

        if let targetReplyParentCommentId {
            let targetReplyId = targetReplyParentCommentId == targetCommentId ? nil : targetCommentId
            await viewModel.expandReplyThread(parentCommentId: targetReplyParentCommentId, targetReplyId: targetReplyId)
        } else {
            await viewModel.loadCommentsUntilCommentIfNeeded(commentId: targetCommentId)
        }

        await performTargetCommentScroll(using: scrollProxy, targetCommentId: targetCommentId)
    }

    @MainActor
    private func performTargetCommentScroll(using scrollProxy: ScrollViewProxy, targetCommentId: String) async {
        let isTargetingReply = targetReplyParentCommentId != nil && targetReplyParentCommentId != targetCommentId
        let scrollId = !isTargetingReply
            ? ExploreCommentScrollTarget.comment(targetCommentId).id
            : ExploreCommentScrollTarget.reply(targetCommentId).id

        let parentScrollId = isTargetingReply ? targetReplyParentCommentId.map {
            ExploreCommentScrollTarget.comment($0).id
        } : nil

        for attempt in 0..<5 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 200_000_000)
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else { return }

            scrollProxy.scrollTo(commentsSectionId, anchor: .top)
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }

            if let parentScrollId {
                scrollProxy.scrollTo(parentScrollId, anchor: .center)
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
            }

            withAnimation(.easeInOut(duration: 0.24)) {
                scrollProxy.scrollTo(scrollId, anchor: .center)
            }
        }

        didFocusTargetComment = true
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

    private func saveFieldNotesDraft(
        _ notes: String,
        isPublic: Bool,
        for post: ExplorePost
    ) async -> FieldNotesVisibilityUpdateFeedback {
        guard currentPost?.id == post.id, isOwnedByCurrentUser(post) else {
            return .failure("This post is no longer available")
        }
        guard !isUpdatingFieldNotesVisibility else {
            return .failure("Field notes visibility is already updating")
        }

        updateLocalFieldNotes(notes)

        let notesToPublish = FieldNotesRepository.trimmedNonEmptyText(notes)
        let shouldPublish = isPublic && notesToPublish != nil

        guard !isPublic || notesToPublish != nil else {
            return .failure("Add field notes before publishing them")
        }

        isUpdatingFieldNotesVisibility = true
        defer { isUpdatingFieldNotesVisibility = false }

        do {
            if !shouldPublish, let notesToPublish {
                preserveLocalFieldNotes(notesToPublish, for: post)
            }

            let response = try await MerianNetworkClient.shared.updateExplorePostFieldNotes(
                postId: post.id,
                fieldNotes: shouldPublish ? notesToPublish : nil
            )
            if response.postId == post.id {
                detail?.fieldNotes = response.fieldNotes
            } else {
                detail?.fieldNotes = shouldPublish ? notesToPublish : nil
            }
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                viewModel.toastMessage = detail?.trimmedFieldNotes == nil
                    ? "Field notes are now private"
                    : "Field notes are now public on Explore"
            }
            return .success(isPublic: detail?.trimmedFieldNotes != nil)
        } catch {
            HapticManager.shared.triggerErrorThump()
            return .failure(ExploreErrorFormatter.message(for: error))
        }
    }

    private func syncLocalFieldNotes(for post: ExplorePost) {
        guard isOwnedByCurrentUser(post) else {
            localFieldNotes = nil
            return
        }

        let scanId = post.scanId
        localFieldNotes = FieldNotesRepository.fieldNotes(
            for: scanId,
            modelContext: modelContext
        )
    }

    private func openFieldNotesEditor(for post: ExplorePost) {
        guard isOwnedByCurrentUser(post) else { return }

        syncLocalFieldNotes(for: post)
        if localFieldNotes == nil, let publicNotes = detail?.trimmedFieldNotes {
            preserveLocalFieldNotes(publicNotes, for: post)
        }

        HapticManager.shared.triggerSelectionPulse()
        showFieldNotesEditor = true
    }

    private func openPostComposer(for post: ExplorePost) {
        guard isOwnedByCurrentUser(post) else { return }
        syncLocalFieldNotes(for: post)
        postComposerMediaItems = ExplorePostComposerMediaDraft.existingPostItems(from: post.mediaItems ?? [])
        Task {
            do {
                let payload = try await MerianNetworkClient.shared.getExploreComposerMedia(postId: post.id)
                postComposerMediaItems = ExplorePostComposerMediaDraft.sourceItems(from: payload.mediaItems)
            } catch {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    viewModel.toastMessage = ExploreErrorFormatter.message(for: error)
                }
            }

            HapticManager.shared.triggerSelectionPulse()
            showPostComposer = true
        }
    }

    private func savePostContent(_ draft: ExplorePostComposerDraft, for post: ExplorePost) async {
        guard isOwnedByCurrentUser(post), !isSavingPostContent else { return }

        isSavingPostContent = true
        defer { isSavingPostContent = false }

        do {
            persistPreferredCommonName(draft.selectedCommonName, scientificName: post.speciesScientificName)
            let response = try await MerianNetworkClient.shared.updateExplorePostContent(
                postId: post.id,
                speciesCommonName: draft.selectedCommonName,
                fieldNotes: draft.publicFieldNotes,
                hashtags: draft.hashtags,
                locationSharing: draft.locationSharing,
                mediaItems: draft.mediaItems
            )
            detail?.fieldNotes = response.fieldNotes
            detail?.locationSharing = response.locationSharing ?? draft.locationSharing
            updateLocalFieldNotes(draft.fieldNotes ?? "")
            showPostComposer = false
            await viewModel.refreshPost(postId: post.id)
            viewModel.refreshPreferredSpeciesNames(for: [post.speciesScientificName], modelContext: modelContext)
            await loadPostDetail()
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                viewModel.toastMessage = "Explore post updated"
            }
        } catch {
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                viewModel.toastMessage = ExploreErrorFormatter.message(for: error)
            }
        }
    }

    private func updateLocalFieldNotes(_ notes: String) {
        guard let post = currentPost, isOwnedByCurrentUser(post) else { return }

        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanId = post.scanId
        _ = FieldNotesRepository.setFieldNotes(
            notes,
            for: scanId,
            modelContext: modelContext
        )
        localFieldNotes = trimmed.isEmpty ? nil : notes
    }

    private func postSnapshotCommonName(for post: ExplorePost) -> String {
        let trimmed = post.speciesCommonName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? viewModel.resolvedSpeciesCommonName(
                scientificName: post.speciesScientificName,
                fallbackCommonName: post.speciesCommonName
            )
            : trimmed
    }

    private func commonNameOptions(for post: ExplorePost) -> [String] {
        ([postSnapshotCommonName(for: post)] + (detail?.alternativeCommonNames ?? []))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .removingFuzzyDuplicateNames()
    }

    private func persistPreferredCommonName(_ name: String, scientificName: String) {
        _ = SpeciesPreferredNameRepository.setPreferredName(
            name,
            for: scientificName,
            modelContext: modelContext
        )
    }

    private func syncPublicFieldNotesAfterInsightDismiss(for post: ExplorePost) async {
        guard isOwnedByCurrentUser(post) else { return }

        do {
            let response = try await MerianNetworkClient.shared.updateExplorePostFieldNotes(
                postId: post.id,
                fieldNotes: localFieldNotes
            )
            if response.postId == post.id {
                detail?.fieldNotes = response.fieldNotes
            }
        } catch {
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                viewModel.toastMessage = ExploreErrorFormatter.message(for: error)
            }
        }
    }

    private func reconcileFieldNotesAfterInsightDismiss(for post: ExplorePost) async {
        syncLocalFieldNotes(for: post)
        await loadPostDetail()

        guard detail?.trimmedFieldNotes != nil else {
            syncLocalFieldNotes(for: post)
            return
        }

        await syncPublicFieldNotesAfterInsightDismiss(for: post)
        syncLocalFieldNotes(for: post)
    }

    private func preserveLocalFieldNotes(_ notes: String, for post: ExplorePost) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let scanId = post.scanId
        localFieldNotes = FieldNotesRepository.promoteExternalFieldNotesIfLocalMissing(
            notes,
            for: scanId,
            modelContext: modelContext
        )
    }

    private func openInsight(for post: ExplorePost) {
        guard isOwnedByCurrentUser(post) else { return }

        let scanId = post.scanId
        if let fieldNotes = detail?.trimmedFieldNotes {
            localFieldNotes = FieldNotesRepository.promoteExternalFieldNotesIfLocalMissing(
                fieldNotes,
                for: scanId,
                modelContext: modelContext
            )
        }

        if let onOpenOwnedPostInsight {
            if onOpenOwnedPostInsight(scanId) {
                HapticManager.shared.triggerSelectionPulse()
                dismiss()
            } else {
                HapticManager.shared.triggerErrorThump()
                viewModel.toastMessage = "This scan is not available on this device."
            }
            return
        }

        guard allowsInsightPresentation else { return }

        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1

        guard let record = try? modelContext.fetch(descriptor).first else {
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = "This scan is not available on this device."
            return
        }

        inferenceEngine.load(from: record)
        HapticManager.shared.triggerSelectionPulse()
        selectedInsightRoute = ScanInsightRoute(scanId: record.id)
    }

    private func isOwnedByCurrentUser(_ post: ExplorePost) -> Bool {
        let currentUserId = SupabaseManager.shared.currentUser?.id.uuidString
        return post.isOwnedByViewer || currentUserId == post.authorUserId
    }

    private func authorIdentityChangeAffects(
        _ authorUserId: String,
        previousUserId: String?,
        currentUserId: String
    ) -> Bool {
        let normalizedAuthorId = authorUserId.lowercased()
        return previousUserId == normalizedAuthorId || currentUserId == normalizedAuthorId
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
        post.publicDisplayLocationLabel
    }

    private func compactCount(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
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
