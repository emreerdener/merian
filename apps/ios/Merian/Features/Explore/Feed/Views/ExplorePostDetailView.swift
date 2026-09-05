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
    let onOpenExploreMap: ((ExploreMapFocusTarget) -> Void)?

    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Environment(SupabaseManager.self) private var supabase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var detailViewModel: ExplorePostDetailViewModel
    @State private var localFieldNotes: String?
    @State private var fieldNotesEditorInitialText = ""
    @State private var presentedSheet: ExplorePostDetailPresentation?
    @State private var insightDismissalRoute: ScanInsightRoute?
    @State private var pendingInsightCommunityRequestId: String?
    @State private var isRefreshingAfterInsightDismiss = false
    @State private var postToUnpublish: ExplorePost?
    @State private var exploreChatViewModel = InsightChatViewModel(source: .explorePost)
    @State private var pendingExploreChatPreparationPostID: String?
    @State private var postComposerPreparationID: UUID?
    @State private var postComposerPreparationTask: Task<Void, Never>?
    private let presentationServices = ExplorePostDetailPresentationServices.live

    private var canOpenAuthorProfileRoutes: Bool {
        allowsAuthorProfilePresentation && ExploreAuthorProfileNavigationPolicy.canOpenProfile(from: authorProfileDepth)
    }

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
        onOpenCommunityIdentificationRequest: ((String) -> Void)? = nil,
        onOpenExploreMap: ((ExploreMapFocusTarget) -> Void)? = nil
    ) {
        _detailViewModel = State(initialValue: ExplorePostDetailViewModel(postId: postId))
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
        self.onOpenExploreMap = onOpenExploreMap
    }

    private var currentPost: ExplorePost? { viewModel.post(id: postId) }
    private var canOpenOwnedPostInsight: Bool { allowsInsightPresentation || onOpenOwnedPostInsight != nil }
    private var hasPresentationConflict: Bool {
        presentedSheet != nil || postToUnpublish != nil
    }

    var body: some View {
        Group {
            if let post = currentPost {
                ExplorePostDetailContentView(
                    viewModel: viewModel,
                    detailViewModel: detailViewModel,
                    post: post,
                    shouldFocusCommentComposer: shouldFocusCommentComposer,
                    shouldOpenInsight: shouldOpenInsight,
                    targetCommentId: targetCommentId,
                    targetReplyParentCommentId: targetReplyParentCommentId,
                    notificationReplyThreadTarget: notificationReplyThreadTarget,
                    allowsInsightPresentation: allowsInsightPresentation,
                    onOpenOwnedPostInsight: onOpenOwnedPostInsight,
                    canOpenOwnedPostInsight: canOpenOwnedPostInsight,
                    canOpenAuthorProfileRoutes: canOpenAuthorProfileRoutes,
                    authorProfileDepth: authorProfileDepth,
                    onOpenAuthorProfile: { openAuthorProfile($0) },
                    onOpenExploreMap: onOpenExploreMap,
                    authorPresentation: presentationServices.authorPresentation(for: post),
                    isOwnedByCurrentUser: presentationServices.isOwnedByCurrentUser(post),
                    localFieldNotes: localFieldNotes,
                    isRefreshingAfterInsightDismiss: isRefreshingAfterInsightDismiss,
                    isFieldChatAvailable: !exploreChatViewModel.isUnavailable(for: post.id),
                    onLoadDetail: {
                        await loadPostDetail()
                    },
                    onSyncLocalFieldNotes: {
                        syncLocalFieldNotes(for: post)
                    },
                    onPresentNotificationReply: { route in
                        beginPresentation(.notificationReply(route))
                    },
                    onOpenInsight: {
                        openInsight(for: post)
                    },
                    onEditFieldNotes: {
                        openFieldNotesEditor(for: post)
                    },
                    onEditPost: {
                        openPostComposer(for: post)
                    },
                    onUnpublish: {
                        openUnpublishConfirmation(for: post)
                    },
                    onOpenFieldChat: {
                        openExploreFieldChat(for: post)
                    },
                    onDisappear: cancelPendingAsyncPresentations
                )
                .onChange(of: currentPost?.id) { _, newValue in
                    if newValue == nil {
                        dismiss()
                    }
                }
            } else if !viewModel.hasLoadedFeedOnce || viewModel.isLoadingInitialFeed {
                ExplorePostDetailSkeleton()
            } else {
                Color.clear
                    .task {
                        dismiss()
                    }
            }
        }
        .onChange(of: offlineQueueManager.isOnline, initial: true) { _, isOnline in
            exploreChatViewModel.updateConnectivity(isOnline: isOnline)
        }
        .onChange(of: viewModel.commentDraft) { _, newValue in
            if newValue.count > 500 {
                viewModel.commentDraft = String(newValue.prefix(500))
            }
        }
        .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
            handleAppEvent(event)
        }
        .task(id: pendingExploreChatPreparationPostID) {
            await preparePendingFieldChat()
        }
        .sheet(
            item: $presentedSheet,
            onDismiss: handlePresentedSheetDismissed
        ) { presentation in
            ExplorePostDetailSheetContent(
                feedViewModel: viewModel,
                detailViewModel: detailViewModel,
                chatViewModel: exploreChatViewModel,
                presentedSheet: $presentedSheet,
                presentation: presentation,
                currentPost: currentPost,
                localFieldNotes: localFieldNotes,
                onUpdateLocalFieldNotes: updateLocalFieldNotes,
                onSaveFieldNotes: { text, isPublic, post in
                    await saveFieldNotesDraft(text, isPublic: isPublic, for: post)
                },
                onSavePost: { draft, post in
                    await savePostContent(draft, for: post)
                },
                onOpenCommunityIdentificationRequest: { requestID in
                    pendingInsightCommunityRequestId = requestID
                    dismissPresentedSheet(ifMatching: presentation.id)
                }
            )
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
    }

    private func handleAppEvent(_ event: AppEvent) {
        switch event {
        case .explorePostNeedsRefresh(let changedPostId) where changedPostId == postId:
            Task {
                await viewModel.refreshPost(postId: changedPostId)
                await loadPostDetail(force: true)
            }
        case .publicAuthorIdentityChanged(let previousUserId, let currentUserId):
            guard let post = currentPost,
                  ExplorePostDetailAuthorIdentityPolicy.changeAffectsAuthor(
                    post.authorUserId,
                    previousUserID: previousUserId,
                    currentUserID: currentUserId
                  ) else { return }
            Task {
                await viewModel.refreshPost(postId: post.id)
                await loadPostDetail(force: true)
            }
        default:
            break
        }
    }

    private func preparePendingFieldChat() async {
        guard let postID = pendingExploreChatPreparationPostID else { return }
        let canPresent = await exploreChatViewModel.prepareForPresentation(scanId: postID)
        guard pendingExploreChatPreparationPostID == postID else { return }
        defer {
            if pendingExploreChatPreparationPostID == postID {
                pendingExploreChatPreparationPostID = nil
            }
        }
        guard ExplorePostDetailPresentationPolicy.canCommitAsyncPresentation(
            requestedPostId: postID,
            currentPostId: currentPost?.id,
            hasPresentationConflict: hasPresentationConflict,
            isCancelled: Task.isCancelled
        ) else { return }

        if canPresent {
            HapticManager.shared.triggerSheetSpring()
            presentedSheet = .fieldChat(postId: postID)
        } else {
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = .error(
                exploreChatViewModel.errorMessage
                    ?? "Field chat isn't available for this post."
            )
        }
    }
    private func handlePresentedSheetDismissed() {
        guard insightDismissalRoute != nil else { return }
        insightDismissalRoute = nil

        if let requestId = pendingInsightCommunityRequestId {
            pendingInsightCommunityRequestId = nil
            onOpenCommunityIdentificationRequest?(requestId)
            return
        }

        isRefreshingAfterInsightDismiss = true
        Task {
            if let post = currentPost {
                await reconcileFieldNotesAfterInsightDismiss(for: post)
            } else {
                await loadPostDetail()
            }
            isRefreshingAfterInsightDismiss = false
        }
    }

    @discardableResult
    private func beginPresentation(
        _ presentation: ExplorePostDetailPresentation
    ) -> Bool {
        guard !hasPresentationConflict else { return false }
        cancelPendingAsyncPresentations()
        if case .insight(let route) = presentation {
            insightDismissalRoute = route
        }
        presentedSheet = presentation
        return true
    }

    private func dismissPresentedSheet(ifMatching presentationID: String) {
        guard presentedSheet?.id == presentationID else { return }
        presentedSheet = nil
    }

    private func cancelPendingAsyncPresentations() {
        pendingExploreChatPreparationPostID = nil
        postComposerPreparationTask?.cancel()
        postComposerPreparationTask = nil
        postComposerPreparationID = nil
    }

    private func openAuthorProfile(_ route: ExploreAuthorProfileRoute) {
        guard canOpenAuthorProfileRoutes, !hasPresentationConflict else { return }
        if let onOpenAuthorProfile {
            cancelPendingAsyncPresentations()
            HapticManager.shared.triggerSelectionPulse()
            onOpenAuthorProfile(route)
        } else if beginPresentation(.author(route)) {
            HapticManager.shared.triggerSelectionPulse()
        }
    }

    private func loadPostDetail(force: Bool = false) async {
        await detailViewModel.loadDetail(force: force)
    }

    private func saveFieldNotesDraft(
        _ notes: String,
        isPublic: Bool,
        for post: ExplorePost
    ) async -> FieldNotesVisibilityUpdateFeedback {
        guard currentPost?.id == post.id,
              presentationServices.isOwnedByCurrentUser(post) else {
            return .failure("This post is no longer available")
        }
        guard !detailViewModel.isUpdatingFieldNotesVisibility else {
            return .failure("Field notes visibility is already updating")
        }

        let previousLocalNotes = FieldNotesEditPolicy.normalizedText(fieldNotesEditorInitialText)
        let previousPublicNotes = FieldNotesEditPolicy.normalizedText(detailViewModel.detail?.fieldNotes)
        let wasPublic = previousPublicNotes != nil
        let notesToPublish = FieldNotesEditPolicy.normalizedText(notes)
        let shouldPublish = isPublic && notesToPublish != nil

        guard !isPublic || notesToPublish != nil else {
            return .failure("Add field notes before publishing them")
        }

        let desiredPublicNotes = shouldPublish ? notesToPublish : nil
        let contentChanged = previousLocalNotes != notesToPublish
        let publicPayloadChanged = previousPublicNotes != desiredPublicNotes

        updateLocalFieldNotes(notes)

        guard contentChanged || publicPayloadChanged else {
            return .success(isPublic: wasPublic)
        }

        guard publicPayloadChanged else {
            HapticManager.shared.triggerSuccessPulse()
            if let message = FieldNotesEditPolicy.successMessage(
                wasPublic: wasPublic,
                isPublic: wasPublic,
                contentChanged: contentChanged
            ) {
                viewModel.toastMessage = .success(message)
            }
            return .success(isPublic: wasPublic)
        }

        do {
            if !shouldPublish, let notesToPublish {
                preserveLocalFieldNotes(notesToPublish, for: post)
            }

            _ = try await detailViewModel.updateFieldNotes(desiredPublicNotes)
            let isNowPublic = detailViewModel.detail?.trimmedFieldNotes != nil
            HapticManager.shared.triggerSuccessPulse()
            if let message = FieldNotesEditPolicy.successMessage(
                wasPublic: wasPublic,
                isPublic: isNowPublic,
                contentChanged: contentChanged
            ) {
                viewModel.toastMessage = .success(message)
            }
            return .success(isPublic: isNowPublic)
        } catch {
            HapticManager.shared.triggerErrorThump()
            return .failure(ExploreErrorFormatter.message(for: error))
        }
    }

    private func syncLocalFieldNotes(for post: ExplorePost) {
        guard presentationServices.isOwnedByCurrentUser(post) else {
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
        guard presentationServices.isOwnedByCurrentUser(post), !hasPresentationConflict else { return }

        syncLocalFieldNotes(for: post)
        if localFieldNotes == nil, let publicNotes = detailViewModel.detail?.trimmedFieldNotes {
            preserveLocalFieldNotes(publicNotes, for: post)
        }
        fieldNotesEditorInitialText = localFieldNotes ?? detailViewModel.detail?.trimmedFieldNotes ?? ""

        if beginPresentation(.fieldNotes(postId: post.id)) {
            HapticManager.shared.triggerSelectionPulse()
        }
    }

    private func openPostComposer(for post: ExplorePost) {
        guard presentationServices.isOwnedByCurrentUser(post), !hasPresentationConflict else { return }
        cancelPendingAsyncPresentations()
        syncLocalFieldNotes(for: post)
        detailViewModel.setInitialComposerMedia(from: post.mediaItems ?? [])
        let requestID = UUID()
        let requestedPostID = post.id
        postComposerPreparationID = requestID
        postComposerPreparationTask = Task { @MainActor in
            var resolvedMediaItems: [ExplorePostComposerMediaDraft]?
            var preparationError: Error?
            do {
                resolvedMediaItems = try await detailViewModel.loadComposerMedia()
            } catch {
                preparationError = error
            }

            guard postComposerPreparationID == requestID else { return }
            defer {
                if postComposerPreparationID == requestID {
                    postComposerPreparationID = nil
                    postComposerPreparationTask = nil
                }
            }
            guard ExplorePostDetailPresentationPolicy.canCommitAsyncPresentation(
                    requestedPostId: requestedPostID,
                    currentPostId: currentPost?.id,
                    hasPresentationConflict: hasPresentationConflict,
                    isCancelled: Task.isCancelled
                  ) else { return }

            if let resolvedMediaItems {
                detailViewModel.commitComposerMedia(resolvedMediaItems)
            }
            if let preparationError {
                viewModel.toastMessage = .error(
                    ExploreErrorFormatter.message(for: preparationError)
                )
            }
            HapticManager.shared.triggerSelectionPulse()
            presentedSheet = .postComposer(postId: requestedPostID)
        }
    }

    private func savePostContent(_ draft: ExplorePostComposerDraft, for post: ExplorePost) async {
        guard presentationServices.isOwnedByCurrentUser(post),
              !detailViewModel.isSavingPostContent else { return }

        do {
            persistPreferredCommonName(draft.selectedCommonName, scientificName: post.speciesScientificName)
            _ = try await detailViewModel.updateContent(draft)
            updateLocalFieldNotes(draft.fieldNotes ?? "")
            dismissPresentedSheet(
                ifMatching: ExplorePostDetailPresentation
                    .postComposer(postId: post.id)
                    .id
            )
            await viewModel.refreshPost(postId: post.id)
            viewModel.refreshPreferredSpeciesNames(for: [post.speciesScientificName], modelContext: modelContext)
            await loadPostDetail(force: true)
            HapticManager.shared.triggerSuccessPulse()
            viewModel.toastMessage = .success("Explore post updated")
        } catch {
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = .error(ExploreErrorFormatter.message(for: error))
        }
    }

    private func updateLocalFieldNotes(_ notes: String) {
        guard let post = currentPost,
              presentationServices.isOwnedByCurrentUser(post) else { return }

        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanId = post.scanId
        _ = FieldNotesRepository.setFieldNotes(
            notes,
            for: scanId,
            modelContext: modelContext
        )
        localFieldNotes = trimmed.isEmpty ? nil : notes
    }

    private func persistPreferredCommonName(_ name: String, scientificName: String) {
        guard let ownerUserID = supabase.currentUser?.id else { return }
        _ = SpeciesPreferredNameRepository.setPreferredName(
            name,
            for: scientificName,
            ownerUserID: ownerUserID,
            modelContext: modelContext
        )
    }

    private func syncPublicFieldNotesAfterInsightDismiss(for post: ExplorePost) async {
        guard presentationServices.isOwnedByCurrentUser(post) else { return }

        do {
            _ = try await detailViewModel.updateFieldNotes(localFieldNotes)
        } catch {
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = .error(ExploreErrorFormatter.message(for: error))
        }
    }

    private func reconcileFieldNotesAfterInsightDismiss(for post: ExplorePost) async {
        syncLocalFieldNotes(for: post)
        await loadPostDetail()

        guard detailViewModel.detail?.trimmedFieldNotes != nil else {
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
        guard presentationServices.isOwnedByCurrentUser(post), !hasPresentationConflict else { return }

        let scanId = post.scanId
        if let fieldNotes = detailViewModel.detail?.trimmedFieldNotes {
            localFieldNotes = FieldNotesRepository.promoteExternalFieldNotesIfLocalMissing(
                fieldNotes,
                for: scanId,
                modelContext: modelContext
            )
        }

        if let onOpenOwnedPostInsight {
            if onOpenOwnedPostInsight(scanId) {
                cancelPendingAsyncPresentations()
                HapticManager.shared.triggerSelectionPulse()
            } else {
                HapticManager.shared.triggerErrorThump()
                viewModel.toastMessage = .warning("This scan is not available on this device.")
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
            viewModel.toastMessage = .warning("This scan is not available on this device.")
            return
        }

        let route = ScanInsightRoute(scanId: record.id)
        if beginPresentation(.insight(route)) {
            HapticManager.shared.triggerSelectionPulse()
        }
    }

    private func openExploreFieldChat(for post: ExplorePost) {
        guard !hasPresentationConflict else { return }
        HapticManager.shared.triggerSelectionPulse()
        let isProActive = presentationServices.isProActive()
        presentationServices.trackFieldChatTapped(
            post.id,
            post.speciesScientificName,
            isProActive
        )

        guard isProActive else {
            _ = beginPresentation(.paywall)
            return
        }

        cancelPendingAsyncPresentations()
        pendingExploreChatPreparationPostID = post.id
    }

    private func openUnpublishConfirmation(for post: ExplorePost) {
        guard !hasPresentationConflict else { return }
        cancelPendingAsyncPresentations()
        postToUnpublish = post
    }

}
