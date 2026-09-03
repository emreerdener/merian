import Foundation
import Testing

@testable import Merian

@Suite("Product Feedback Endpoints")
@MainActor
struct ProductFeedbackEndpointTests {
    @Test(arguments: [
        EnrichmentExportFeedbackRequestCase.Kind.survey, .communityFeedback
    ])
    func feedbackPreservesConstructorNormalizationMetadataAndWireKeys(
        kind: EnrichmentExportFeedbackRequestCase.Kind
    ) async throws {
        let testCase = try EnrichmentExportFeedbackRequestCase.make(kind)
        try await testCase.withResponse("") { client in try await testCase.invoke(client) }
    }

    @Test func submitFeedbackSurveyEncodesSurveyPayload() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        fixture.transport.register(path: "/submit-feedback-survey") { request in
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

        try await fixture.client.submitFeedbackSurvey(submission)
    }
}
