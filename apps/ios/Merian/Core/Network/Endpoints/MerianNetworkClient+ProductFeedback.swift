import Foundation

/// Product feedback requests. Feature adapters and models retain validation,
/// metadata construction, draft state, and submission presentation.
extension MerianNetworkClient {
    func submitFeedbackSurvey(_ submission: FeedbackSurveySubmission) async throws {
        _ = try await performAuthenticatedEncodedJSONPost(
            function: "submit-feedback-survey",
            body: submission,
            timeoutInterval: 30
        )
    }

    func submitCommunityFeedback(feedback: String) async throws {
        let submission = CommunityFeedbackSubmission(feedback: feedback)
        _ = try await performAuthenticatedEncodedJSONPost(
            function: "submit-community-feedback",
            body: submission,
            timeoutInterval: 30
        )
    }
}
