import SwiftData
import SwiftUI
import UIKit

enum ExploreTab: Hashable {
    case feed
    case community
    case fieldTrips
    case dictionary
}

private enum ExploreDiscoveryMode: Hashable {
    case feed
    case map
}

private enum ExploreDictionaryMode: Hashable {
    case dictionary
    case tree
}

struct ExploreView: View {
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(AppSettings.self) private var appSettings
    @Environment(EnvironmentContextManager.self) private var environmentContextManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ExploreFeedViewModel()
    @State private var mapViewModel = ExploreMapViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var selectedAuthorProfileRoute: ExploreAuthorProfileRoute?
    @State private var selectedInsightRoute: ScanInsightRoute?
    @State private var activeTab: ExploreTab = .feed
    @State private var activeDiscoveryMode: ExploreDiscoveryMode = .feed
    @State private var activeDictionaryMode: ExploreDictionaryMode = .dictionary
    @State private var activeCommunityMode: CommunityIdentificationMode = .requests
    @State private var activeFieldTripsSection: FieldTripsSection = .available
    @State private var dictionaryUserRegionIdentifier = Self.defaultDictionaryUserRegionIdentifier()
    @State private var playbackCoordinator = ExploreVideoPlaybackCoordinator()

    private let allowsInsightPresentation: Bool
    private let onOpenOwnedPostInsight: ((String) -> Bool)?

    private var canOpenOwnedPostInsight: Bool {
        allowsInsightPresentation || onOpenOwnedPostInsight != nil
    }

    private var ownedPostInsightHandler: ((String) -> Bool)? {
        guard onOpenOwnedPostInsight != nil else { return nil }
        return { scanId in openOwnedPostInsightFromParent(scanId) }
    }

    private var hasPresentedRootOverlay: Bool {
        viewModel.isCommentsSheetPresented ||
            viewModel.isNotificationsSheetPresented ||
            selectedInsightRoute != nil ||
            selectedAuthorProfileRoute != nil
    }

    private var activeTabBinding: Binding<ExploreTab> {
        Binding(
            get: { activeTab },
            set: { newValue in
                guard newValue != activeTab else { return }
                selectExploreTab(newValue)
            }
        )
    }

