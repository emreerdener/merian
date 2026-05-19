import SwiftData
import SwiftUI

struct ExplorePostDetailView: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let postId: String
    let shouldFocusCommentComposer: Bool
    let shouldOpenInsight: Bool
    let allowsInsightPresentation: Bool
    let allowsAuthorProfilePresentation: Bool

    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isComposerFocused: Bool
    @State private var detail: ExplorePostDetail?
    @State private var isLoadingDetail = false
    @State private var detailErrorMessage: String?
    @State private var isUpdatingFieldNotesVisibility = false
    @State private var showHideFieldNotesConfirmation = false
    @State private var showFieldNotesEditor = false
    @State private var localFieldNotes: String?
    @State private var selectedInsightRecord: LocalScanRecord?
    @State private var selectedAuthorProfileRoute: ExploreAuthorProfileRoute?
    @State private var isRefreshingAfterInsightDismiss = false
    @State private var didAutoOpenInsight = false
    @State private var isCommonNameScrolledPast = false
    @State private var postToUnpublish: ExplorePost?

    private let commentsSectionId = "explore-comments-section"
    private let commentsComposerId = "explore-comments-composer"

    init(
        viewModel: ExploreFeedViewModel,
        postId: String,
        shouldFocusCommentComposer: Bool,
        shouldOpenInsight: Bool,
        allowsInsightPresentation: Bool,
        allowsAuthorProfilePresentation: Bool = true
    ) {
        self.viewModel = viewModel
        self.postId = postId
        self.shouldFocusCommentComposer = shouldFocusCommentComposer
        self.shouldOpenInsight = shouldOpenInsight
        self.allowsInsightPresentation = allowsInsightPresentation
        self.allowsAuthorProfilePresentation = allowsAuthorProfilePresentation
    }

    private var currentPost: ExplorePost? {
        viewModel.post(id: postId)
    }

    private var fieldNotesArePublicOnExplore: Bool {
        detail?.trimmedFieldNotes != nil
    }

    private var canManageFieldNotes: Bool {
        detail?.trimmedFieldNotes != nil
            || localFieldNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
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
                                opensAuthorProfile: allowsAuthorProfilePresentation,
                                onOpenAuthorProfile: {
                                    selectedAuthorProfileRoute = ExploreAuthorProfileRoute(post: post)
                                }
                            )
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 12)

                            ExploreDetailMediaView(
                                imageUrl: post.heroImageUrl,
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
                                    viewModel.share(post)
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
                                    alternativeCommonNames: detail?.alternativeCommonNames ?? [],
                                    aiReasoning: detail?.trimmedAiReasoning.map {
                                        styledAiReasoning(text: $0, scientificName: post.speciesScientificName)
                                    },
                                    onCommonNameMaxYChange: {
                                        evaluateCommonNameScrollOffset(maxY: $0)
                                    }
                                )

                                fieldNotesSection(for: post)

                                ExplorePostDetailInsightSection(
                                    scientificName: post.speciesScientificName,
                                    currentCommonName: viewModel.resolvedSpeciesCommonName(for: post),
                                    detail: detail,
                                    isLoading: isLoadingDetail,
                                    errorMessage: detailErrorMessage
                                )

                                ExploreObservationContextCard(post: post)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 16)

                            ExplorePostDetailCommentsSection(
                                viewModel: viewModel,
                                post: post,
                                composerId: commentsComposerId,
                                isComposerFocused: $isComposerFocused,
                                onDismissComposer: dismissCommentComposer
                            )
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                                .padding(.bottom, 24)
                                .id(commentsSectionId)
                        }
                    }
                    .coordinateSpace(name: "ExplorePostDetailScrollSpace")
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
                                allowsInsightPresentation: allowsInsightPresentation,
                                canManageFieldNotes: canManageFieldNotes,
                                fieldNotesArePublic: fieldNotesArePublicOnExplore,
                                isUpdatingFieldNotesVisibility: isUpdatingFieldNotesVisibility,
                                onOpenInsight: { openInsight(for: post) },
                                onEditFieldNotes: { openFieldNotesEditor(for: post) },
                                onToggleFieldNotesVisibility: { showFieldNotesVisibilityConfirmation() },
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
                        syncLocalFieldNotes(for: post)

                        if shouldFocusCommentComposer {
                            focusComments(using: scrollProxy, animated: false)
                        }

                        if allowsInsightPresentation && shouldOpenInsight && !didAutoOpenInsight {
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
        .overlay {
            if showHideFieldNotesConfirmation {
                ExploreFieldNotesVisibilityOverlay(
                    fieldNotesArePublic: fieldNotesArePublicOnExplore,
                    isUpdating: isUpdatingFieldNotesVisibility,
                    onCancel: hideFieldNotesVisibilityConfirmation,
                    onConfirm: { nextVisibility in
                        hideFieldNotesVisibilityConfirmation()
                        Task { await updateFieldNotesVisibility(isPublic: nextVisibility) }
                    }
                )
            }
        }
        .sheet(item: $selectedInsightRecord, onDismiss: {
            isRefreshingAfterInsightDismiss = true
            Task {
                if let post = currentPost {
                    await reconcileFieldNotesAfterInsightDismiss(for: post)
                } else {
                    await loadPostDetail()
                }
                isRefreshingAfterInsightDismiss = false
            }
        }) { record in
            InsightSheetView(
                isPresented: Binding(
                    get: { selectedInsightRecord != nil },
                    set: { if !$0 { selectedInsightRecord = nil } }
                ),
                initialRecord: record,
                inferenceEngine: inferenceEngine,
                allowsExplorePresentation: false
            )
        }
        .sheet(item: $selectedAuthorProfileRoute) { route in
            ExploreAuthorProfileSheet(viewModel: viewModel, route: route)
        }
        .sheet(isPresented: $showFieldNotesEditor, onDismiss: {
            Task {
                if let post = currentPost {
                    await reconcileFieldNotesAfterInsightDismiss(for: post)
                } else {
                    await loadPostDetail()
                }
            }
        }) {
            FieldNotesSheet(
                text: Binding(
                    get: { localFieldNotes ?? detail?.trimmedFieldNotes ?? "" },
                    set: { updateLocalFieldNotes($0) }
                ),
                promptContext: .resolved(subjectId: nil)
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
        if !isRefreshingAfterInsightDismiss, let fieldNotes = detail?.trimmedFieldNotes {
            ExploreFieldNotesCard(
                fieldNotes: fieldNotes,
                fieldNotesArePublic: true,
                canToggleVisibility: isOwnedByCurrentUser(post),
                canEdit: isOwnedByCurrentUser(post),
                isUpdating: isUpdatingFieldNotesVisibility,
                onEdit: { openFieldNotesEditor(for: post) },
                onToggleVisibility: showFieldNotesVisibilityConfirmation
            )
        }
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

    private func showFieldNotesVisibilityConfirmation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showHideFieldNotesConfirmation = true
        }
    }

    private func hideFieldNotesVisibilityConfirmation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showHideFieldNotesConfirmation = false
        }
    }

    private func updateFieldNotesVisibility(isPublic: Bool) async {
        guard let post = currentPost, isOwnedByCurrentUser(post) else { return }
        guard !isUpdatingFieldNotesVisibility else { return }

        let notesToPublish = (localFieldNotes ?? detail?.trimmedFieldNotes)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isPublic || notesToPublish?.isEmpty == false else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                viewModel.toastMessage = "Add field notes before publishing them"
            }
            return
        }

        isUpdatingFieldNotesVisibility = true
        defer { isUpdatingFieldNotesVisibility = false }

        do {
            if !isPublic, let notesToPublish {
                preserveLocalFieldNotes(notesToPublish, for: post)
            }

            let response = try await MerianNetworkClient.shared.updateExplorePostFieldNotes(
                postId: post.id,
                fieldNotes: isPublic ? notesToPublish : nil
            )
            if response.postId == post.id {
                detail?.fieldNotes = response.fieldNotes
            } else {
                detail?.fieldNotes = isPublic ? notesToPublish : nil
            }
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                viewModel.toastMessage = detail?.trimmedFieldNotes == nil
                    ? "Field notes are now private"
                    : "Field notes are now public on Explore"
            }
        } catch {
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                viewModel.toastMessage = ExploreErrorFormatter.message(for: error)
            }
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
        guard allowsInsightPresentation else { return }
        guard isOwnedByCurrentUser(post) else { return }

        let scanId = post.scanId
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )

        guard let record = try? modelContext.fetch(descriptor).first else {
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = "This scan is not available on this device."
            return
        }

        if let fieldNotes = detail?.trimmedFieldNotes {
            localFieldNotes = FieldNotesRepository.promoteExternalFieldNotesIfLocalMissing(
                fieldNotes,
                for: scanId,
                modelContext: modelContext,
                activeRecord: record
            )
        }

        inferenceEngine.load(from: record)
        HapticManager.shared.triggerSelectionPulse()
        selectedInsightRecord = record
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
