import SwiftUI
import UIKit

struct ExplorePostDetailContentView: View {
    @Bindable var viewModel: ExploreFeedViewModel
    @Bindable var detailViewModel: ExplorePostDetailViewModel

    let post: ExplorePost
    let shouldFocusCommentComposer: Bool
    let shouldOpenInsight: Bool
    let targetCommentId: String?
    let targetReplyParentCommentId: String?
    let notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget?
    let allowsInsightPresentation: Bool
    let onOpenOwnedPostInsight: ((String) -> Bool)?
    let canOpenOwnedPostInsight: Bool
    let canOpenAuthorProfileRoutes: Bool
    let authorProfileDepth: Int
    let onOpenAuthorProfile: ((ExploreAuthorProfileRoute) -> Void)?
    let onOpenExploreMap: ((ExploreMapFocusTarget) -> Void)?
    let authorPresentation: ExplorePostCardAuthorPresentation
    let isOwnedByCurrentUser: Bool
    let localFieldNotes: String?
    let isRefreshingAfterInsightDismiss: Bool
    let isFieldChatAvailable: Bool
    let onLoadDetail: @MainActor () async -> Void
    let onSyncLocalFieldNotes: @MainActor () -> Void
    let onPresentNotificationReply: @MainActor (ExploreNotificationReplyThreadRoute) -> Bool
    let onOpenInsight: @MainActor () -> Void
    let onEditFieldNotes: @MainActor () -> Void
    let onEditPost: @MainActor () -> Void
    let onUnpublish: @MainActor () -> Void
    let onOpenFieldChat: @MainActor () -> Void
    let onDisappear: @MainActor () -> Void

    @Environment(ExploreVideoPlaybackCoordinator.self) private var playbackCoordinator: ExploreVideoPlaybackCoordinator?
    @FocusState private var isComposerFocused: Bool
    @State private var commentsSectionMinY: CGFloat = .infinity
    @State private var viewportHeight: CGFloat = 0
    @State private var focusedComposerIsSticky: Bool?
    @State private var isCommonNameScrolledPast = false
    @State private var didFocusTargetComment = false
    @State private var didAutoOpenInsight = false
    @State private var didPresentNotificationReplyThread = false
    @State private var isAudioBoostEnabled = false
    @State private var audioBoostActionToken: UUID?
    @State private var composerFocusTask: Task<Void, Never>?
    @State private var composerScrollTask: Task<Void, Never>?

    private let commentsSectionId = "explore-comments-section"
    private let commentsComposerId = "explore-comments-composer"

    private var isComposerSticky: Bool {
        commentsSectionMinY <= viewportHeight - 150
    }

