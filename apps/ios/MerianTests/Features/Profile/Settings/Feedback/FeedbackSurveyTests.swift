import Foundation
@testable import Merian
import Testing

@Suite("Feedback Survey Tests", .serialized)
@MainActor
struct FeedbackSurveyTests {
    init() {
        MockURLProtocol.mockEndpoints = [:]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MerianNetworkClient.shared.overridingSession = URLSession(configuration: config)
        MerianNetworkClient.shared.overridingAuthUserID = UUID(
            uuidString: "11111111-1111-4111-8111-111111111111"
        )
    }

    @Test func promptPolicyRequiresForegroundCompletionOnboardingAndMeaningfulUse() {
        #expect(FeedbackSurveyPromptPolicy.shouldPrompt(
            completedScanCount: 3,
            hasCompletedOnboarding: true,
            hasForegroundBiologicalScanCompletion: true,
            dismissedCampaignId: "",
            submittedCampaignId: ""
        ))

        #expect(!FeedbackSurveyPromptPolicy.shouldPrompt(
            completedScanCount: 3,
            hasCompletedOnboarding: true,
            hasForegroundBiologicalScanCompletion: false,
            dismissedCampaignId: "",
            submittedCampaignId: ""
        ))

        #expect(!FeedbackSurveyPromptPolicy.shouldPrompt(
            completedScanCount: 2,
            hasCompletedOnboarding: true,
            hasForegroundBiologicalScanCompletion: true,
            dismissedCampaignId: "",
            submittedCampaignId: ""
        ))

        #expect(!FeedbackSurveyPromptPolicy.shouldPrompt(
            completedScanCount: 3,
            hasCompletedOnboarding: false,
            hasForegroundBiologicalScanCompletion: true,
            dismissedCampaignId: "",
            submittedCampaignId: ""
        ))
    }

    @Test func promptPolicySuppressesDismissedOrSubmittedCampaign() {
        #expect(!FeedbackSurveyPromptPolicy.shouldPrompt(
            completedScanCount: 3,
            hasCompletedOnboarding: true,
            hasForegroundBiologicalScanCompletion: true,
            dismissedCampaignId: FeedbackSurveyCampaign.currentId,
            submittedCampaignId: ""
        ))

        #expect(!FeedbackSurveyPromptPolicy.shouldPrompt(
            completedScanCount: 3,
            hasCompletedOnboarding: true,
            hasForegroundBiologicalScanCompletion: true,
            dismissedCampaignId: "",
            submittedCampaignId: FeedbackSurveyCampaign.currentId
        ))
    }

    @Test func submittedStateExpiresAfterRepeatSubmissionCooldown() {
        let submittedAt: TimeInterval = 1_000
        let stillCoolingDown = Date(
            timeIntervalSince1970: submittedAt + FeedbackSurveyCampaign.repeatSubmissionCooldown - 1
        )
        let readyForMoreFeedback = Date(
            timeIntervalSince1970: submittedAt + FeedbackSurveyCampaign.repeatSubmissionCooldown
        )

        #expect(FeedbackSurveyCampaign.isSubmittedStateActive(
            submittedCampaignId: FeedbackSurveyCampaign.currentId,
            submittedAt: submittedAt,
            now: stillCoolingDown
        ))
        #expect(!FeedbackSurveyCampaign.isSubmittedStateActive(
            submittedCampaignId: FeedbackSurveyCampaign.currentId,
            submittedAt: submittedAt,
            now: readyForMoreFeedback
        ))
        #expect(!FeedbackSurveyCampaign.isSubmittedStateActive(
            submittedCampaignId: FeedbackSurveyCampaign.currentId,
            submittedAt: 0,
            now: stillCoolingDown
        ))
    }

    @Test func submitFeedbackSurveyEncodesSurveyPayload() async throws {
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/submit-feedback-survey"] = { request in
            #expect(request.url?.path.hasSuffix("/submit-feedback-survey") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["survey_campaign_id"] as? String == FeedbackSurveyCampaign.currentId)
            #expect(payload["satisfaction_rating"] as? Int == 5)
            #expect(payload["recommendation_rating"] as? Int == 10)
            #expect(payload["used_features"] as? [String] == ["identify_found_subject", "browse_explore"])
            #expect(payload["most_useful_features"] as? [String] == ["camera_identification", "insight_sheet"])
            #expect(payload["bug_status"] as? String == "blocked")
            #expect(payload["may_follow_up"] as? Bool == false)
            #expect(payload["contact"] as? String == "")
            #expect(payload["platform"] as? String == "ios")

            return (mockResponse, Data(#"{"success":true}"#.utf8))
        }

        let submission = FeedbackSurveySubmission(
            satisfactionRating: 5,
            recommendationRating: 10,
            usedFeatures: [.identifyFoundSubject, .browseExplore],
            mostUsefulFeatures: [.cameraIdentification, .insightSheet],
            confusingOrDisappointing: "Nothing yet.",
            wishedNext: "More field notes.",
            bugStatus: .blocked,
            bugDetails: "A blocking issue.",
            mayFollowUp: false,
            contact: ""
        )

        try await MerianNetworkClient.shared.submitFeedbackSurvey(submission)
    }
}
