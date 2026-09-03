import Foundation
import Testing

@testable import Merian

@Suite("Feedback Survey Tests")
@MainActor
struct FeedbackSurveyTests {
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

}
