@testable import Merian
import Testing

@Suite("Explore Shell navigation policy")
@MainActor
struct ExploreShellNavigationPolicyTests {
    @Test func rootNavigationHasExactlyThreeItems() {
        #expect(ExploreTab.allCases == [.feed, .fieldTrips, .community])
    }

    @Test func speciesRouteSelectsIdentifyIndex() {
        let route = speciesRoute()

        #expect(
            ExploreInitialTabPolicy.resolve(
                requestedTab: .feed,
                speciesDictionaryRoute: route
            ) == .community
        )
        #expect(
            ExploreInitialIdentifyModePolicy.resolve(
                speciesDictionaryRoute: route,
                communityRequestId: nil
            ) == .index
        )
    }

    @Test func communityRouteSelectsIdentifyRequests() {
        #expect(
            ExploreInitialTabPolicy.resolve(
                requestedTab: .feed,
                speciesDictionaryRoute: nil,
                communityRequestId: "request-id"
            ) == .community
        )
        #expect(
            ExploreInitialIdentifyModePolicy.resolve(
                speciesDictionaryRoute: nil,
                communityRequestId: "request-id"
            ) == .requests
        )
    }

    @Test func requestedRootTabIsPreservedWithoutAnOverride() {
        let plan = ExploreShellInitialNavigationPlan.resolve(
            initialPostId: nil,
            initialSpeciesDictionaryRoute: nil,
            initialCommunityRequestId: nil,
            initialTargetCommentId: nil,
            initialTargetReplyParentCommentId: nil,
            initialCaptureGoalDestination: nil,
            initialTab: .community
        )

        #expect(plan.activeTab == .community)
        #expect(plan.activeIdentifyMode == .requests)
        #expect(plan.destination == nil)
    }

    @Test func captureGoalPlanPreservesFocusedOutingTarget() {
        let plan = ExploreShellInitialNavigationPlan.resolve(
            initialPostId: "post-id",
            initialSpeciesDictionaryRoute: nil,
            initialCommunityRequestId: "request-id",
            initialTargetCommentId: "comment-id",
            initialTargetReplyParentCommentId: "parent-id",
            initialCaptureGoalDestination: .fieldTrip(
                templateId: "template-id",
                checklistItemId: "goal-id"
            ),
            initialTab: .feed
        )

        #expect(plan.activeTab == .fieldTrips)
        #expect(plan.activeFieldTripsSection == .fieldTrips)
        #expect(
            plan.destination == .fieldTrip(.template(FieldTripTemplateRoute(
                templateId: "template-id",
                focusedChecklistItemId: "goal-id"
            )))
        )
    }

    @Test func eventGoalSelectsSeasonalSection() {
        let plan = ExploreFieldTripNavigationPolicy.resolve(
            captureGoal: .fieldTripChallenge(challengeId: "challenge-id")
        )

        #expect(plan.section == .seasonal)
        #expect(
            plan.destination == .challenge(
                FieldTripChallengeRoute(challengeId: "challenge-id")
            )
        )
    }

    @Test func embeddedInsightOverviewMapsToTheOwnedDestinations() {
        let outing = ExploreFieldTripNavigationPolicy.resolve(
            insightOverview: .standardOuting(templateId: "template-id")
        )
        let event = ExploreFieldTripNavigationPolicy.resolve(
            insightOverview: .event(challengeId: "challenge-id")
        )

        #expect(outing.section == .fieldTrips)
        #expect(
            outing.destination == .template(
                FieldTripTemplateRoute(templateId: "template-id")
            )
        )
        #expect(event.section == .seasonal)
        #expect(
            event.destination == .challenge(
                FieldTripChallengeRoute(challengeId: "challenge-id")
            )
        )
    }

    @Test func speciesDestinationRetainsHighestInitialPriority() {
        let route = speciesRoute()
        let plan = ExploreShellInitialNavigationPlan.resolve(
            initialPostId: "post-id",
            initialSpeciesDictionaryRoute: route,
            initialCommunityRequestId: "request-id",
            initialTargetCommentId: "comment-id",
            initialTargetReplyParentCommentId: "parent-id",
            initialCaptureGoalDestination: .fieldTripTemplate(slug: "outing-slug"),
            initialTab: .fieldTrips
        )

        #expect(plan.activeTab == .community)
        #expect(plan.activeIdentifyMode == .index)
        #expect(plan.destination == .speciesDictionary(route))
    }

    @Test func communityDestinationPrecedesAnInitialPost() {
        let plan = ExploreShellInitialNavigationPlan.resolve(
            initialPostId: "post-id",
            initialSpeciesDictionaryRoute: nil,
            initialCommunityRequestId: "request-id",
            initialTargetCommentId: "comment-id",
            initialTargetReplyParentCommentId: "parent-id",
            initialCaptureGoalDestination: nil,
            initialTab: .feed
        )

        #expect(plan.activeTab == .community)
        #expect(plan.activeIdentifyMode == .requests)
        #expect(
            plan.destination == .communityRequest(
                ExploreCommunityRequestRoute(requestId: "request-id")
            )
        )
    }

    @Test func postPlanPreservesCommentTargets() {
        let plan = ExploreShellInitialNavigationPlan.resolve(
            initialPostId: "post-id",
            initialSpeciesDictionaryRoute: nil,
            initialCommunityRequestId: nil,
            initialTargetCommentId: "comment-id",
            initialTargetReplyParentCommentId: "parent-id",
            initialCaptureGoalDestination: nil,
            initialTab: .feed
        )

        #expect(
            plan.destination == .post(ExplorePostRoute(
                postId: "post-id",
                shouldFocusCommentComposer: false,
                shouldOpenInsight: false,
                targetCommentId: "comment-id",
                targetReplyParentCommentId: "parent-id"
            ))
        )
    }

    private func speciesRoute() -> SpeciesDictionaryRoute {
        SpeciesDictionaryRoute(
            scientificName: "",
            speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            entryPoint: .deepLink
        )
    }
}
