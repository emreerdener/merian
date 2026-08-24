@testable import Merian
import Testing

@Suite("Explore Post Field Chat Presentation Policy Tests")
struct ExplorePostFieldChatPolicyTests {
    @Test func floatingButtonIsAvailableWhileBrowsingPostContent() {
        #expect(ExplorePostFieldChatPresentationPolicy.showsFloatingButton(
            isFieldChatAvailable: true,
            isCommentComposerSticky: false,
            isCommentComposerFocused: false
        ))
    }

    @Test func menuActionReplacesFloatingButtonForStickyOrFocusedComposer() {
        for state in [(true, false), (false, true), (true, true)] {
            #expect(!ExplorePostFieldChatPresentationPolicy.showsFloatingButton(
                isFieldChatAvailable: true,
                isCommentComposerSticky: state.0,
                isCommentComposerFocused: state.1
            ))
            #expect(ExplorePostFieldChatPresentationPolicy.showsMenuAction(
                isFieldChatAvailable: true,
                isCommentComposerSticky: state.0,
                isCommentComposerFocused: state.1
            ))
        }
    }

    @Test func menuActionStaysHiddenWhileFloatingButtonIsVisible() {
        #expect(!ExplorePostFieldChatPresentationPolicy.showsMenuAction(
            isFieldChatAvailable: true,
            isCommentComposerSticky: false,
            isCommentComposerFocused: false
        ))
    }

    @Test func unavailablePostsHideBothFieldChatEntryPoints() {
        for state in [(false, false), (true, false), (false, true), (true, true)] {
            #expect(!ExplorePostFieldChatPresentationPolicy.showsFloatingButton(
                isFieldChatAvailable: false,
                isCommentComposerSticky: state.0,
                isCommentComposerFocused: state.1
            ))
            #expect(!ExplorePostFieldChatPresentationPolicy.showsMenuAction(
                isFieldChatAvailable: false,
                isCommentComposerSticky: state.0,
                isCommentComposerFocused: state.1
            ))
        }
    }

    @Test func asynchronousPresentationRequiresCurrentPostAndAnEmptySlot() {
        #expect(ExplorePostDetailPresentationPolicy.canCommitAsyncPresentation(
            requestedPostId: "POST-1",
            currentPostId: "post-1",
            hasPresentationConflict: false,
            isCancelled: false
        ))
        #expect(!ExplorePostDetailPresentationPolicy.canCommitAsyncPresentation(
            requestedPostId: "post-1",
            currentPostId: "post-2",
            hasPresentationConflict: false,
            isCancelled: false
        ))
        #expect(!ExplorePostDetailPresentationPolicy.canCommitAsyncPresentation(
            requestedPostId: "post-1",
            currentPostId: "post-1",
            hasPresentationConflict: true,
            isCancelled: false
        ))
        #expect(!ExplorePostDetailPresentationPolicy.canCommitAsyncPresentation(
            requestedPostId: "post-1",
            currentPostId: "post-1",
            hasPresentationConflict: false,
            isCancelled: true
        ))
    }

    @Test func localSheetKindsHaveDisjointStableIdentities() {
        let identities = [
            ExplorePostDetailPresentation.fieldNotes(postId: "post-1").id,
            ExplorePostDetailPresentation.postComposer(postId: "post-1").id,
            ExplorePostDetailPresentation.fieldChat(postId: "post-1").id,
            ExplorePostDetailPresentation.paywall.id
        ]

        #expect(Set(identities).count == identities.count)
    }
}
