enum ExploreTab: Hashable, CaseIterable {
    case feed
    case fieldTrips
    case community
}

enum ExploreDiscoveryMode: Hashable {
    case feed
    case map
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

enum ExploreFieldTripNavigationDestination: Equatable {
    case template(FieldTripTemplateRoute)
    case challenge(FieldTripChallengeRoute)
}

struct ExploreFieldTripNavigationPlan {
    let section: FieldTripsSection
    let destination: ExploreFieldTripNavigationDestination
}

enum ExploreFieldTripNavigationPolicy {
    static func resolve(
        captureGoal destination: CaptureGoalDestination
    ) -> ExploreFieldTripNavigationPlan {
        switch destination {
        case .fieldTrip(let templateId, let checklistItemId):
            ExploreFieldTripNavigationPlan(
                section: .fieldTrips,
                destination: .template(FieldTripTemplateRoute(
                    templateId: templateId,
                    focusedChecklistItemId: checklistItemId
                ))
            )
        case .fieldTripTemplate(let slug):
            ExploreFieldTripNavigationPlan(
                section: .fieldTrips,
                destination: .template(FieldTripTemplateRoute(slug: slug))
            )
        case .fieldTripChallenge(let challengeId):
            ExploreFieldTripNavigationPlan(
                section: .seasonal,
                destination: .challenge(FieldTripChallengeRoute(challengeId: challengeId))
            )
        }
    }

    static func resolve(
        insightOverview destination: InsightFieldTripOverviewDestination
    ) -> ExploreFieldTripNavigationPlan {
        switch destination {
        case .standardOuting(let templateId):
            ExploreFieldTripNavigationPlan(
                section: .fieldTrips,
                destination: .template(FieldTripTemplateRoute(templateId: templateId))
            )
        case .event(let challengeId):
            ExploreFieldTripNavigationPlan(
                section: .seasonal,
                destination: .challenge(FieldTripChallengeRoute(challengeId: challengeId))
            )
        }
    }
}

enum ExploreShellInitialDestination: Equatable {
    case speciesDictionary(SpeciesDictionaryRoute)
    case fieldTrip(ExploreFieldTripNavigationDestination)
    case communityRequest(ExploreCommunityRequestRoute)
    case post(ExplorePostRoute)
}

struct ExploreShellInitialNavigationPlan {
    let activeTab: ExploreTab
    let activeIdentifyMode: ExploreIdentifyMode
    let activeFieldTripsSection: FieldTripsSection
    let destination: ExploreShellInitialDestination?
}

extension ExploreShellInitialNavigationPlan {
    static func resolve(
        initialPostId: String?,
        initialSpeciesDictionaryRoute: SpeciesDictionaryRoute?,
        initialCommunityRequestId: String?,
        initialTargetCommentId: String?,
        initialTargetReplyParentCommentId: String?,
        initialCaptureGoalDestination: CaptureGoalDestination?,
        initialTab: ExploreTab
    ) -> Self {
        var activeTab = ExploreInitialTabPolicy.resolve(
            requestedTab: initialTab,
            speciesDictionaryRoute: initialSpeciesDictionaryRoute,
            communityRequestId: initialCommunityRequestId
        )
        let activeIdentifyMode = ExploreInitialIdentifyModePolicy.resolve(
            speciesDictionaryRoute: initialSpeciesDictionaryRoute,
            communityRequestId: initialCommunityRequestId
        )
        var activeFieldTripsSection = FieldTripsSection.fieldTrips
        let destination: ExploreShellInitialDestination?

        if let initialSpeciesDictionaryRoute {
            destination = .speciesDictionary(initialSpeciesDictionaryRoute)
        } else if let initialCaptureGoalDestination {
            let plan = ExploreFieldTripNavigationPolicy.resolve(
                captureGoal: initialCaptureGoalDestination
            )
            activeTab = .fieldTrips
            activeFieldTripsSection = plan.section
            destination = .fieldTrip(plan.destination)
        } else if let initialCommunityRequestId {
            activeTab = .community
            destination = .communityRequest(
                ExploreCommunityRequestRoute(requestId: initialCommunityRequestId)
            )
        } else if let initialPostId {
            destination = .post(ExplorePostRoute(
                postId: initialPostId,
                shouldFocusCommentComposer: false,
                shouldOpenInsight: false,
                targetCommentId: initialTargetCommentId,
                targetReplyParentCommentId: initialTargetReplyParentCommentId
            ))
        } else {
            destination = nil
        }

        return Self(
            activeTab: activeTab,
            activeIdentifyMode: activeIdentifyMode,
            activeFieldTripsSection: activeFieldTripsSection,
            destination: destination
        )
    }
}

struct ExplorePostNavigationRequest {
    let post: ExplorePost
    let focusCommentComposer: Bool
    let openInsight: Bool
    let targetCommentId: String?
    let targetReplyParentCommentId: String?
    let notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget?
    let origin: ExplorePostDetailOrigin

    init(
        post: ExplorePost,
        focusCommentComposer: Bool = false,
        openInsight: Bool = false,
        targetCommentId: String? = nil,
        targetReplyParentCommentId: String? = nil,
        notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget? = nil,
        origin: ExplorePostDetailOrigin = .other
    ) {
        self.post = post
        self.focusCommentComposer = focusCommentComposer
        self.openInsight = openInsight
        self.targetCommentId = targetCommentId
        self.targetReplyParentCommentId = targetReplyParentCommentId
        self.notificationReplyThreadTarget = notificationReplyThreadTarget
        self.origin = origin
    }
}
