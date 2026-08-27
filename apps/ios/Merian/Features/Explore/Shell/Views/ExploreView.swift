import SwiftData
import SwiftUI

struct ExploreView: View {
    @Environment(EnvironmentContextManager.self) private var environmentContextManager
    @Environment(\.modelContext) private var modelContext

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
    @State private var notificationNavigation = ExploreNotificationNavigationCoordinator()

    private let dependencies: ExploreShellDependencies
    private let allowsInsightPresentation: Bool
    private let onOpenOwnedPostInsight: ((String) -> Bool)?

    private var canOpenOwnedPostInsight: Bool {
        allowsInsightPresentation || onOpenOwnedPostInsight != nil
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
        self.init(
            initialPostId: initialPostId,
            initialSpeciesDictionaryRoute: initialSpeciesDictionaryRoute,
            initialCommunityRequestId: initialCommunityRequestId,
            initialTargetCommentId: initialTargetCommentId,
            initialTargetReplyParentCommentId: initialTargetReplyParentCommentId,
            initialCaptureGoalDestination: initialCaptureGoalDestination,
            initialTab: initialTab,
            allowsInsightPresentation: allowsInsightPresentation,
            onOpenOwnedPostInsight: onOpenOwnedPostInsight,
            dependencies: .live
        )
    }

    init(
        initialPostId: String?,
        initialSpeciesDictionaryRoute: SpeciesDictionaryRoute?,
        initialCommunityRequestId: String?,
        initialTargetCommentId: String?,
        initialTargetReplyParentCommentId: String?,
        initialCaptureGoalDestination: CaptureGoalDestination?,
        initialTab: ExploreTab,
        allowsInsightPresentation: Bool,
        onOpenOwnedPostInsight: ((String) -> Bool)?,
        dependencies: ExploreShellDependencies
    ) {
        let plan = ExploreShellInitialNavigationPlan.resolve(
            initialPostId: initialPostId,
            initialSpeciesDictionaryRoute: initialSpeciesDictionaryRoute,
            initialCommunityRequestId: initialCommunityRequestId,
            initialTargetCommentId: initialTargetCommentId,
            initialTargetReplyParentCommentId: initialTargetReplyParentCommentId,
            initialCaptureGoalDestination: initialCaptureGoalDestination,
            initialTab: initialTab
        )

        self.dependencies = dependencies
        self.allowsInsightPresentation = allowsInsightPresentation
        self.onOpenOwnedPostInsight = onOpenOwnedPostInsight
        _activeTab = State(initialValue: plan.activeTab)
        _activeIdentifyMode = State(initialValue: plan.activeIdentifyMode)
        _activeFieldTripsSection = State(initialValue: plan.activeFieldTripsSection)
        _navigationPath = State(initialValue: Self.navigationPath(for: plan.destination))
    }

    var body: some View {
        ExploreShellNavigationView(
            navigationPath: $navigationPath,
            selectedInsightRoute: $selectedInsightRoute,
            activeTab: $activeTab,
            activeDiscoveryMode: $activeDiscoveryMode,
            activeIdentifyMode: $activeIdentifyMode,
            activeFieldTripsSection: $activeFieldTripsSection,
            feedViewModel: viewModel,
            mapViewModel: mapViewModel,
            dictionaryUserRegionIdentifier: dictionaryUserRegionIdentifier,
            allowsInsightPresentation: allowsInsightPresentation,
            onOpenOwnedPostInsight: onOpenOwnedPostInsight,
            dependencies: dependencies,
            onOpenPost: openPostDetail,
            onOpenCommunityIdentificationRequest: openCommunityIdentificationRequest
        )
        .environment(playbackCoordinator)
        .modifier(ExploreShellLifecycleModifier(
            feedViewModel: viewModel,
            activeTab: activeTab,
            activeDiscoveryMode: activeDiscoveryMode,
            activeIdentifyMode: activeIdentifyMode,
            triggerSelectionFeedback: dependencies.triggerSelectionFeedback,
            refreshDictionaryUserRegion: refreshDictionaryUserRegionFromAuthorizedLocation
        ))
        .modifier(ExploreShellPresentationModifier(
            feedViewModel: viewModel,
            selectedInsightRoute: $selectedInsightRoute,
            onNotificationsDismiss: notificationSheetDidDismiss,
            onOpenNotification: openNotification,
            onStageInsightCommunityRequest: { requestId in
                pendingInsightCommunityRequestId = requestId
            },
            onResumeInsightCommunityRequest: resumePendingInsightCommunityRequest
        ))
        .modifier(ExploreShellEventFeedbackModifier(
            feedViewModel: viewModel,
            mapViewModel: mapViewModel,
            dependencies: dependencies
        ))
    }

