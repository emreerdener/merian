import SwiftData
import SwiftUI

struct ExploreShellNavigationView: View {
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(SupabaseManager.self) private var supabase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var navigationPath: NavigationPath
    @Binding var selectedInsightRoute: ScanInsightRoute?
    @Binding var activeTab: ExploreTab
    @Binding var activeDiscoveryMode: ExploreDiscoveryMode
    @Binding var activeIdentifyMode: ExploreIdentifyMode
    @Binding var activeFieldTripsSection: FieldTripsSection

    let feedViewModel: ExploreFeedViewModel
    let mapViewModel: ExploreMapViewModel
    let dictionaryUserRegionIdentifier: String?
    let allowsInsightPresentation: Bool
    let onOpenOwnedPostInsight: ((String) -> Bool)?
    let dependencies: ExploreShellDependencies
    let onOpenPost: (ExplorePostNavigationRequest) -> Void
    let onOpenCommunityIdentificationRequest: (String) -> Void

    private var canOpenOwnedPostInsight: Bool {
        allowsInsightPresentation || onOpenOwnedPostInsight != nil
    }

    private var ownedPostInsightHandler: ((String) -> Bool)? {
        guard onOpenOwnedPostInsight != nil else { return nil }
        return { scanId in openOwnedPostInsightFromParent(scanId) }
    }

    private var tabSelection: Binding<ExploreTab> {
        Binding(
            get: { activeTab },
            set: { newValue in
                guard newValue != activeTab else { return }
                dependencies.triggerSelectionFeedback()
                activeTab = newValue
            }
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            TabView(selection: tabSelection) {
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
                        navigationPath.append(
                            FieldTripPublicationRoute(publicationId: publicationId)
                        )
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
                    viewModel: feedViewModel,
                    postId: route.postId,
                    shouldFocusCommentComposer: route.shouldFocusCommentComposer,
                    shouldOpenInsight: route.shouldOpenInsight,
                    targetCommentId: route.targetCommentId,
                    targetReplyParentCommentId: route.targetReplyParentCommentId,
                    notificationReplyThreadTarget: route.notificationReplyThreadTarget,
                    allowsInsightPresentation: allowsInsightPresentation,
                    onOpenOwnedPostInsight: ownedPostInsightHandler,
                    allowsAuthorProfilePresentation: ExploreAuthorProfileNavigationPolicy
                        .canOpenProfile(from: route.authorProfileDepth),
                    authorProfileDepth: route.authorProfileDepth,
                    onOpenAuthorProfile: { authorRoute in
                        appendAuthorProfileRoute(
                            authorRoute,
                            fromDepth: route.authorProfileDepth
                        )
                    },
                    onOpenCommunityIdentificationRequest: onOpenCommunityIdentificationRequest,
                    onOpenExploreMap: observationMapHandler(for: route)
                )
                .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: ExploreAuthorProfileRoute.self) { route in
                ExploreAuthorProfileContent(
                    viewModel: feedViewModel,
                    route: route,
                    presentation: .stack,
                    onClose: popExploreNavigation,
                    onOpenPostRoute: { navigationPath.append($0) },
                    onOpenPublication: { publicationId in
                        navigationPath.append(
                            FieldTripPublicationRoute(publicationId: publicationId)
                        )
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
                    exploreViewModel: feedViewModel
                )
                .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: SpeciesDictionaryCategoryRoute.self) { route in
                speciesDictionaryCategoryDestination(route)
            }
            .navigationDestination(for: ExploreHashtagRoute.self) { route in
                ExploreHashtagPostsView(
                    viewModel: feedViewModel,
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
                        navigationPath.append(
                            FieldTripPublicationRoute(publicationId: publicationId)
                        )
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
    }

    @ViewBuilder
    private func speciesDictionaryCategoryDestination(
        _ route: SpeciesDictionaryCategoryRoute
    ) -> some View {
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
        case .regions:
            SpeciesDictionaryRegionsView(userRegion: dictionaryUserRegionIdentifier)
                .toolbar(.hidden, for: .tabBar)
                .toolbar {}
        }
    }

    @ToolbarContentBuilder
    private var exploreToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dependencies.triggerLightImpact(0.45)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
            }
            .accessibilityLabel("Close Explore")
            .accessibilityIdentifier("ExploreCloseButton")
        }

