import Foundation
import SwiftUI
@testable import Merian
import Testing

struct ToastPayloadTests {
    @Test func typedToastSeparatesTitleBodySeverityAndAction() {
        let toast = ToastPayload.success(
            "Shared to Explore\nYour post is now visible.",
            action: .viewExplorePost
        )

        #expect(toast.title == "Shared to Explore")
        #expect(toast.body == "Your post is now visible.")
        #expect(toast.severity == .success)
        #expect(toast.action == .viewExplorePost)
    }

    @Test func replacingEquivalentToastStillCreatesNewPresentationIdentity() {
        let first = ToastPayload.information("Saved")
        let replacement = ToastPayload.information("Saved")

        #expect(first.id != replacement.id)
        #expect(first.title == replacement.title)
    }

    @Test func milestoneSuppressionAppliesOnlyToTheSameFeedbackAlignment() {
        #expect(SystemFeedbackOverlayPolicy.suppressesToast(
            showsAchievementToasts: true,
            toastAlignment: .bottom,
            milestoneAlignment: .bottom,
            hasPresentedMilestone: true
        ))
        #expect(!SystemFeedbackOverlayPolicy.suppressesToast(
            showsAchievementToasts: true,
            toastAlignment: .bottom,
            milestoneAlignment: .top,
            hasPresentedMilestone: true
        ))
        #expect(!SystemFeedbackOverlayPolicy.suppressesToast(
            showsAchievementToasts: false,
            toastAlignment: .bottom,
            milestoneAlignment: .bottom,
            hasPresentedMilestone: true
        ))
        #expect(!SystemFeedbackOverlayPolicy.suppressesToast(
            showsAchievementToasts: true,
            toastAlignment: .bottom,
            milestoneAlignment: .bottom,
            hasPresentedMilestone: false
        ))
    }

    @Test func passiveOrIncompleteToastsNeverClaimHitTesting() {
        #expect(!SystemFeedbackOverlayPolicy.allowsHitTesting(
            hasActionDescriptor: false,
            hasActionHandler: false
        ))
        #expect(!SystemFeedbackOverlayPolicy.allowsHitTesting(
            hasActionDescriptor: true,
            hasActionHandler: false
        ))
        #expect(!SystemFeedbackOverlayPolicy.allowsHitTesting(
            hasActionDescriptor: false,
            hasActionHandler: true
        ))
        #expect(SystemFeedbackOverlayPolicy.allowsHitTesting(
            hasActionDescriptor: true,
            hasActionHandler: true
        ))
    }
}
