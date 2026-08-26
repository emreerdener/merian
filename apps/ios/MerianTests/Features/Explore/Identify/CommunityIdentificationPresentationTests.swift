@testable import Merian
import Testing

@Suite("Community Identification Presentation")
struct CommunityIdentificationPresentationTests {
    @Test func dashboardPreviewLimitsRemainFixedForMVP() {
        #expect(CommunityIdentificationDashboardPolicy.requestPreviewLimit == 12)
        #expect(CommunityIdentificationDashboardPolicy.activityPreviewLimit == 10)
        #expect(CommunityIdentificationDashboardPolicy.fullPageSize == 30)
    }

    @Test func dashboardSectionsFailIndependently() {
        var state = IdentifyDashboardLoadState()
        state.succeed(.requests)
        state.fail(.activity, message: "Activity unavailable")

        #expect(!state.isLoadingRequests)
        #expect(state.requestErrorMessage == nil)
        #expect(!state.isLoadingActivity)
        #expect(state.activityErrorMessage == "Activity unavailable")

        state.begin(.activity)

        #expect(!state.isLoadingRequests)
        #expect(state.requestErrorMessage == nil)
        #expect(state.isLoadingActivity)
        #expect(state.activityErrorMessage == nil)
    }

    @Test func fullFeedRoutesCarryTheCurrentFilter() {
        #expect(ExploreCommunityRequestsFeedRoute(filter: .mine).filter == .mine)
        #expect(ExploreCommunityActivityFeedRoute(filter: .birds).filter == .birds)
        #expect(CommunityIdentificationRequestFilter.mine.scope == .mine)
        #expect(CommunityIdentificationRequestFilter.birds.group == .birds)
    }

    @Test func requestZeroStatesUseSingularCategoryNames() {
        #expect(CommunityIdentificationRequestFilter.all.emptyRequestTitle == "No requests yet")
        #expect(CommunityIdentificationRequestFilter.mine.emptyRequestTitle == "No requests from you yet")
        #expect(CommunityIdentificationRequestFilter.plants.emptyRequestTitle == "No plant requests yet")
        #expect(CommunityIdentificationRequestFilter.birds.emptyRequestTitle == "No bird requests yet")
        #expect(CommunityIdentificationRequestFilter.insects.emptyRequestTitle == "No insect requests yet")
        #expect(CommunityIdentificationRequestFilter.fungi.emptyRequestTitle == "No fungus requests yet")
        #expect(CommunityIdentificationRequestFilter.mammals.emptyRequestTitle == "No mammal requests yet")
        #expect(
            CommunityIdentificationRequestFilter.reptilesAmphibians.emptyRequestTitle
                == "No herp requests yet"
        )
    }

    @Test func rootModeRemainsRequestsAndIndex() {
        #expect(ExploreIdentifyMode.allCases == [.requests, .index])
    }
}