    init(
        initialPostId: String? = nil,
        initialCommunityRequestId: String? = nil,
        initialTargetCommentId: String? = nil,
        initialTargetReplyParentCommentId: String? = nil,
        allowsInsightPresentation: Bool = true,
        onOpenOwnedPostInsight: ((String) -> Bool)? = nil
    ) {
        self.allowsInsightPresentation = allowsInsightPresentation
        self.onOpenOwnedPostInsight = onOpenOwnedPostInsight
        if let requestId = initialCommunityRequestId {
            var initialPath = NavigationPath()
            initialPath.append(ExploreCommunityRequestRoute(requestId: requestId))
            _navigationPath = State(initialValue: initialPath)
            _activeTab = State(initialValue: .community)
        } else if let postId = initialPostId {
            var initialPath = NavigationPath()
            initialPath.append(ExplorePostRoute(
                postId: postId,
                shouldFocusCommentComposer: false,
                shouldOpenInsight: false,
                targetCommentId: initialTargetCommentId,
                targetReplyParentCommentId: initialTargetReplyParentCommentId
            ))
            _navigationPath = State(initialValue: initialPath)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            TabView(selection: activeTabBinding) {
                discoveryTabContent
                .tag(ExploreTab.feed)
                .tabItem {
                    Label("Observations", systemImage: "photo.stack")
                }

                ExploreCommunityIdentificationView(activeMode: $activeCommunityMode) { route in
                    navigationPath.append(route)
                }
                .tag(ExploreTab.community)
                .tabItem {
                    Label("Identify", systemImage: "person.crop.badge.magnifyingglass.fill")
                }

                FieldTripsView(
                    userRegion: dictionaryUserRegionIdentifier,
                    selectedSection: $activeFieldTripsSection,
                    onOpenPublication: { publicationId in
                        navigationPath.append(FieldTripPublicationRoute(publicationId: publicationId))
                    },
                    onOpenAuthorProfile: openAuthorProfile
                )
                .tag(ExploreTab.fieldTrips)
                .tabItem {
                    Label("Field Trips", systemImage: "map")
                }

                dictionaryTabContent
                .background(Color(uiColor: .systemGroupedBackground))
                .tag(ExploreTab.dictionary)
                .tabItem {
                    Label("Index", systemImage: "book.closed")
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ExplorePostRoute.self) { route in
                ExplorePostDetailView(
                    viewModel: viewModel,
                    postId: route.postId,
                    shouldFocusCommentComposer: route.shouldFocusCommentComposer,
                    shouldOpenInsight: route.shouldOpenInsight,
                    targetCommentId: route.targetCommentId,
                    targetReplyParentCommentId: route.targetReplyParentCommentId,
                    notificationReplyThreadTarget: route.notificationReplyThreadTarget,
                    allowsInsightPresentation: allowsInsightPresentation,
                    onOpenOwnedPostInsight: ownedPostInsightHandler,
                    onOpenCommunityIdentificationRequest: openCommunityIdentificationRequest
                )
                .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: SpeciesDictionaryRoute.self) { route in
                SpeciesDictionaryPageContentView(
                    scientificName: route.scientificName,
                    speciesId: route.speciesId,
                    entryPoint: route.entryPoint,
                    showsCloseButton: false
                )
                .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: SpeciesDictionaryCategoryRoute.self) { route in
                switch route {
                case .catalog(let title, let category, let region):
                    SpeciesDictionaryCatalogView(
                        isSearchEnabled: false,
                        isBottomSearchEnabled: true,
                        showsNavigationTitle: true,
                        navigationTitle: title,
                        category: category,
                        region: region
                    )
                    .toolbar(.hidden, for: .tabBar)
                    .toolbar {}
                case .group(let title, let group):
                    SpeciesDictionaryCatalogView(
                        isSearchEnabled: false,
                        isBottomSearchEnabled: true,
                        showsNavigationTitle: true,
                        navigationTitle: title,
                        category: .group,
                        group: group
                    )
                    .toolbar(.hidden, for: .tabBar)
                    .toolbar {}
                case .taxonomy:
                    TaxonomyTreeCanvasView(showsNavigationTitle: true) { speciesRoute in
                        navigationPath.append(speciesRoute)
                    }
                    .toolbar(.hidden, for: .tabBar)
                    .toolbar {}
                case .regions:
                    SpeciesDictionaryRegionsView(userRegion: dictionaryUserRegionIdentifier)
                        .toolbar(.hidden, for: .tabBar)
                        .toolbar {}
                }
            }
            .navigationDestination(for: ExploreHashtagRoute.self) { route in
                ExploreHashtagPostsView(
                    viewModel: viewModel,
                    route: route,
                    allowsInsightPresentation: allowsInsightPresentation,
                    onOpenOwnedPostInsight: ownedPostInsightHandler
                )
                .toolbar(.hidden, for: .tabBar)
                .toolbar {}
            }
            .navigationDestination(for: ExploreCommunityRequestRoute.self) { route in
                ExploreCommunityIdentificationDetailView(requestId: route.requestId)
                    .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: FieldTripTemplateRoute.self) { route in
                FieldTripTemplateDetailView(
                    templateId: route.templateId,
                    onOpenPublication: { publicationId in
                        navigationPath.append(FieldTripPublicationRoute(publicationId: publicationId))
                    },
                    onOpenAuthorProfile: openAuthorProfile
                )
                .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: FieldTripChallengeRoute.self) { route in
                FieldTripChallengeDetailView(
                    challengeId: route.challengeId,
                    onOpenEntry: { entryId in
                        navigationPath.append(FieldTripChallengeEntryRoute(entryId: entryId))
                    },
                    onOpenAuthorProfile: openAuthorProfile
                )
                .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: FieldTripPublicationRoute.self) { route in
                FieldTripPublicationDetailView(publicationId: route.publicationId)
                    .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: FieldTripChallengeEntryRoute.self) { route in
                FieldTripChallengeEntryDetailView(entryId: route.entryId)
                    .toolbar(.hidden, for: .tabBar)
            }
            .toolbar { exploreToolbar }
        }
        .exploreVideoOverlayLifecycle(
            isPresented: hasPresentedRootOverlay,
            reason: "explore-root-sheet"
        )
        .environment(playbackCoordinator)
        .task {
            viewModel.bindSettings(appSettings)
            await viewModel.loadInitialFeed()
            viewModel.refreshPreferredSpeciesNames(modelContext: modelContext)
        }
        .onChange(of: viewModel.store.changeVersion) { _, _ in
            viewModel.refreshPreferredSpeciesNames(modelContext: modelContext)
        }
        .onChange(of: activeDiscoveryMode) { _, newValue in
            HapticManager.shared.triggerSelectionPulse()
            if newValue == .map {
                AppTelemetry.trackExploreMapOpened()
            }
        }
        .onChange(of: activeDictionaryMode) { _, _ in
            HapticManager.shared.triggerSelectionPulse()
        }
        .onChange(of: activeCommunityMode) { _, _ in
            HapticManager.shared.triggerSelectionPulse()
        }
        .task(id: activeTab) {
            guard activeTab == .dictionary else { return }
            await refreshDictionaryUserRegionFromAuthorizedLocation()
        }
        .task {
            await viewModel.startUnreadNotificationUpdates()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                await viewModel.refreshUnreadNotificationCount()
            }
        }
        .onDisappear {
            viewModel.stopUnreadNotificationUpdates()
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isCommentsSheetPresented },
                set: { if !$0 { viewModel.dismissCommentsSheet() } }
            ),
            onDismiss: {}
        ) {
            if let post = viewModel.activeCommentsPost {
                ExploreCommentsSheet(viewModel: viewModel, post: post)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isNotificationsSheetPresented },
                set: { if !$0 { viewModel.dismissNotifications() } }
            ),
            onDismiss: {
                Task { await viewModel.refreshUnreadNotificationCount() }
            }
        ) {
            ExploreNotificationsSheet(
                onUnreadNotificationsCleared: {
                    viewModel.unreadNotificationCount = 0
                    AppIconBadgeCoordinator.clearExploreUnreadNotificationCount()
                },
                onOpenNotification: { notification in
                    await openNotification(notification)
                }
            )
        }
        .sheet(
            item: $selectedInsightRoute,
            onDismiss: {
                viewModel.refreshPreferredSpeciesNames(modelContext: modelContext)
            }
        ) { route in
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
                    openCommunityIdentificationRequest(requestId)
                }
            )
        }
        .sheet(item: $selectedAuthorProfileRoute) { route in
            ExploreAuthorProfileSheet(viewModel: viewModel, route: route)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.refreshUnreadNotificationCount() }
        }
        .onReceive(AppEventPublisher.shared.publisher) { event in
            switch event {
            case .explorePostNeedsRefresh(let postId):
                Task { await viewModel.refreshPost(postId: postId) }
            case .openCommunityIdentificationRequest(let requestId):
                openCommunityIdentificationRequest(requestId)
            case .fieldTripProgressUpdated(let updates):
                if let update = updates.first,
                   let item = update.newlyCompletedItems.first {
                    let label = item.commonName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        ?? item.prompt
                    viewModel.toastMessage = "\(update.title): \(label)"
                }
            case .publicAuthorIdentityChanged(let previousUserId, let currentUserId):
                selectedAuthorProfileRoute = selectedAuthorProfileRoute.flatMap { route in
                    authorIdentityChangeAffects(route.authorUserId, previousUserId: previousUserId, currentUserId: currentUserId)
                        ? nil
                        : route
                }
                Task {
                    await viewModel.refreshFeed()
                    mapViewModel.syncPosts(from: viewModel.store.allPosts)
                }
            default:
                break
            }
        }
        .merianSystemFeedback(
            toastMessage: Binding(
                get: { viewModel.toastMessage },
                set: { viewModel.toastMessage = $0 }
            ),
            toastAlignment: .top
        )
    }

    @ToolbarContentBuilder
    private var exploreToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                HapticManager.shared.triggerLightImpact(intensity: 0.45)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
            }
        }

        ToolbarItem(placement: .principal) {
            ExploreRootModePicker(
                activeTab: activeTab,
                activeDiscoveryMode: $activeDiscoveryMode,
                activeDictionaryMode: $activeDictionaryMode,
                activeCommunityMode: $activeCommunityMode,
                activeFieldTripsSection: $activeFieldTripsSection
            )
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 0) {
                bellButton
            }
        }
    }

    @ViewBuilder
    private var discoveryTabContent: some View {
        switch activeDiscoveryMode {
        case .feed:
            ExploreFeedTabContent(
                viewModel: viewModel,
                onOpenPostDetail: { openPostDetail(for: $0) },
                onOpenAuthorProfile: { openAuthorProfile(for: $0) },
                onOpenHashtag: openHashtag,
                onOpenInsight: canOpenOwnedPostInsight ? { openInsight(for: $0) } : nil
            )
        case .map:
            ExploreMapView(
                viewModel: mapViewModel,
                feedViewModel: viewModel,
                postStore: viewModel.store,
                onOpenDetail: { post, focusCommentComposer in
                    openPostDetail(for: post, focusCommentComposer: focusCommentComposer)
                }
            )
        }
    }

    @ViewBuilder
    private var dictionaryTabContent: some View {
        switch activeDictionaryMode {
        case .dictionary:
            SpeciesDictionaryOverviewView(userRegion: dictionaryUserRegionIdentifier)
        case .tree:
            TaxonomyTreeCanvasView(showsNavigationTitle: false) { speciesRoute in
                navigationPath.append(speciesRoute)
            }
        }
    }

    private var shouldShowRootModePicker: Bool {
        navigationPath.isEmpty
    }

    private func openPostDetail(
        for post: ExplorePost,
        focusCommentComposer: Bool = false,
        openInsight: Bool = false,
        targetCommentId: String? = nil,
        targetReplyParentCommentId: String? = nil,
        notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget? = nil
    ) {
        viewModel.upsertPost(post)
        viewModel.refreshPreferredSpeciesNames(for: [post.speciesScientificName], modelContext: modelContext)
        navigationPath.append(ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: focusCommentComposer,
            shouldOpenInsight: canOpenOwnedPostInsight && openInsight,
            targetCommentId: targetCommentId,
            targetReplyParentCommentId: targetReplyParentCommentId,
            notificationReplyThreadTarget: notificationReplyThreadTarget
        ))
    }

    private func openAuthorProfile(for post: ExplorePost) {
        HapticManager.shared.triggerSelectionPulse()
        viewModel.upsertPost(post)
        selectedAuthorProfileRoute = ExploreAuthorProfileRoute(post: post)
    }

    private func openAuthorProfile(for publication: FieldTripRecentPublication) {
        HapticManager.shared.triggerSelectionPulse()
        selectedAuthorProfileRoute = ExploreAuthorProfileRoute(
            authorUserId: publication.authorUserId,
            authorName: publication.authorName,
            authorUsername: publication.authorUsername,
            authorAvatarUrl: publication.authorAvatarUrl
        )
    }

    private func openAuthorProfile(for entry: FieldTripChallengeEntry) {
        HapticManager.shared.triggerSelectionPulse()
        selectedAuthorProfileRoute = ExploreAuthorProfileRoute(
            authorUserId: entry.authorUserId,
            authorName: entry.authorName,
            authorUsername: entry.authorUsername,
            authorAvatarUrl: entry.authorAvatarUrl
        )
    }

    private func openHashtag(_ hashtag: String) {
        HapticManager.shared.triggerSelectionPulse()
        navigationPath.append(ExploreHashtagRoute(hashtag: hashtag))
    }

    private func openCommunityIdentificationRequest(_ requestId: String) {
        var requestPath = NavigationPath()
        requestPath.append(ExploreCommunityRequestRoute(requestId: requestId))
        activeTab = .community
        navigationPath = requestPath
    }

    private func selectExploreTab(_ tab: ExploreTab) {
        HapticManager.shared.triggerSelectionPulse()
        activeTab = tab
    }

    private func openInsight(for post: ExplorePost) {
        guard isOwnedByCurrentUser(post) else { return }

        if onOpenOwnedPostInsight != nil {
            if openOwnedPostInsightFromParent(post.scanId) {
                HapticManager.shared.triggerSelectionPulse()
            } else {
                HapticManager.shared.triggerErrorThump()
                viewModel.toastMessage = "This scan is not available on this device."
            }
            return
        }

        guard allowsInsightPresentation else { return }

        let scanId = post.scanId
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )

        guard let record = try? modelContext.fetch(descriptor).first else {
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = "This scan is not available on this device."
            return
        }

        inferenceEngine.load(from: record)
        HapticManager.shared.triggerSelectionPulse()
        selectedInsightRoute = ScanInsightRoute(scanId: record.id)
    }

    private func openOwnedPostInsightFromParent(_ scanId: String) -> Bool {
        guard let onOpenOwnedPostInsight else { return false }
        let didOpen = onOpenOwnedPostInsight(scanId)
        if didOpen {
            dismiss()
        }
        return didOpen
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

    private var bellButton: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                HapticManager.shared.triggerSelectionPulse()
                viewModel.presentNotifications()
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            
            if viewModel.unreadNotificationCount > 0 {
                notificationUnreadDot
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(accessibilityNotificationLabel)
    }

    private var notificationUnreadDot: some View {
        Circle()
            .fill(Color(uiColor: .systemRed))
            .frame(width: 11, height: 11)
            .overlay(
                Circle()
                    .stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
    }

    private var accessibilityNotificationLabel: String {
        if viewModel.unreadNotificationCount == 0 {
            return "Notifications"
        }
        return "Notifications, \(viewModel.unreadNotificationCount) unread"
    }

    private func openNotification(_ notification: ExploreNotification) async {
        if notification.type.isCommunityNotification,
           let requestId = notification.communityRequestId {
            viewModel.dismissNotifications()
            openCommunityIdentificationRequest(requestId)
            return
        }

        if notification.type.isFieldTripNotification,
           let publicationId = notification.fieldTripPublicationId {
            viewModel.dismissNotifications()
            activeTab = .fieldTrips
            navigationPath.append(FieldTripPublicationRoute(publicationId: publicationId))
            return
        }

        guard let postId = notification.postId else { return }

        do {
            let post = try await viewModel.preparePostForNavigation(postId: postId)
            viewModel.dismissNotifications()
            let targetReplyParentCommentId = notification.parentCommentId
                ?? (notification.type == .commentReply ? notification.commentId : nil)
            let targetCommentId = targetReplyParentCommentId == notification.commentId
                ? nil
                : notification.commentId

            if notification.type == .commentReply,
               let targetReplyId = notification.commentId {
                openPostDetail(
                    for: post,
                    notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget(
                        parentCommentId: notification.parentCommentId,
                        targetReplyId: targetReplyId,
                        fallbackReply: ExploreNotificationReplyFallback(
                            commentId: targetReplyId,
                            body: notification.commentBody,
                            authorUserId: notification.triggeringUserId,
                            authorName: notification.triggeringUserName,
                            createdAt: notification.createdAt
                        )
                    )
                )
                return
            }

            if targetReplyParentCommentId != nil {
                viewModel.prepareToExpandReplyThread(parentCommentId: targetReplyParentCommentId)
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            openPostDetail(
                for: post,
                focusCommentComposer: notification.type == .comment && targetCommentId == nil,
                targetCommentId: targetCommentId ?? targetReplyParentCommentId,
                targetReplyParentCommentId: targetReplyParentCommentId
            )
        } catch {
            MerianLog.network.error(
                "Failed to open Explore notification \(notification.id, privacy: .private): \(error.localizedDescription, privacy: .private)"
            )
            AppTelemetry.trackExploreNotificationOpenFailed(type: notification.type.rawValue)
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private static func defaultDictionaryUserRegionIdentifier() -> String? {
        EnvironmentContextManager.normalizedRegionIdentifier(Locale.current.region?.identifier)
    }

    @MainActor
    private func refreshDictionaryUserRegionFromAuthorizedLocation() async {
        guard let regionIdentifier = await environmentContextManager.currentAuthorizedRegionIdentifier(),
              regionIdentifier != dictionaryUserRegionIdentifier else {
            return
        }

        dictionaryUserRegionIdentifier = regionIdentifier
    }
}

private struct ExploreFeedTabContent: View {
    @Bindable var viewModel: ExploreFeedViewModel
    @Environment(EnvironmentContextManager.self) private var environmentContextManager
    @Environment(ExploreVideoPlaybackCoordinator.self) private var playbackCoordinator: ExploreVideoPlaybackCoordinator?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var isLocationSettingsAlertPresented = false
    @State private var isResolvingNearbyLocation = false
    @State private var editingPost: ExplorePost?
    @State private var editingPostDetail: ExplorePostDetail?
    @State private var editingPostMediaItems: [ExplorePostComposerMediaDraft] = []
    @State private var editingPostLocalFieldNotes: String?
    @State private var isSavingEditedPost = false
    let onOpenPostDetail: (ExplorePost) -> Void
    let onOpenAuthorProfile: (ExplorePost) -> Void
    let onOpenHashtag: (String) -> Void
    let onOpenInsight: ((ExplorePost) -> Void)?

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            Group {
                if viewModel.isLoadingInitialFeed && viewModel.posts.isEmpty {
                    loadingState
                } else if let errorMessage = viewModel.errorMessage, viewModel.posts.isEmpty {
                    errorState(message: errorMessage)
                } else if viewModel.posts.isEmpty {
                    emptyState
                } else {
                    feedScrollView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .exploreVideoOverlayLifecycle(
            isPresented: editingPost != nil,
            reason: "explore-feed-edit-post"
        )
        .alert("Turn On Location", isPresented: $isLocationSettingsAlertPresented) {
            Button("Not Now", role: .cancel) {}
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    openURL(settingsURL)
                }
            }
        } message: {
            Text("Nearby uses your current location to show discoveries shared within \(ExploreFeedFilter.nearbyRadiusMiles) miles.")
        }
        .sheet(item: $editingPost, onDismiss: {
            clearPostEditor()
        }) { post in
            ExplorePostComposerView(
                mode: .edit,
                speciesName: postSnapshotCommonName(for: post),
                scientificName: post.speciesScientificName,
                heroImageUrl: post.heroImageUrl,
                publicLocationLabel: post.publicDisplayLocationLabel,
                commonNameOptions: commonNameOptions(for: post, detail: editingPostDetail),
                initialSelectedCommonName: postSnapshotCommonName(for: post),
                initialFieldNotes: editingPostDetail?.trimmedFieldNotes ?? editingPostLocalFieldNotes,
                initialFieldNotesArePublic: editingPostDetail?.trimmedFieldNotes != nil,
                initialHashtags: editingPostDetail?.hashtags ?? post.hashtags ?? [],
                initialLocationSharing: editingPostDetail?.locationSharing ?? post.locationSharing ?? .obscured,
                mediaItems: editingPostMediaItems,
                isSaving: isSavingEditedPost,
                onSubmit: { draft in
                    Task { await saveEditedPost(draft, for: post) }
                }
            )
        }
    }

    private var feedScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterBar
                
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.posts) { post in
                        ExplorePostCard(
                            post: post,
                            speciesDisplayName: viewModel.resolvedSpeciesCommonName(for: post),
                            mediaReloadGeneration: viewModel.mediaReloadGeneration,
                            onLike: { Task { await viewModel.toggleLike(for: post) } },
                            onComments: {
                                Task { await viewModel.openCommentsSheet(for: post) }
                            },
                            onShare: { viewModel.share(post, playbackCoordinator: playbackCoordinator) },
                            onOpenDetail: { onOpenPostDetail(post) },
                            onOpenAuthorProfile: { onOpenAuthorProfile(post) },
                            onOpenHashtag: onOpenHashtag,
                            onOpenInsight: onOpenInsight.map { callback in
                                { callback(post) }
                            },
                            onEditPost: { Task { await openPostEditor(for: post) } },
                            onUnshare: { Task { await viewModel.unshare(post) } },
                            onBlock: { Task { await viewModel.blockAuthor(of: post) } },
                            onReport: { Task { await viewModel.report(post) } }
                        )
                        .onAppear {
                            Task { await viewModel.loadMoreIfNeeded(currentPost: post) }
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .refreshable {
            await refreshFeed()
        }
    }

    private var loadingState: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterBar
                
                LazyVStack(spacing: 24) {
                    ForEach(0..<3, id: \.self) { _ in
                        ExplorePostCard.Skeleton()
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterBar
                
                EmptyStateView(
                    imageName: "nature-scene",
                    imageHeight: 300,
                    title: emptyStateTitle,
                    message: emptyStateMessage
                )
                .padding(.top, 60)
            }
        }
        .refreshable {
            await refreshFeed()
        }
    }

    private func errorState(message: String) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                filterBar
                
                ExploreUnavailableStateView(
                    title: "Explore unavailable",
                    message: message
                ) {
                    Task { await refreshFeed() }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 520)
            }
        }
        .refreshable {
            await refreshFeed()
        }
    }

    private var emptyStateTitle: String {
        switch viewModel.activeFilter {
        case .recent:
            return "Nothing shared yet"
        case .following:
            return "No followed discoveries yet"
        case .trending:
            return "Nothing trending yet"
        case .nearby:
            return "Nothing nearby yet"
        }
    }

    private var emptyStateMessage: String {
        switch viewModel.activeFilter {
        case .recent:
            return "Shared discoveries will show up here once people publish scans to Explore."
        case .following:
            return "Follow authors from their public profiles to build this feed."
        case .trending:
            return "Freshly liked discoveries will appear here as the community reacts."
        case .nearby:
            return "We couldn’t find shared discoveries within \(ExploreFeedFilter.nearbyRadiusMiles) miles of your current location."
        }
    }

    private func selectFilter(_ filter: ExploreFeedFilter) async {
        guard filter.requiresLocation else {
            await viewModel.selectFilter(filter)
            return
        }

        await activateNearbyFeedSelection()
    }

    private func refreshFeed() async {
        guard viewModel.activeFilter == .nearby else {
            await viewModel.refreshFeed()
            return
        }

        await activateNearbyFeedSelection(isRefresh: true)
    }

    @MainActor
    private func openPostEditor(for post: ExplorePost) async {
        guard post.isOwnedByViewer else { return }

        editingPostLocalFieldNotes = FieldNotesRepository.fieldNotes(
            for: post.scanId,
            modelContext: modelContext
        )

        do {
            editingPostDetail = try await MerianNetworkClient.shared.getExplorePostDetail(postId: post.id)
            let mediaPayload = try await MerianNetworkClient.shared.getExploreComposerMedia(postId: post.id)
            editingPostMediaItems = ExplorePostComposerMediaDraft.sourceItems(from: mediaPayload.mediaItems)
        } catch {
            editingPostDetail = nil
            editingPostMediaItems = ExplorePostComposerMediaDraft.existingPostItems(from: post.mediaItems ?? [])
            viewModel.toastMessage = ExploreErrorFormatter.message(for: error)
            return
        }

        HapticManager.shared.triggerSelectionPulse()
        editingPost = post
    }

    @MainActor
    private func saveEditedPost(_ draft: ExplorePostComposerDraft, for post: ExplorePost) async {
        guard post.isOwnedByViewer, !isSavingEditedPost else { return }

        isSavingEditedPost = true
        defer { isSavingEditedPost = false }

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
            updateLocalFieldNotes(draft.fieldNotes ?? "", for: post)
            editingPostDetail?.fieldNotes = response.fieldNotes
            editingPostDetail?.locationSharing = response.locationSharing ?? draft.locationSharing
            editingPost = nil
            await viewModel.refreshPost(postId: post.id)
            viewModel.refreshPreferredSpeciesNames(for: [post.speciesScientificName], modelContext: modelContext)
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

    @MainActor
    private func updateLocalFieldNotes(_ notes: String, for post: ExplorePost) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = FieldNotesRepository.setFieldNotes(
            notes,
            for: post.scanId,
            modelContext: modelContext
        )
        editingPostLocalFieldNotes = trimmed.isEmpty ? nil : notes
    }

    private func clearPostEditor() {
        editingPostDetail = nil
        editingPostMediaItems = []
        editingPostLocalFieldNotes = nil
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

    private func commonNameOptions(for post: ExplorePost, detail: ExplorePostDetail?) -> [String] {
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

    private func activateNearbyFeedSelection(isRefresh: Bool = false) async {
        guard !isResolvingNearbyLocation else { return }

        isResolvingNearbyLocation = true
        defer { isResolvingNearbyLocation = false }

        guard let location = await environmentContextManager.requestCurrentLocation() else {
            handleNearbyLocationFailure()
            return
        }

        if isRefresh {
            await viewModel.refreshFeed(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        } else {
            await viewModel.selectFilter(
                .nearby,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }
    }

    private func handleNearbyLocationFailure() {
        switch environmentContextManager.locationAuthorizationStatus {
        case .denied:
            isLocationSettingsAlertPresented = true
        case .restricted:
            viewModel.toastMessage = "Location access is restricted on this device."
        default:
            viewModel.toastMessage = "We couldn’t determine your location right now. Try again in a moment."
        }
    }

    private var filterBar: some View {
        CategoryFilterBar(
            items: ExploreFeedFilter.allCases,
            activeItem: viewModel.activeFilter,
            title: { $0.title },
            onSelection: { filter in
                Task {
                    await selectFilter(filter)
                }
            }
        )
        .disabled(isResolvingNearbyLocation)
        .overlay(alignment: .trailing) {
            if isResolvingNearbyLocation {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.85)
                    .padding(.trailing, 16)
            }
        }
    }
}

private struct ExploreRootModePicker: View {
    let activeTab: ExploreTab
    @Binding var activeDiscoveryMode: ExploreDiscoveryMode
    @Binding var activeDictionaryMode: ExploreDictionaryMode
    @Binding var activeCommunityMode: CommunityIdentificationMode
    @Binding var activeFieldTripsSection: FieldTripsSection

    var body: some View {
        picker
            .pickerStyle(.segmented)
            .padding(.bottom, 1)
            .background(Capsule().fill(.regularMaterial))
            .clipShape(Capsule())
            .frame(width: pickerWidth)
    }

    @ViewBuilder
    private var picker: some View {
        switch activeTab {
        case .feed:
            Picker("Observations view", selection: $activeDiscoveryMode) {
                Text("Feed").tag(ExploreDiscoveryMode.feed)
                Text("Map").tag(ExploreDiscoveryMode.map)
            }
        case .community:
            Picker("Identify view", selection: $activeCommunityMode) {
                ForEach(CommunityIdentificationMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        case .fieldTrips:
            Picker("Field Trips view", selection: $activeFieldTripsSection) {
                ForEach(FieldTripsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
        case .dictionary:
            Picker("Dictionary view", selection: $activeDictionaryMode) {
                Text("Catalog").tag(ExploreDictionaryMode.dictionary)
                Text("Tree").tag(ExploreDictionaryMode.tree)
            }
        }
    }

    private var pickerWidth: CGFloat {
        switch activeTab {
        case .community:
            240
        case .fieldTrips:
            240
        case .feed, .dictionary:
            220
        }
    }
}

struct ExplorePostRoute: Hashable {
    let postId: String
    let shouldFocusCommentComposer: Bool
    let shouldOpenInsight: Bool
    let targetCommentId: String?
    let targetReplyParentCommentId: String?
    let notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget?

    init(
        postId: String,
        shouldFocusCommentComposer: Bool,
        shouldOpenInsight: Bool,
        targetCommentId: String?,
        targetReplyParentCommentId: String?,
        notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget? = nil
    ) {
        self.postId = postId
        self.shouldFocusCommentComposer = shouldFocusCommentComposer
        self.shouldOpenInsight = shouldOpenInsight
        self.targetCommentId = targetCommentId
        self.targetReplyParentCommentId = targetReplyParentCommentId
        self.notificationReplyThreadTarget = notificationReplyThreadTarget
    }
}

struct ExploreNotificationReplyThreadTarget: Hashable {
    let parentCommentId: String?
    let targetReplyId: String
    let fallbackReply: ExploreNotificationReplyFallback
}

struct FieldTripPublicationRoute: Hashable {
    let publicationId: String
}

struct FieldTripTemplateRoute: Hashable {
    let templateId: String
}

struct FieldTripChallengeRoute: Hashable {
    let challengeId: String
}

struct FieldTripChallengeEntryRoute: Hashable {
    let entryId: String
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct ExploreHashtagRoute: Hashable {
    let hashtag: String
}

struct ExploreHashtagPostsView: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let route: ExploreHashtagRoute
    let allowsInsightPresentation: Bool
    let onOpenOwnedPostInsight: ((String) -> Bool)?
    var allowsAuthorProfilePresentation = true

    @Environment(\.modelContext) private var modelContext

    @State private var posts: [ExplorePost] = []
    @State private var cursor = ExploreHashtagPostCursor.empty
    @State private var isLoadingInitialPage = true
    @State private var isLoadingMore = false
    @State private var hasReachedEnd = false
    @State private var errorMessage: String?
    @State private var selectedPostRoute: ExplorePostRoute?

    private let pageSize = 30

    var body: some View {
        Group {
            if isLoadingInitialPage && posts.isEmpty {
                loadingState
            } else if let errorMessage, posts.isEmpty {
                errorState(message: errorMessage)
            } else if posts.isEmpty {
                emptyState
            } else {
                postsGrid
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("#\(route.hashtag)")
        .navigationDestination(
            isPresented: Binding(
                get: { selectedPostRoute != nil },
                set: { if !$0 { selectedPostRoute = nil } }
            )
        ) {
            if let selectedPostRoute {
                ExplorePostDetailView(
                    viewModel: viewModel,
                    postId: selectedPostRoute.postId,
                    shouldFocusCommentComposer: selectedPostRoute.shouldFocusCommentComposer,
                    shouldOpenInsight: selectedPostRoute.shouldOpenInsight,
                    targetCommentId: selectedPostRoute.targetCommentId,
                    targetReplyParentCommentId: selectedPostRoute.targetReplyParentCommentId,
                    allowsInsightPresentation: allowsInsightPresentation,
                    onOpenOwnedPostInsight: onOpenOwnedPostInsight,
                    allowsAuthorProfilePresentation: allowsAuthorProfilePresentation
                )
            }
        }
        .task(id: route.hashtag) {
            await reloadPosts()
        }
    }

    private var postsGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                spacing: 2
            ) {
                ForEach(posts) { post in
                    Button {
                        openPost(post)
                    } label: {
                        ExploreHeroImageView(
                            imageUrl: post.heroImageUrl,
                            reloadGeneration: viewModel.mediaReloadGeneration,
                            maxDimension: 360
                        )
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .overlay(alignment: .topLeading) {
                            if post.hasVideoMedia {
                                ExploreMediaPlayIndicator()
                                    .padding(6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(viewModel.resolvedSpeciesCommonName(for: post)), tagged #\(route.hashtag)")
                    .onAppear {
                        guard post.id == posts.last?.id else { return }
                        Task { await loadMorePostsIfNeeded() }
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)

            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
            }
        }
        .refreshable {
            await reloadPosts()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Loading tagged posts...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        EmptyStateView(
            iconName: "number",
            title: "No tagged posts",
            message: "Visible Explore posts tagged #\(route.hashtag) will appear here."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        ExploreUnavailableStateView(
            title: "Hashtag unavailable",
            message: message
        ) {
            Task { await reloadPosts() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func reloadPosts() async {
        posts = []
        cursor = .empty
        hasReachedEnd = false
        errorMessage = nil
        isLoadingInitialPage = true
        await loadMorePostsIfNeeded()
        isLoadingInitialPage = false
    }

    @MainActor
    private func loadMorePostsIfNeeded() async {
        guard !isLoadingMore, !hasReachedEnd else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await MerianNetworkClient.shared.getExploreHashtagPosts(
                hashtag: route.hashtag,
                limit: pageSize,
                cursor: cursor.isEmpty ? nil : cursor
            )
            guard !Task.isCancelled else { return }

            appendUniquePosts(page)
            registerPosts(page)

            if let lastPost = posts.last {
                cursor = ExploreHashtagPostCursor(
                    beforeSharedAt: lastPost.sharedAt,
                    beforePostId: lastPost.id
                )
            }

            hasReachedEnd = page.count < pageSize
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            if posts.isEmpty {
                errorMessage = ExploreErrorFormatter.message(for: error)
            } else {
                viewModel.toastMessage = ExploreErrorFormatter.message(for: error)
            }
        }
    }

    @MainActor
    private func appendUniquePosts(_ nextPosts: [ExplorePost]) {
        let existingIds = Set(posts.map(\.id))
        posts.append(contentsOf: nextPosts.filter { !existingIds.contains($0.id) })
    }

    @MainActor
    private func registerPosts(_ page: [ExplorePost]) {
        for post in page {
            viewModel.upsertPost(post)
        }
        viewModel.refreshPreferredSpeciesNames(
            for: page.map(\.speciesScientificName),
            modelContext: modelContext
        )
    }

    @MainActor
    private func openPost(_ post: ExplorePost) {
        viewModel.upsertPost(post)
        selectedPostRoute = ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: false,
            shouldOpenInsight: false,
            targetCommentId: nil,
            targetReplyParentCommentId: nil
        )
    }
}