    private var presentedComposerIsSticky: Bool {
        focusedComposerIsSticky ?? isComposerSticky
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    authorHeader
                    media
                    actionRow(scrollProxy: scrollProxy)
                    detailSections
                    commentsSection(sticky: false)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                        .id(commentsSectionId)
                        .background(commentsPositionReader)
                }
            }
            .coordinateSpace(name: "ExplorePostDetailScrollSpace")
            .safeAreaInset(edge: .bottom) {
                if presentedComposerIsSticky {
                    commentsSection(sticky: true)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: presentedComposerIsSticky)
            .onChange(of: presentedComposerIsSticky) { _, _ in
                HapticManager.shared.triggerLightImpact(intensity: 0.8)
            }
            .onChange(of: isComposerFocused) { _, isFocused in
                if isFocused {
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
            .toolbar { toolbarContent }
            .task(id: post.id) {
                async let detailTask: Void = onLoadDetail()
                async let commentsTask: Void = viewModel.openComments(for: post)
                _ = await (detailTask, commentsTask)
                await viewModel.expandPendingReplyThreadIfNeeded()
                await focusTargetCommentIfNeeded(using: scrollProxy)
                onSyncLocalFieldNotes()
                presentNotificationReplyThreadIfNeeded()

                if shouldFocusCommentComposer {
                    focusComments(using: scrollProxy, animated: false)
                }

                if canOpenOwnedPostInsight && shouldOpenInsight && !didAutoOpenInsight {
                    didAutoOpenInsight = true
                    do {
                        try await Task.sleep(for: .milliseconds(250))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    onOpenInsight()
                }
            }
            .onChange(of: post.id, initial: true) { _, _ in
                isCommonNameScrolledPast = false
                isAudioBoostEnabled = ExploreAudioBoostPreferenceStore().isEnabled(for: post.id)
                if isAudioBoostEnabled {
                    AppTelemetry.trackExploreAudioBoost(event: "restored", surface: "detail")
                }
            }
            .onChange(of: isAudioBoostEnabled) { _, enabled in
                ExploreAudioBoostPreferenceStore().setEnabled(enabled, for: post.id)
            }
            .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
                guard case let .exploreAudioBoostPreferenceChanged(postId, enabled) = event,
                      postId == post.id,
                      enabled != isAudioBoostEnabled else { return }
                isAudioBoostEnabled = enabled
            }
            .onDisappear {
                composerFocusTask?.cancel()
                composerFocusTask = nil
                composerScrollTask?.cancel()
                composerScrollTask = nil
                ExploreVideoMutePreference.resetToMuted()
                onDisappear()
            }
        }
        .background(viewportReader)
    }

    private var authorHeader: some View {
        ExplorePostDetailAuthorHeader(
            post: post,
            avatarUrl: authorPresentation.avatarURL,
            showsProBadge: authorPresentation.showsProBadge,
            locationText: post.publicDisplayLocationLabel,
            opensAuthorProfile: canOpenAuthorProfileRoutes,
            onOpenAuthorProfile: {
                onOpenAuthorProfile?(ExploreAuthorProfileRoute(post: post))
            }
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var media: some View {
        ExploreDetailMediaView(
            imageUrl: post.heroImageUrl,
            mediaItems: post.resolvedMediaItems,
            reloadGeneration: viewModel.mediaReloadGeneration,
            audioBoostEnabled: $isAudioBoostEnabled,
            audioBoostActionToken: audioBoostActionToken,
            onAudioBoostActionFinished: finishAudioBoostAction,
            onAudioBoostToggleRequested: toggleAudioBoostFromMedia
        )
    }

    private func actionRow(scrollProxy: ScrollViewProxy) -> some View {
        ExplorePostDetailActionRow(
            viewerHasLiked: post.viewerHasLiked,
            likeCountText: post.likeCount.formatted(.number.notation(.compactName)),
            commentCountText: post.commentCount.formatted(.number.notation(.compactName)),
            onLike: { Task { await viewModel.toggleLike(for: post) } },
            onComments: { focusComments(using: scrollProxy) },
            onShare: { viewModel.share(post, playbackCoordinator: playbackCoordinator) }
        )
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var detailSections: some View {
        VStack(spacing: 24) {
            ExplorePostDetailSpeciesSummary(
                scientificName: post.speciesScientificName,
                postCommonName: post.speciesCommonName,
                displayCommonName: viewModel.resolvedSpeciesCommonName(for: post),
                aiReasoning: detailViewModel.detail?.trimmedAiReasoning.map {
                    styledAiReasoning(text: $0, scientificName: post.speciesScientificName)
                },
                onCommonNameMaxYChange: evaluateCommonNameScrollOffset
            )

            hashtagRow
            toxicityBanner
            fieldNotesSection

            ExplorePostDetailInsightSection(
                post: post,
                scientificName: post.speciesScientificName,
                displayCommonName: viewModel.resolvedSpeciesCommonName(for: post),
                alternativeCommonNames: detailViewModel.detail?.alternativeCommonNames ?? [],
                detail: detailViewModel.detail,
                isLoading: detailViewModel.isLoadingDetail,
                errorMessage: detailViewModel.detailErrorMessage,
                onOpenExploreMap: onOpenExploreMap
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var hashtagRow: some View {
        if let hashtags = detailViewModel.detail?.hashtags, !hashtags.isEmpty {
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

    @ViewBuilder
    private var toxicityBanner: some View {
        if let hazardType = detailViewModel.detail?.hazardType {
            ToxicityBanner(hazardType: hazardType)
        }
    }

    @ViewBuilder
    private var fieldNotesSection: some View {
        let fieldNotes = detailViewModel.detail?.trimmedFieldNotes
            ?? (isOwnedByCurrentUser ? FieldNotesRepository.trimmedNonEmptyText(localFieldNotes) : nil)

        if !isRefreshingAfterInsightDismiss, let fieldNotes {
            ExploreFieldNotesCard(
                fieldNotes: fieldNotes,
                visibility: isOwnedByCurrentUser
                    ? (detailViewModel.detail?.trimmedFieldNotes != nil ? .published : .privateNotes)
                    : nil,
                canEdit: isOwnedByCurrentUser,
                onEdit: onEditFieldNotes
            )
        }
    }

    private func commentsSection(sticky: Bool) -> some View {
        ExplorePostDetailCommentsSection(
            viewModel: viewModel,
            post: post,
            composerId: commentsComposerId,
            targetCommentId: targetCommentId,
            targetReplyParentCommentId: targetReplyParentCommentId,
            isComposerFocused: $isComposerFocused,
            onDismissComposer: dismissCommentComposer,
            isComposerSticky: sticky,
            hideInlineComposer: sticky ? false : presentedComposerIsSticky,
            allowsAuthorProfilePresentation: canOpenAuthorProfileRoutes,
            onOpenAuthorProfile: onOpenAuthorProfile
        )
    }

    private var commentsPositionReader: some View {
        GeometryReader { geometry in
            Color.clear
                .onChange(
                    of: geometry.frame(in: .named("ExplorePostDetailScrollSpace")).minY,
                    initial: true
                ) { _, newMinY in
                    if newMinY.isFinite {
                        commentsSectionMinY = newMinY
                    }
                }
        }
    }

    private var viewportReader: some View {
        GeometryReader { geometry in
            Color.clear
                .onChange(of: geometry.size.height, initial: true) { _, newHeight in
                    if newHeight.isFinite, newHeight >= 0 {
                        viewportHeight = newHeight
                    }
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ScrollAwareToolbarTitleBadge(
                title: viewModel.resolvedSpeciesCommonName(for: post),
                isVisible: isCommonNameScrolledPast
            )
        }

        ToolbarItem(placement: .topBarTrailing) {
            ExplorePostDetailMenuButton(
                isOwnedByCurrentUser: isOwnedByCurrentUser,
                allowsInsightPresentation: canOpenOwnedPostInsight,
                onOpenInsight: onOpenInsight,
                onEditPost: onEditPost,
                onUnpublish: onUnpublish,
                showsFieldChatAction: ExplorePostFieldChatPresentationPolicy.showsMenuAction(
                    isFieldChatAvailable: isFieldChatAvailable,
                    isCommentComposerSticky: presentedComposerIsSticky,
                    isCommentComposerFocused: isComposerFocused
                ),
                onFieldChat: onOpenFieldChat,
                onBlockAuthor: { Task { await viewModel.blockAuthor(of: post) } },
                onReportPost: { Task { await viewModel.report(post) } },
                audioBoostEnabled: post.resolvedMediaItems.first?.kind == .audio
                    ? $isAudioBoostEnabled
                    : nil,
                onAudioBoostEnableRequested: {
                    audioBoostActionToken = UUID()
                }
            )
        }

        if ExplorePostFieldChatPresentationPolicy.showsFloatingButton(
            isFieldChatAvailable: isFieldChatAvailable,
            isCommentComposerSticky: presentedComposerIsSticky,
            isCommentComposerFocused: isComposerFocused
        ) {
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                FieldChatToolbarButton(action: onOpenFieldChat)
            }
        }
    }

    private func focusComments(using scrollProxy: ScrollViewProxy, animated: Bool = true) {
        let scrollBlock = { scrollProxy.scrollTo(commentsSectionId, anchor: .top) }
        if animated {
            withAnimation(.easeInOut(duration: 0.22), scrollBlock)
        } else {
            scrollBlock()
        }

        composerFocusTask?.cancel()
        composerFocusTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            isComposerFocused = true
            composerFocusTask = nil
        }
    }

    private func scrollFocusedInlineComposerIntoViewIfNeeded(
        using scrollProxy: ScrollViewProxy,
        composerWasSticky: Bool
    ) {
        guard !composerWasSticky else { return }
        composerScrollTask?.cancel()
        composerScrollTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard !Task.isCancelled, isComposerFocused, focusedComposerIsSticky == false else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                scrollProxy.scrollTo(commentsComposerId, anchor: .bottom)
            }
            composerScrollTask = nil
        }
    }

    private func presentNotificationReplyThreadIfNeeded() {
        guard !didPresentNotificationReplyThread,
              let notificationReplyThreadTarget else { return }

        let route = ExploreNotificationReplyThreadRoute(
            post: post,
            parentCommentId: notificationReplyThreadTarget.parentCommentId,
            targetReplyId: notificationReplyThreadTarget.targetReplyId,
            fallbackReply: notificationReplyThreadTarget.fallbackReply
        )
        guard onPresentNotificationReply(route) else { return }
        didPresentNotificationReplyThread = true
    }

    private func focusTargetCommentIfNeeded(using scrollProxy: ScrollViewProxy) async {
        guard let targetCommentId, !didFocusTargetComment else { return }
        if let targetReplyParentCommentId {
            let targetReplyId = targetReplyParentCommentId == targetCommentId ? nil : targetCommentId
            await viewModel.expandReplyThread(
                parentCommentId: targetReplyParentCommentId,
                targetReplyId: targetReplyId
            )
        } else {
            await viewModel.loadCommentsUntilCommentIfNeeded(commentId: targetCommentId)
        }
        await performTargetCommentScroll(using: scrollProxy, targetCommentId: targetCommentId)
    }

    private func performTargetCommentScroll(
        using scrollProxy: ScrollViewProxy,
        targetCommentId: String
    ) async {
        let isTargetingReply = targetReplyParentCommentId != nil && targetReplyParentCommentId != targetCommentId
        let scrollId = isTargetingReply
            ? ExploreCommentScrollTarget.reply(targetCommentId).id
            : ExploreCommentScrollTarget.comment(targetCommentId).id
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
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func evaluateCommonNameScrollOffset(maxY: CGFloat) {
        guard maxY.isFinite else { return }
        let isPast = maxY < 44
        guard isCommonNameScrolledPast != isPast else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isCommonNameScrolledPast = isPast
        }
    }

    private func finishAudioBoostAction(_ token: UUID) {
        guard audioBoostActionToken == token else { return }
        audioBoostActionToken = nil
    }

    private func toggleAudioBoostFromMedia() {
        if !isAudioBoostEnabled {
            audioBoostActionToken = UUID()
        }
        isAudioBoostEnabled.toggle()
        if isAudioBoostEnabled {
            HapticManager.shared.triggerMediumPulse(
                source: "media.explore.detail.audioBoost.enabled"
            )
        } else {
            HapticManager.shared.triggerLightImpact(
                intensity: 0.5,
                source: "media.explore.detail.audioBoost.disabled"
            )
        }
    }

    private func styledAiReasoning(
        text: String,
        scientificName: String
    ) -> AttributedString {
        let cleanText = text
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
        var result = AttributedString(cleanText)
        let normalizedScientificName = scientificName
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !normalizedScientificName.isEmpty {
            var searchRange = result.startIndex..<result.endIndex
            while let range = result[searchRange].range(
                of: normalizedScientificName,
                options: .caseInsensitive
            ) {
                result[range].font = .system(.body, design: .monospaced)
                result[range].backgroundColor = Color.secondary.opacity(0.15)
                searchRange = range.upperBound..<result.endIndex
            }
        }
        return result
    }
}