    private func openPostDetail(_ request: ExplorePostNavigationRequest) {
        let post = request.post
        viewModel.upsertPost(post)
        viewModel.refreshPreferredSpeciesNames(
            for: [post.speciesScientificName],
            modelContext: modelContext
        )
        navigationPath.append(ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: request.focusCommentComposer,
            shouldOpenInsight: canOpenOwnedPostInsight && request.openInsight,
            targetCommentId: request.targetCommentId,
            targetReplyParentCommentId: request.targetReplyParentCommentId,
            notificationReplyThreadTarget: request.notificationReplyThreadTarget,
            origin: request.origin
        ))
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

    private func openNotification(_ notification: ExploreNotification) async {
        let outcome = await notificationNavigation.prepareDestination(
            for: notification,
            fieldTripsEnabled: FeatureFlags.isEnabled(.fieldTrips),
            isSheetPresented: { viewModel.isNotificationsSheetPresented },
            preparePostId: { postId in
                try await viewModel.preparePostForNavigation(postId: postId).id
            }
        )

        switch outcome {
        case .staged(let token):
            guard notificationNavigation.commitStagedDestination(
                token,
                isSheetPresented: { viewModel.isNotificationsSheetPresented }
            ) else {
                return
            }
            viewModel.dismissNotifications()
        case .failed(let token, let error):
            guard notificationNavigation.commitFailedOpen(
                token,
                isSheetPresented: { viewModel.isNotificationsSheetPresented }
            ) else {
                return
            }
            MerianLog.network.error(
                "Failed to open Explore notification \(notification.id, privacy: .private): \(error.localizedDescription, privacy: .private)"
            )
            AppTelemetry.trackExploreNotificationOpenFailed(type: notification.type.rawValue)
            dependencies.triggerErrorFeedback()
            viewModel.toastMessage = .error(ExploreErrorFormatter.message(for: error))
            viewModel.dismissNotifications()
        case .ignored:
            break
        }
    }

    private func notificationSheetDidDismiss() {
        notificationNavigation.invalidateOpen()
        resumePendingNotificationDestination()
    }

    private func resumePendingNotificationDestination() {
        guard let destination = notificationNavigation.takePendingDestination() else { return }

        switch destination {
        case .scansLibrary:
            dependencies.requestScansLibrary()
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
                dependencies.triggerErrorFeedback()
                viewModel.toastMessage = .error("This Explore post is no longer available.")
                return
            }
            if let targetReplyParentCommentId {
                viewModel.prepareToExpandReplyThread(parentCommentId: targetReplyParentCommentId)
            }
            openPostDetail(ExplorePostNavigationRequest(
                post: post,
                focusCommentComposer: focusCommentComposer,
                targetCommentId: targetCommentId,
                targetReplyParentCommentId: targetReplyParentCommentId,
                notificationReplyThreadTarget: replyThreadTarget
            ))
        }
    }

    private static func navigationPath(
        for destination: ExploreShellInitialDestination?
    ) -> NavigationPath {
        var path = NavigationPath()
        guard let destination else { return path }

        switch destination {
        case .speciesDictionary(let route):
            path.append(route)
        case .fieldTrip(.template(let route)):
            path.append(route)
        case .fieldTrip(.challenge(let route)):
            path.append(route)
        case .communityRequest(let route):
            path.append(route)
        case .post(let route):
            path.append(route)
        }
        return path
    }

    private static func defaultDictionaryUserRegionIdentifier() -> String? {
        EnvironmentContextManager.normalizedRegionIdentifier(Locale.current.region?.identifier)
    }

    @MainActor
    private func refreshDictionaryUserRegionFromAuthorizedLocation() async {
        guard let regionIdentifier = await environmentContextManager
            .currentAuthorizedRegionIdentifier(),
            regionIdentifier != dictionaryUserRegionIdentifier else {
            return
        }

        dictionaryUserRegionIdentifier = regionIdentifier
    }
}
