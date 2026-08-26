import SwiftData
import SwiftUI
import UIKit

enum ExploreTab: Hashable, CaseIterable {
    case feed
    case fieldTrips
    case community
}

enum ExploreInitialTabPolicy {
    static func resolve(
        requestedTab: ExploreTab,
        speciesDictionaryRoute: SpeciesDictionaryRoute?,
        communityRequestId: String? = nil
    ) -> ExploreTab {
        speciesDictionaryRoute == nil && communityRequestId == nil
            ? requestedTab
            : .community
    }
}

enum ExploreInitialIdentifyModePolicy {
    static func resolve(
        speciesDictionaryRoute: SpeciesDictionaryRoute?,
        communityRequestId: String?
    ) -> ExploreIdentifyMode {
        if speciesDictionaryRoute != nil {
            return .index
        }
        if communityRequestId != nil {
            return .requests
        }
        return .requests
    }
}

private enum ExploreDiscoveryMode: Hashable {
    case feed
    case map
}

private struct ExploreNotificationSessionKey: Hashable {
    let userID: UUID?
    let authTransitionInProgress: Bool
}

private enum ExploreNotificationDismissalDestination {
    case scansLibrary
    case communityRequest(String)
    case fieldTripPublication(String)
    case post(
        postId: String,
        focusCommentComposer: Bool,
        targetCommentId: String?,
        targetReplyParentCommentId: String?,
        replyThreadTarget: ExploreNotificationReplyThreadTarget?
    )
}

