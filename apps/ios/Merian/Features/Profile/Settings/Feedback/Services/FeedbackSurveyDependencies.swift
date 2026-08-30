import Foundation

@MainActor
struct FeedbackSurveyDependencies {
    let submit: @MainActor (
        _ submission: FeedbackSurveySubmission
    ) async throws -> Void
    let now: @MainActor () -> Date
}

extension FeedbackSurveyDependencies {
    static var live: Self {
        Self(
            submit: { submission in
                try await MerianNetworkClient.shared.submitFeedbackSurvey(
                    submission
                )
            },
            now: Date.init
        )
    }
}