        if navigationPath.isEmpty {
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
                ExploreNotificationButton(
                    unreadCount: feedViewModel.unreadNotificationCount,
                    action: {
                        dependencies.triggerSelectionFeedback()
                        feedViewModel.presentNotifications()
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var discoveryTabContent: some View {
        switch activeDiscoveryMode {
        case .feed:
            ExploreFeedTabContent(
                viewModel: feedViewModel,
                onOpenPostDetail: {
                    onOpenPost(ExplorePostNavigationRequest(post: $0, origin: .feed))
                },
                onOpenFieldTrip: {
                    navigationPath.append(
                        FieldTripPublicationRoute(publicationId: $0.publicationId)
                    )
                },
                onOpenAuthorProfile: openAuthorProfile,
                onOpenFieldTripAuthorProfile: openAuthorProfile,
                onOpenHashtag: openHashtag,
                onOpenInsight: canOpenOwnedPostInsight ? openInsight : nil
            )
        case .map:
            ExploreMapView(
                viewModel: mapViewModel,
                feedViewModel: feedViewModel,
                postStore: feedViewModel.store,
                onOpenDetail: { post, focusCommentComposer in
                    onOpenPost(ExplorePostNavigationRequest(
                        post: post,
                        focusCommentComposer: focusCommentComposer,
                        origin: .map
                    ))
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

    private func observationMapHandler(
        for route: ExplorePostRoute
    ) -> ((ExploreMapFocusTarget) -> Void)? {
        guard route.allowsObservationMapNavigation else { return nil }
        return openExploreMap
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
        dependencies.triggerSelectionFeedback()
        feedViewModel.upsertPost(post)
        appendAuthorProfileRoute(ExploreAuthorProfileRoute(post: post), fromDepth: 0)
    }

    private func openAuthorProfile(for publication: FieldTripRecentPublication) {
        dependencies.triggerSelectionFeedback()
        appendAuthorProfileRoute(ExploreAuthorProfileRoute(
            authorUserId: publication.authorUserId,
            authorName: publication.authorName,
            authorUsername: publication.authorUsername,
            authorAvatarUrl: publication.authorAvatarUrl
        ), fromDepth: 0)
    }

    private func openAuthorProfile(for entry: FieldTripChallengeEntry) {
        dependencies.triggerSelectionFeedback()
        appendAuthorProfileRoute(ExploreAuthorProfileRoute(
            authorUserId: entry.authorUserId,
            authorName: entry.authorName,
            authorUsername: entry.authorUsername,
            authorAvatarUrl: entry.authorAvatarUrl
        ), fromDepth: 0)
    }

    private func appendAuthorProfileRoute(
        _ route: ExploreAuthorProfileRoute,
        fromDepth currentDepth: Int
    ) {
        guard ExploreAuthorProfileNavigationPolicy.canOpenProfile(from: currentDepth) else {
            dependencies.triggerLightImpact(0.35)
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
        dependencies.triggerSelectionFeedback()
        navigationPath.append(ExploreHashtagRoute(hashtag: hashtag))
    }

    private func openInsight(for post: ExplorePost) {
        guard isOwnedByCurrentUser(post) else { return }

        if onOpenOwnedPostInsight != nil {
            if openOwnedPostInsightFromParent(post.scanId) {
                dependencies.triggerSelectionFeedback()
            } else {
                presentUnavailableScanMessage()
            }
            return
        }

        guard allowsInsightPresentation,
              let scanId = availableLocalScanId(post.scanId) else {
            if allowsInsightPresentation {
                presentUnavailableScanMessage()
            }
            return
        }

        dependencies.triggerSelectionFeedback()
        selectedInsightRoute = ScanInsightRoute(scanId: scanId)
    }

    private func openFieldTripCompletedScan(_ scanId: String) {
        guard let resolvedScanId = availableLocalScanId(scanId) else {
            presentUnavailableScanMessage()
            return
        }

        dependencies.triggerSelectionFeedback()
        navigationPath.append(ScanInsightRoute(scanId: resolvedScanId))
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
        post.isOwnedByViewer || supabase.currentUser?.id.uuidString == post.authorUserId
    }

    private func availableLocalScanId(_ scanId: String) -> String? {
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        return try? modelContext.fetch(descriptor).first?.id
    }

    private func presentUnavailableScanMessage() {
        dependencies.triggerErrorFeedback()
        feedViewModel.toastMessage = .warning("This scan is not available on this device.")
    }

    @MainActor
    private func openFieldTripOverviewDestination(
        _ destination: InsightFieldTripOverviewDestination
    ) {
        applyFieldTripNavigation(
            ExploreFieldTripNavigationPolicy.resolve(insightOverview: destination)
        )
    }

    private func applyFieldTripNavigation(_ plan: ExploreFieldTripNavigationPlan) {
        activeTab = .fieldTrips
        activeFieldTripsSection = plan.section

        switch plan.destination {
        case .template(let route):
            navigationPath.append(route)
        case .challenge(let route):
            navigationPath.append(route)
        }
    }
}