struct ExploreView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(AppSettings.self) private var appSettings
    @Environment(EnvironmentContextManager.self) private var environmentContextManager
    @Environment(SupabaseManager.self) private var supabase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ExploreFeedViewModel()
    @State private var mapViewModel = ExploreMapViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var selectedInsightRoute: ScanInsightRoute?
    @State private var pendingInsightCommunityRequestId: String?
    @State private var activeTab: ExploreTab = .feed
    @State private var activeDiscoveryMode: ExploreDiscoveryMode = .feed
    @State private var activeIdentifyMode: ExploreIdentifyMode = .requests
    @State private var activeFieldTripsSection: FieldTripsSection = .fieldTrips
    @State private var dictionaryUserRegionIdentifier = Self.defaultDictionaryUserRegionIdentifier()
    @State private var playbackCoordinator = ExploreVideoPlaybackCoordinator()
    @State private var pendingNotificationDestination:
        ExploreNotificationDismissalDestination?
    @State private var notificationOpenToken: UUID?

    private let allowsInsightPresentation: Bool
    private let onOpenOwnedPostInsight: ((String) -> Bool)?

    private var canOpenOwnedPostInsight: Bool {
        allowsInsightPresentation || onOpenOwnedPostInsight != nil
    }

    private var ownedPostInsightHandler: ((String) -> Bool)? {
        guard onOpenOwnedPostInsight != nil else { return nil }
        return { scanId in openOwnedPostInsightFromParent(scanId) }
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
        initialSpeciesDictionaryRoute: SpeciesDictionaryRoute? = nil,
        initialCommunityRequestId: String? = nil,
        initialTargetCommentId: String? = nil,
        initialTargetReplyParentCommentId: String? = nil,
        initialCaptureGoalDestination: CaptureGoalDestination? = nil,
        initialTab: ExploreTab = .feed,
        allowsInsightPresentation: Bool = true,
        onOpenOwnedPostInsight: ((String) -> Bool)? = nil
    ) {
        self.allowsInsightPresentation = allowsInsightPresentation
        self.onOpenOwnedPostInsight = onOpenOwnedPostInsight
        _activeTab = State(initialValue: ExploreInitialTabPolicy.resolve(
            requestedTab: initialTab,
            speciesDictionaryRoute: initialSpeciesDictionaryRoute,
            communityRequestId: initialCommunityRequestId
        ))
        _activeIdentifyMode = State(initialValue: ExploreInitialIdentifyModePolicy.resolve(
            speciesDictionaryRoute: initialSpeciesDictionaryRoute,
            communityRequestId: initialCommunityRequestId
        ))
        if initialTab == .fieldTrips {
            _activeFieldTripsSection = State(initialValue: .fieldTrips)
        }
        if let initialSpeciesDictionaryRoute {
            var initialPath = NavigationPath()
            initialPath.append(initialSpeciesDictionaryRoute)
            _navigationPath = State(initialValue: initialPath)
        } else if let initialCaptureGoalDestination {
            var initialPath = NavigationPath()
            switch initialCaptureGoalDestination {
            case .fieldTrip(let templateId, let checklistItemId):
                initialPath.append(FieldTripTemplateRoute(
                    templateId: templateId,
                    focusedChecklistItemId: checklistItemId
                ))
                _navigationPath = State(initialValue: initialPath)
                _activeTab = State(initialValue: .fieldTrips)
                _activeFieldTripsSection = State(initialValue: .fieldTrips)
            case .fieldTripTemplate(let slug):
                initialPath.append(FieldTripTemplateRoute(slug: slug))
                _navigationPath = State(initialValue: initialPath)
                _activeTab = State(initialValue: .fieldTrips)
                _activeFieldTripsSection = State(initialValue: .fieldTrips)
            case .fieldTripChallenge(let challengeId):
                initialPath.append(FieldTripChallengeRoute(challengeId: challengeId))
                _navigationPath = State(initialValue: initialPath)
                _activeTab = State(initialValue: .fieldTrips)
                _activeFieldTripsSection = State(initialValue: .seasonal)
            }
        } else if let requestId = initialCommunityRequestId {
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

                FieldTripsView(
                    userRegion: dictionaryUserRegionIdentifier,
                    selectedSection: $activeFieldTripsSection,
                    onOpenTemplate: { templateId in
                        navigationPath.append(FieldTripTemplateRoute(templateId: templateId))
                    },
                    onOpenCompletedScan: openFieldTripCompletedScan,
                    onOpenPublication: { publicationId in
                        navigationPath.append(FieldTripPublicationRoute(publicationId: publicationId))
                    },
                    onOpenAuthorProfile: openAuthorProfile
                )
                .tag(ExploreTab.fieldTrips)
                .tabItem {
                    Label("Field trips", systemImage: "map")
                }

                identifyTabContent
                .tag(ExploreTab.community)
                .tabItem {
                    Label("Identify", systemImage: "person.crop.badge.magnifyingglass.fill")
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
                    allowsAuthorProfilePresentation: ExploreAuthorProfileNavigationPolicy.canOpenProfile(
                        from: route.authorProfileDepth
                    ),
                    authorProfileDepth: route.authorProfileDepth,
                    onOpenAuthorProfile: { authorRoute in
                        appendAuthorProfileRoute(authorRoute, fromDepth: route.authorProfileDepth)
                    },
                    onOpenCommunityIdentificationRequest: openCommunityIdentificationRequest,
                    onOpenExploreMap: observationMapHandler(for: route)
                )
                .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: ExploreAuthorProfileRoute.self) { route in
                ExploreAuthorProfileContent(
                    viewModel: viewModel,
                    route: route,
                    presentation: .stack,
                    onClose: popExploreNavigation,
                    onOpenPostRoute: { route in
                        navigationPath.append(route)
                    },
                    onOpenPublication: { publicationId in
                        navigationPath.append(FieldTripPublicationRoute(publicationId: publicationId))
                    },
                    onOpenTemplate: { templateId in
                        navigationPath.append(FieldTripTemplateRoute(templateId: templateId))
                    }
                )
                .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: SpeciesDictionaryRoute.self) { route in
                SpeciesDictionaryPageContentView(
                    scientificName: route.scientificName,
                    speciesId: route.speciesId,
                    entryPoint: route.entryPoint,
                    showsCloseButton: false,
                    exploreViewModel: viewModel
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
                    if FeatureFlags.isEnabled(.speciesDictionaryTree) {
                        TaxonomyTreeCanvasView(showsNavigationTitle: true) { speciesRoute in
                            navigationPath.append(speciesRoute)
                        }
                        .toolbar(.hidden, for: .tabBar)
                        .toolbar {}
                    } else {
                        SpeciesDictionaryOverviewView(userRegion: dictionaryUserRegionIdentifier)
                            .toolbar(.hidden, for: .tabBar)
                            .toolbar {}
                    }
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
                    onOpenOwnedPostInsight: ownedPostInsightHandler,
                    authorProfileDepth: 0,
                    onOpenAuthorProfile: { route in
                        appendAuthorProfileRoute(route, fromDepth: 0)
                    }
                )
                .toolbar(.hidden, for: .tabBar)
                .toolbar {}
            }
            .navigationDestination(for: ExploreCommunityRequestRoute.self) { route in
                ExploreCommunityIdentificationDetailView(requestId: route.requestId)
                    .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: ExploreCommunityRequestsFeedRoute.self) { route in
                ExploreCommunityRequestsFeedView(
                    initialFilter: route.filter,
                    onOpenRequest: { navigationPath.append($0) }
                )
                .toolbar(.hidden, for: .tabBar)
                .toolbar {}
            }
            .navigationDestination(for: ExploreCommunityActivityFeedRoute.self) { route in
                ExploreCommunityActivityFeedView(
                    initialFilter: route.filter,
                    onOpenRequest: { navigationPath.append($0) }
                )
                .toolbar(.hidden, for: .tabBar)
                .toolbar {}
            }
            .navigationDestination(for: FieldTripTemplateRoute.self) { route in
                FieldTripTemplateDetailView(
                    reference: route.reference,
                    focusedChecklistItemId: route.focusedChecklistItemId,
                    onOpenCompletedScan: openFieldTripCompletedScan,
                    onOpenPublication: { publicationId in
                        navigationPath.append(FieldTripPublicationRoute(publicationId: publicationId))
                    },
                    onOpenAuthorProfile: openAuthorProfile
                )
                .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: ScanInsightRoute.self) { route in
                LocalScanInsightLoader(scanId: route.scanId) {
                    InsightSheetView(
                        isPresented: Binding(
                            get: { true },
                            set: { isPresented in
                                if !isPresented, !navigationPath.isEmpty {
                                    navigationPath.removeLast()
                                }
                            }
                        ),
                        initialScanId: route.scanId,
                        inferenceEngine: inferenceEngine,
                        allowsExplorePresentation: false,
                        presentationStyle: .embeddedInScansLibrary,
                        onOpenFieldTripOverview: openFieldTripOverviewDestination
                    )
                }
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
        .onChange(of: activeIdentifyMode) { _, _ in
            HapticManager.shared.triggerSelectionPulse()
        }
        .task(id: activeIdentifyMode) {
            guard activeTab == .community, activeIdentifyMode == .index else { return }
            await refreshDictionaryUserRegionFromAuthorizedLocation()
        }
        .task(id: activeTab) {
            guard activeTab == .community, activeIdentifyMode == .index else { return }
            await refreshDictionaryUserRegionFromAuthorizedLocation()
        }
        .task(id: ExploreNotificationSessionKey(
            userID: supabase.currentUser?.id,
            authTransitionInProgress: supabase.isAuthTransitionInProgress
        )) {
            viewModel.stopUnreadNotificationUpdates()
            guard supabase.allowsUnownedAccountBoundWork else { return }
            await viewModel.startUnreadNotificationUpdates()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
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
            Group {
                if let post = viewModel.activeCommentsPost {
                    ExploreCommentsSheet(viewModel: viewModel, post: post)
                }
            }
            .exploreVideoPresentedOverlayLifecycle(reason: "explore-root-comments-sheet")
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isNotificationsSheetPresented },
                set: { if !$0 { viewModel.dismissNotifications() } }
            ),
            onDismiss: {
                notificationOpenToken = nil
                resumePendingNotificationDestination()
                Task { await viewModel.refreshUnreadNotificationCount(force: true) }
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
            .exploreVideoPresentedOverlayLifecycle(reason: "explore-root-notifications-sheet")
        }
        .sheet(
            item: $selectedInsightRoute,
            onDismiss: {
                viewModel.refreshPreferredSpeciesNames(modelContext: modelContext)
                resumePendingInsightCommunityRequest()
            }
        ) { route in
            LocalScanInsightLoader(scanId: route.scanId) {
                InsightSheetView(
                    isPresented: Binding(
                        get: { selectedInsightRoute != nil },
                        set: { if !$0 { selectedInsightRoute = nil } }
                    ),
                    initialScanId: route.scanId,
                    inferenceEngine: inferenceEngine,
                    allowsExplorePresentation: false,
                    onOpenCommunityIdentificationRequest: { requestId in
                        pendingInsightCommunityRequestId = requestId
                        selectedInsightRoute = nil
                    }
                )
            }
            .exploreVideoPresentedOverlayLifecycle(reason: "explore-root-insight-sheet")
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.refreshUnreadNotificationCount() }
        }
        .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
            switch event {
            case .explorePostNeedsRefresh(let postId):
                Task { await viewModel.refreshPost(postId: postId) }
            case .publicAuthorIdentityChanged:
                Task {
                    await viewModel.refreshFeed()
                    mapViewModel.syncPosts(from: viewModel.store.allPosts)
                }
            default:
                break
            }
        }
        .merianSystemFeedback(
            toast: Binding(
                get: { viewModel.toastMessage },
                set: { viewModel.toastMessage = $0 }
            ),
            toastAlignment: .top
        )
    }

    @MainActor
    private func openCaptureGoalDestination(_ destination: CaptureGoalDestination) {
        var nextPath = NavigationPath()
        activeTab = .fieldTrips

        switch destination {
        case .fieldTrip(let templateId, let checklistItemId):
            activeFieldTripsSection = .fieldTrips
            nextPath.append(FieldTripTemplateRoute(
                templateId: templateId,
                focusedChecklistItemId: checklistItemId
            ))
        case .fieldTripTemplate(let slug):
            activeFieldTripsSection = .fieldTrips
            nextPath.append(FieldTripTemplateRoute(slug: slug))
        case .fieldTripChallenge(let challengeId):
            activeFieldTripsSection = .seasonal
            nextPath.append(FieldTripChallengeRoute(challengeId: challengeId))
        }

        navigationPath = nextPath
    }

    /// Keeps an embedded Insight underneath the Field trip detail so Back returns
    /// to the scan. The card route intentionally opens the Goals overview without
    /// carrying Capture's focused checklist item into the destination.
    @MainActor
    private func openFieldTripOverviewDestination(
        _ destination: InsightFieldTripOverviewDestination
    ) {
        activeTab = .fieldTrips

        switch destination {
        case .standardOuting(let templateId):
            activeFieldTripsSection = .fieldTrips
            navigationPath.append(FieldTripTemplateRoute(templateId: templateId))
        case .event(let challengeId):
            activeFieldTripsSection = .seasonal
            navigationPath.append(FieldTripChallengeRoute(challengeId: challengeId))
        }
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
            .accessibilityLabel("Close Explore")
            .accessibilityIdentifier("ExploreCloseButton")
        }

        if shouldShowRootModePicker {
            ToolbarItem(placement: .principal) {
                ExploreRootModePicker(
                    activeTab: activeTab,
                    activeDiscoveryMode: $activeDiscoveryMode,
                    activeIdentifyMode: $activeIdentifyMode,
                    activeFieldTripsSection: $activeFieldTripsSection
                )
            }
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
                onOpenPostDetail: { openPostDetail(for: $0, origin: .feed) },
                onOpenFieldTrip: { navigationPath.append(FieldTripPublicationRoute(publicationId: $0.publicationId)) },
                onOpenAuthorProfile: { openAuthorProfile(for: $0) },
                onOpenFieldTripAuthorProfile: openAuthorProfile,
                onOpenHashtag: openHashtag,
                onOpenInsight: canOpenOwnedPostInsight ? { openInsight(for: $0) } : nil
            )
        case .map:
            ExploreMapView(
                viewModel: mapViewModel,
                feedViewModel: viewModel,
                postStore: viewModel.store,
                onOpenDetail: { post, focusCommentComposer in
                    openPostDetail(
                        for: post,
                        focusCommentComposer: focusCommentComposer,
                        origin: .map
                    )
                }
            )
        }
    }

    @ViewBuilder
    private var identifyTabContent: some View {
        Group {
            switch activeIdentifyMode {
            case .requests:
                ExploreCommunityIdentificationView(
                    onOpenRequest: { navigationPath.append($0) },
                    onOpenRequestsFeed: { navigationPath.append($0) },
                    onOpenActivityFeed: { navigationPath.append($0) }
                )
            case .index:
                SpeciesDictionaryOverviewView(userRegion: dictionaryUserRegionIdentifier)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
        notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget? = nil,
        origin: ExplorePostDetailOrigin = .other
    ) {
        viewModel.upsertPost(post)
        viewModel.refreshPreferredSpeciesNames(for: [post.speciesScientificName], modelContext: modelContext)
        navigationPath.append(ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: focusCommentComposer,
            shouldOpenInsight: canOpenOwnedPostInsight && openInsight,
            targetCommentId: targetCommentId,
            targetReplyParentCommentId: targetReplyParentCommentId,
            notificationReplyThreadTarget: notificationReplyThreadTarget,
            origin: origin
        ))
    }

    private func observationMapHandler(
        for route: ExplorePostRoute
    ) -> ((ExploreMapFocusTarget) -> Void)? {
        guard route.allowsObservationMapNavigation else { return nil }
        return { target in
            openExploreMap(target)
        }
    }

    private func openExploreMap(_ target: ExploreMapFocusTarget) {
        mapViewModel.focus(on: target)
        navigationPath = NavigationPath()
        activeTab = .feed
        activeDiscoveryMode = .map

        Task {
            await mapViewModel.refreshFocusedArea()
        }
    }

    private func openAuthorProfile(for post: ExplorePost) {
        HapticManager.shared.triggerSelectionPulse()
        viewModel.upsertPost(post)
        appendAuthorProfileRoute(ExploreAuthorProfileRoute(post: post), fromDepth: 0)
    }

    private func openAuthorProfile(for publication: FieldTripRecentPublication) {
        HapticManager.shared.triggerSelectionPulse()
        appendAuthorProfileRoute(ExploreAuthorProfileRoute(
            authorUserId: publication.authorUserId,
            authorName: publication.authorName,
            authorUsername: publication.authorUsername,
            authorAvatarUrl: publication.authorAvatarUrl
        ), fromDepth: 0)
    }

    private func openAuthorProfile(for entry: FieldTripChallengeEntry) {
        HapticManager.shared.triggerSelectionPulse()
        appendAuthorProfileRoute(ExploreAuthorProfileRoute(
            authorUserId: entry.authorUserId,
            authorName: entry.authorName,
            authorUsername: entry.authorUsername,
            authorAvatarUrl: entry.authorAvatarUrl
        ), fromDepth: 0)
    }

    private func appendAuthorProfileRoute(_ route: ExploreAuthorProfileRoute, fromDepth currentDepth: Int) {
        guard ExploreAuthorProfileNavigationPolicy.canOpenProfile(from: currentDepth) else {
            HapticManager.shared.triggerLightImpact(intensity: 0.35)
            return
        }

        navigationPath.append(
            route.withNavigationDepth(
                ExploreAuthorProfileNavigationPolicy.nextProfileDepth(from: currentDepth)
            )
        )
    }

    private func popExploreNavigation() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }

    private func openHashtag(_ hashtag: String) {
        HapticManager.shared.triggerSelectionPulse()
        navigationPath.append(ExploreHashtagRoute(hashtag: hashtag))
    }

    private func openCommunityIdentificationRequest(_ requestId: String) {
        var requestPath = NavigationPath()
        requestPath.append(ExploreCommunityRequestRoute(requestId: requestId))
        activeTab = .community
        activeIdentifyMode = .requests
        navigationPath = requestPath
    }

    private func resumePendingInsightCommunityRequest() {
        guard let requestId = pendingInsightCommunityRequestId else { return }
        pendingInsightCommunityRequestId = nil
        openCommunityIdentificationRequest(requestId)
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
                viewModel.toastMessage = .warning("This scan is not available on this device.")
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
            viewModel.toastMessage = .warning("This scan is not available on this device.")
            return
        }

        HapticManager.shared.triggerSelectionPulse()
        selectedInsightRoute = ScanInsightRoute(scanId: record.id)
    }

    private func openFieldTripCompletedScan(_ scanId: String) {
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )

        guard let record = try? modelContext.fetch(descriptor).first else {
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = .warning("This scan is not available on this device.")
            return
        }

        HapticManager.shared.triggerSelectionPulse()
        navigationPath.append(ScanInsightRoute(scanId: record.id))
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
        guard viewModel.isNotificationsSheetPresented else { return }
        let openToken = UUID()
        notificationOpenToken = openToken

        if notification.type == .mediaMissing {
            stageNotificationDestination(.scansLibrary)
            return
        }

        if notification.type.isCommunityNotification,
           let requestId = notification.communityRequestId {
            stageNotificationDestination(.communityRequest(requestId))
            return
        }

        if notification.type.isFieldTripNotification,
           let publicationId = notification.fieldTripPublicationId {
            guard FeatureFlags.isEnabled(.fieldTrips) else { return }
            stageNotificationDestination(.fieldTripPublication(publicationId))
            return
        }

        guard let postId = notification.postId else { return }

        do {
            let post = try await viewModel.preparePostForNavigation(postId: postId)
            guard notificationOpenToken == openToken,
                  viewModel.isNotificationsSheetPresented else { return }
            let targetReplyParentCommentId = notification.parentCommentId
                ?? (notification.type == .commentReply ? notification.commentId : nil)
            let targetCommentId = targetReplyParentCommentId == notification.commentId
                ? nil
                : notification.commentId

            if notification.type == .commentReply,
               let targetReplyId = notification.commentId {
                stageNotificationDestination(
                    .post(
                        postId: post.id,
                        focusCommentComposer: false,
                        targetCommentId: nil,
                        targetReplyParentCommentId: nil,
                        replyThreadTarget: ExploreNotificationReplyThreadTarget(
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
                )
                return
            }

            stageNotificationDestination(
                .post(
                    postId: post.id,
                    focusCommentComposer: notification.type == .comment && targetCommentId == nil,
                    targetCommentId: targetCommentId ?? targetReplyParentCommentId,
                    targetReplyParentCommentId: targetReplyParentCommentId,
                    replyThreadTarget: nil
                )
            )
        } catch {
            guard notificationOpenToken == openToken,
                  viewModel.isNotificationsSheetPresented else { return }
            MerianLog.network.error(
                "Failed to open Explore notification \(notification.id, privacy: .private): \(error.localizedDescription, privacy: .private)"
            )
            AppTelemetry.trackExploreNotificationOpenFailed(type: notification.type.rawValue)
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = .error(ExploreErrorFormatter.message(for: error))
            viewModel.dismissNotifications()
        }
    }

    private func stageNotificationDestination(
        _ destination: ExploreNotificationDismissalDestination
    ) {
        guard viewModel.isNotificationsSheetPresented else { return }
        pendingNotificationDestination = destination
        viewModel.dismissNotifications()
    }

    private func resumePendingNotificationDestination() {
        guard let destination = pendingNotificationDestination else { return }
        pendingNotificationDestination = nil

        switch destination {
        case .scansLibrary:
            AppDIContainer.shared.appRouteCoordinator.request(
                .scansLibrary,
                source: .internalUserAction
            )
        case .communityRequest(let requestId):
            openCommunityIdentificationRequest(requestId)
        case .fieldTripPublication(let publicationId):
            activeTab = .fieldTrips
            navigationPath.append(FieldTripPublicationRoute(publicationId: publicationId))
        case let .post(
            postId,
            focusCommentComposer,
            targetCommentId,
            targetReplyParentCommentId,
            replyThreadTarget
        ):
            guard let post = viewModel.post(id: postId) else {
                HapticManager.shared.triggerErrorThump()
                viewModel.toastMessage = .error("This Explore post is no longer available.")
                return
            }
            if let targetReplyParentCommentId {
                viewModel.prepareToExpandReplyThread(
                    parentCommentId: targetReplyParentCommentId
                )
            }
            openPostDetail(
                for: post,
                focusCommentComposer: focusCommentComposer,
                targetCommentId: targetCommentId,
                targetReplyParentCommentId: targetReplyParentCommentId,
                notificationReplyThreadTarget: replyThreadTarget
            )
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
    @Environment(SupabaseManager.self) private var supabase
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var isLocationSettingsAlertPresented = false
    @State private var isResolvingNearbyLocation = false
    @State private var isShowingFilterSheet = false
    @State private var editingPost: ExplorePost?
    @State private var editingPostDetail: ExplorePostDetail?
    @State private var editingPostMediaItems: [ExplorePostComposerMediaDraft] = []
    @State private var editingPostLocalFieldNotes: String?
    @State private var isSavingEditedPost = false
    let onOpenPostDetail: (ExplorePost) -> Void
    let onOpenFieldTrip: (FieldTripRecentPublication) -> Void
    let onOpenAuthorProfile: (ExplorePost) -> Void
    let onOpenFieldTripAuthorProfile: (FieldTripRecentPublication) -> Void
    let onOpenHashtag: (String) -> Void
    let onOpenInsight: ((ExplorePost) -> Void)?

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            feedScrollView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .alert("Turn On Location", isPresented: $isLocationSettingsAlertPresented) {
            Button("Not Now", role: .cancel) {}
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    openURL(settingsURL)
                }
            }
        } message: {
            Text("Nearby uses your current location to show discoveries shared within \(viewModel.advancedFilters.nearbyRadius.rawValue) miles.")
        }
        .sheet(isPresented: $isShowingFilterSheet) {
            feedFilterSheet
                .exploreVideoPresentedOverlayLifecycle(reason: "explore-feed-filter-sheet")
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
            .exploreVideoPresentedOverlayLifecycle(reason: "explore-feed-edit-post-sheet")
        }
    }

    private var feedScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterBar

                if viewModel.isLoadingInitialFeed && viewModel.feedItems.isEmpty {
                    loadingState
                } else if let errorMessage = viewModel.errorMessage, viewModel.feedItems.isEmpty {
                    errorState(message: errorMessage)
                } else if viewModel.feedItems.isEmpty {
                    emptyState
                } else {
                    feedItems
                }
            }
        }
        .refreshable {
            await refreshFeed()
        }
        .onAppear {
            ExploreVideoMutePreference.resetToMuted()
        }
    }

    private var feedItems: some View {
        LazyVStack(spacing: 16) {
            ForEach(viewModel.feedItems) { item in
                switch item {
                case .observation(let post):
                    ExplorePostCard(
                        post: post,
                        speciesDisplayName: viewModel.resolvedSpeciesCommonName(for: post),
                        mediaReloadGeneration: viewModel.mediaReloadGeneration,
                        authorPresentation: postCardAuthorPresentation(for: post),
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
                case .fieldTrip(let publication):
                    FieldTripCommunityPublicationCard(
                        publication: publication,
                        onOpenPublication: { _ in onOpenFieldTrip(publication) },
                        onOpenAuthorProfile: onOpenFieldTripAuthorProfile
                    )
                    .padding(.horizontal, 16)
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

    private func postCardAuthorPresentation(
        for post: ExplorePost
    ) -> ExplorePostCardAuthorPresentation {
        ExplorePostCardAuthorPresentation.resolve(
            authorAvatarURL: post.authorAvatarUrl,
            authorUserID: post.authorUserId,
            authorIsPro: post.authorIsPro,
            isOwnedByViewer: post.isOwnedByViewer,
            viewer: ExplorePostCardViewerContext(
                userID: supabase.currentUser?.id.uuidString,
                avatarURL: supabase.currentUserAvatarUrl,
                isSubscribed: revenueCatManager.isSubscribed
            )
        )
    }

    private var loadingState: some View {
        LazyVStack(spacing: 24) {
            ForEach(0..<3, id: \.self) { _ in
                ExplorePostCard.Skeleton()
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var emptyState: some View {
        EmptyStateView(
            imageName: "nature-scene",
            imageHeight: 300,
            title: emptyStateTitle,
            message: emptyStateMessage
        )
        .padding(.top, 60)
    }

    private func errorState(message: String) -> some View {
        ExploreUnavailableStateView(
            title: "Explore unavailable",
            message: message
        ) {
            Task { await refreshFeed() }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 520)
    }

    private var emptyStateTitle: String {
        if viewModel.hasActiveAdvancedFilters {
            return "No matching discoveries"
        }

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
        if viewModel.hasActiveAdvancedFilters {
            return "Try removing one or more filters to broaden the feed."
        }

        switch viewModel.activeFilter {
        case .recent:
            return "Shared discoveries will show up here once people publish scans to Explore."
        case .following:
            return "Follow authors from their public profiles to build this feed."
        case .trending:
            return "Freshly liked discoveries will appear here as the community reacts."
        case .nearby:
            return "We couldn’t find shared discoveries within \(viewModel.advancedFilters.nearbyRadius.rawValue) miles of your current location."
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
            viewModel.toastMessage = .error(ExploreErrorFormatter.message(for: error))
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
            viewModel.toastMessage = .success("Explore post updated")
        } catch {
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = .error(ExploreErrorFormatter.message(for: error))
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
            viewModel.toastMessage = .warning("Location access is restricted on this device.")
        default:
            viewModel.toastMessage = .error(
                "We couldn’t determine your location right now. Try again in a moment."
            )
        }
    }

    private var filterBar: some View {
        CategoryFilterBar(
            items: ExploreFeedFilter.allCases,
            activeItem: viewModel.activeFilter,
            title: { $0.title },
            leadingTitle: viewModel.hasActiveAdvancedFilters
                ? "Filters \(viewModel.activeAdvancedFilterCount.formatted())"
                : "Filters",
            leadingSystemImage: "line.3.horizontal.decrease",
            isLeadingSelected: viewModel.hasActiveAdvancedFilters,
            loadingItem: isResolvingNearbyLocation ? .nearby : nil,
            onSelection: { filter in
                Task {
                    await selectFilter(filter)
                }
            },
            onLeadingSelection: {
                HapticManager.shared.triggerSelectionPulse()
                isShowingFilterSheet = true
            }
        )
        .disabled(isResolvingNearbyLocation)
    }

    private var feedFilterSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    filterSectionTitle("Feed")

                    ForEach(ExploreFeedFilter.allCases) { filter in
                        Button {
                            HapticManager.shared.triggerSelectionPulse()
                            Task { await selectFilter(filter) }
                        } label: {
                            FilterSheetSelectionRow(
                                title: filter.title,
                                subtitle: feedFilterSubtitle(filter),
                                systemImage: feedFilterSymbol(filter),
                                isSelected: viewModel.activeFilter == filter
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isResolvingNearbyLocation)
                    }

                    filterSectionTitle("Media type")
                        .padding(.top, 8)

                    Button {
                        updateMediaTypes([])
                    } label: {
                        FilterSheetSelectionRow(
                            title: "All media",
                            subtitle: "Show every media type",
                            systemImage: "rectangle.stack",
                            isSelected: viewModel.advancedFilters.mediaTypes.isEmpty
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(ExploreMediaKind.feedFilterCases) { mediaType in
                        Button {
                            toggleMediaType(mediaType)
                        } label: {
                            FilterSheetSelectionRow(
                                title: mediaType.filterTitle,
                                subtitle: "Show posts containing \(mediaType.filterTitle.lowercased())",
                                systemImage: mediaType.filterSymbolName,
                                isSelected: viewModel.advancedFilters.mediaTypes.contains(mediaType)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    filterSectionTitle("Date shared")
                        .padding(.top, 8)

                    ForEach(ExploreFeedDateRange.allCases) { dateRange in
                        Button {
                            updateDateRange(dateRange)
                        } label: {
                            FilterSheetSelectionRow(
                                title: dateRange.title,
                                subtitle: dateRange.subtitle,
                                systemImage: "calendar",
                                isSelected: viewModel.advancedFilters.dateRange == dateRange
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if viewModel.activeFilter == .nearby {
                        filterSectionTitle("Distance")
                            .padding(.top, 8)

                        ForEach(ExploreFeedNearbyRadius.allCases) { radius in
                            Button {
                                updateNearbyRadius(radius)
                            } label: {
                                FilterSheetSelectionRow(
                                    title: radius.title,
                                    subtitle: "Search within \(radius.rawValue) miles of your current location",
                                    systemImage: "location.circle",
                                    isSelected: viewModel.advancedFilters.nearbyRadius == radius
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    filterSectionTitle("Species")
                        .padding(.top, 8)

                    Button {
                        updateSpeciesCategories([])
                    } label: {
                        FilterSheetSelectionRow(
                            title: "All species",
                            subtitle: "Show every species group",
                            systemImage: "map",
                            isSelected: viewModel.advancedFilters.speciesCategories.isEmpty
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(ExploreMapSpeciesCategory.defaultFilters) { category in
                        Button {
                            toggleSpeciesCategory(category)
                        } label: {
                            FilterSheetSelectionRow(
                                title: category.title,
                                subtitle: "Show discoveries in this species group",
                                systemImage: category.symbolName,
                                isSelected: viewModel.advancedFilters.speciesCategories.contains(category)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Feed filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        HapticManager.shared.triggerSelectionPulse()
                        Task { await viewModel.resetAdvancedFilters() }
                    }
                    .disabled(!viewModel.hasStoredAdvancedFilters)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        HapticManager.shared.triggerSelectionPulse()
                        isShowingFilterSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    private func filterSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func feedFilterSubtitle(_ filter: ExploreFeedFilter) -> String {
        switch filter {
        case .recent: "Newest discoveries first"
        case .following: "Discoveries from people you follow"
        case .trending: "Discoveries getting attention now"
        case .nearby: "Discoveries near your current location"
        }
    }

    private func feedFilterSymbol(_ filter: ExploreFeedFilter) -> String {
        switch filter {
        case .recent: "clock.arrow.circlepath"
        case .following: "person.2"
        case .trending: "flame"
        case .nearby: "location"
        }
    }

    private func updateSpeciesCategories(_ categories: Set<ExploreMapSpeciesCategory>) {
        var filters = viewModel.advancedFilters
        filters.speciesCategories = categories
        applyAdvancedFilters(filters)
    }

    private func toggleSpeciesCategory(_ category: ExploreMapSpeciesCategory) {
        var categories = viewModel.advancedFilters.speciesCategories
        if categories.contains(category) {
            categories.remove(category)
        } else {
            categories.insert(category)
        }
        updateSpeciesCategories(categories)
    }

    private func updateMediaTypes(_ mediaTypes: Set<ExploreMediaKind>) {
        var filters = viewModel.advancedFilters
        filters.mediaTypes = mediaTypes
        applyAdvancedFilters(filters)
    }

    private func toggleMediaType(_ mediaType: ExploreMediaKind) {
        var mediaTypes = viewModel.advancedFilters.mediaTypes
        if mediaTypes.contains(mediaType) {
            mediaTypes.remove(mediaType)
        } else {
            mediaTypes.insert(mediaType)
        }
        updateMediaTypes(mediaTypes)
    }

    private func updateDateRange(_ dateRange: ExploreFeedDateRange) {
        var filters = viewModel.advancedFilters
        filters.dateRange = dateRange
        applyAdvancedFilters(filters)
    }

    private func updateNearbyRadius(_ radius: ExploreFeedNearbyRadius) {
        var filters = viewModel.advancedFilters
        filters.nearbyRadius = radius
        applyAdvancedFilters(filters)
    }

    private func applyAdvancedFilters(_ filters: ExploreFeedAdvancedFilters) {
        HapticManager.shared.triggerSelectionPulse()
        Task { await viewModel.applyAdvancedFilters(filters) }
    }
}

private struct ExploreRootModePicker: View {
    let activeTab: ExploreTab
    @Binding var activeDiscoveryMode: ExploreDiscoveryMode
    @Binding var activeIdentifyMode: ExploreIdentifyMode
    @Binding var activeFieldTripsSection: FieldTripsSection

    @ViewBuilder
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
            Picker("Identify view", selection: $activeIdentifyMode) {
                ForEach(ExploreIdentifyMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        case .fieldTrips:
            Picker("Field trips view", selection: $activeFieldTripsSection) {
                ForEach(FieldTripsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
        }
    }

    private var pickerWidth: CGFloat {
        switch activeTab {
        case .community:
            240
        case .fieldTrips:
            240
        case .feed:
            220
        }
    }
}

enum ExplorePostDetailOrigin: Hashable {
    case feed
    case map
    case other

    var allowsObservationMapNavigation: Bool {
        self == .feed
    }
}

struct ExplorePostRoute: Hashable {
    let postId: String
    let shouldFocusCommentComposer: Bool
    let shouldOpenInsight: Bool
    let targetCommentId: String?
    let targetReplyParentCommentId: String?
    let notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget?
    let authorProfileDepth: Int
    let origin: ExplorePostDetailOrigin

    var allowsObservationMapNavigation: Bool {
        origin.allowsObservationMapNavigation
    }

    init(
        postId: String,
        shouldFocusCommentComposer: Bool,
        shouldOpenInsight: Bool,
        targetCommentId: String?,
        targetReplyParentCommentId: String?,
        notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget? = nil,
        authorProfileDepth: Int = 0,
        origin: ExplorePostDetailOrigin = .other
    ) {
        self.postId = postId
        self.shouldFocusCommentComposer = shouldFocusCommentComposer
        self.shouldOpenInsight = shouldOpenInsight
        self.targetCommentId = targetCommentId
        self.targetReplyParentCommentId = targetReplyParentCommentId
        self.notificationReplyThreadTarget = notificationReplyThreadTarget
        self.authorProfileDepth = authorProfileDepth
        self.origin = origin
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

enum FieldTripTemplateReference: Hashable {
    case id(String)
    case slug(String)
}

struct FieldTripTemplateRoute: Hashable {
    let reference: FieldTripTemplateReference
    let focusedChecklistItemId: String?

    init(templateId: String, focusedChecklistItemId: String? = nil) {
        reference = .id(templateId)
        self.focusedChecklistItemId = focusedChecklistItemId
    }

    init(slug: String, focusedChecklistItemId: String? = nil) {
        reference = .slug(slug)
        self.focusedChecklistItemId = focusedChecklistItemId
    }
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
    var authorProfileDepth = 0
    var onOpenAuthorProfile: ((ExploreAuthorProfileRoute) -> Void)?

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
                    allowsAuthorProfilePresentation: allowsAuthorProfilePresentation &&
                        ExploreAuthorProfileNavigationPolicy.canOpenProfile(from: selectedPostRoute.authorProfileDepth),
                    authorProfileDepth: selectedPostRoute.authorProfileDepth,
                    onOpenAuthorProfile: onOpenAuthorProfile
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
                            imageUrl: post.gridThumbnailUrl,
                            reloadGeneration: viewModel.mediaReloadGeneration,
                            maxDimension: 360
                        )
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .overlay(alignment: .bottomTrailing) {
                            if post.hasVideoMedia || post.hasAudioMedia {
                                ExploreMediaTypeIndicator(kind: post.hasVideoMedia ? .video : .audio)
                                    .padding(8)
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
                viewModel.toastMessage = .error(ExploreErrorFormatter.message(for: error))
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
            targetReplyParentCommentId: nil,
            authorProfileDepth: authorProfileDepth
        )
    }
}
