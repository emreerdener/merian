@testable import Merian
import Foundation
import Testing

@Suite("Community Identification Presentation")
struct CommunityIdentificationPresentationTests {
    @Test func unknownProviderScoresDoNotAcquireGeminiPresentation() {
        #expect(CommunityAIIdentificationPresentation.confidenceLabel(score: 0.999, qualified: false) == nil)
        #expect(CommunityAIIdentificationPresentation.modelLabel(tier: "pro", qualified: false) == "AI suggestion")
        for qualified: Bool? in [true, nil] {
            #expect(CommunityAIIdentificationPresentation.confidenceLabel(score: 0.91, qualified: qualified) == "91% confident")
            #expect(CommunityAIIdentificationPresentation.modelLabel(tier: "pro", qualified: qualified) == "Naturebook Pro")
            #expect(CommunityAIIdentificationPresentation.modelLabel(tier: nil, qualified: qualified) == "Naturebook Flash")
        }
        #expect(CommunityAIIdentificationPresentation.confidenceLabel(score: nil, qualified: true) == nil)
        #expect(CommunityAIIdentificationPresentation.confidenceLabel(score: .infinity, qualified: true) == nil)
    }

    @Test func communityConfidenceFlagDecodesFalseTrueAndLegacyOmission() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var payload: [String: Any] = [
            "request_id": "synthetic-request", "post_id": "synthetic-post", "scan_id": "synthetic-scan",
            "hero_image_url": "https://example.invalid/synthetic.webp", "requested_at": "2026-09-26T00:00:00Z",
            "status": "needs_id", "author_user_id": "synthetic-author", "author_name": "Synthetic",
            "identification_count": 0, "identifications": []
        ]
        func decode() throws -> CommunityIdentificationDetail {
            try decoder.decode(CommunityIdentificationDetail.self, from: JSONSerialization.data(withJSONObject: payload))
        }
        #expect(try decode().aiConfidenceQualified == nil)
        for value in [false, true] {
            payload["ai_confidence_qualified"] = value
            #expect(try decode().aiConfidenceQualified == value)
        }
        payload["ai_confidence_qualified"] = "false"
        #expect(throws: DecodingError.self) { try decode() }
    }

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

    @Test func speciesIsTheLeadingIdentifyMode() {
        #expect(ExploreIdentifyMode.allCases == [.index, .requests])
        #expect(ExploreIdentifyMode.index.title == "Species")
        #expect(ExploreIdentifyMode.requests.title == "Community")
    }
}
