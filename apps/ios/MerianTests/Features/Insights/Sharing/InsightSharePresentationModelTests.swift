import Testing

@testable import Merian

struct InsightSharePresentationModelTests {
    @Test func publishedPresentationPreservesCopy() {
        let presentation = InsightSharePresentation(
            sharedExplorePostID: "post-id",
            recommendation: .publishToExplore
        )

        #expect(presentation.isPublished)
        #expect(presentation.headline == "Published")
        #expect(presentation.actionTitle == "View post")
        #expect(
            presentation.description ==
                "This discovery is visible to the community."
        )
    }

    @Test func recommendationCopyAndPrimaryActionsRemainStable() {
        let ask = InsightSharePresentation(
            sharedExplorePostID: nil,
            recommendation: .askCommunity
        )
        #expect(ask.headline == "Ask the community")
        #expect(ask.actionTitle == "Ask for ID")
        #expect(
            ask.primaryAction(
                canAskCommunity: true,
                canEditCommunityRequest: false
            ) == .askCommunity
        )
        #expect(
            ask.primaryAction(
                canAskCommunity: false,
                canEditCommunityRequest: false
            ) == .composeExplorePost
        )

        let pending = InsightSharePresentation(
            sharedExplorePostID: nil,
            recommendation: .communityPending
        )
        #expect(pending.headline == "Identify request")
        #expect(pending.actionTitle == "Edit request")
        #expect(
            pending.publishConfirmationMessage ==
                InsightSharePresentation.pendingCommunityPublishDisclaimer
        )
        #expect(
            pending.primaryAction(
                canAskCommunity: false,
                canEditCommunityRequest: true
            ) == .editCommunityRequest
        )
        #expect(
            pending.primaryAction(
                canAskCommunity: false,
                canEditCommunityRequest: false
            ) == .viewCommunityRequest
        )

        let resolved = InsightSharePresentation(
            sharedExplorePostID: nil,
            recommendation: .communityResolvedNeedsPublish
        )
        #expect(resolved.headline == "Ready to publish")
        #expect(resolved.actionTitle == "Share discovery")
        #expect(
            resolved.primaryAction(
                canAskCommunity: true,
                canEditCommunityRequest: true
            ) == .composeExplorePost
        )
    }
}
