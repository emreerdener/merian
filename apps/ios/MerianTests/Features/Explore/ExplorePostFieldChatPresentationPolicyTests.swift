@testable import Merian
import Testing

@Suite("Explore Post Field Chat Presentation Policy Tests")
struct ExplorePostFieldChatPolicyTests {
    @Test func floatingButtonIsAvailableWhileBrowsingPostContent() {
        #expect(ExplorePostFieldChatPresentationPolicy.showsFloatingButton(
            isCommentComposerSticky: false,
            isCommentComposerFocused: false
        ))
    }

    @Test func menuActionReplacesFloatingButtonForStickyOrFocusedComposer() {
        for state in [(true, false), (false, true), (true, true)] {
            #expect(!ExplorePostFieldChatPresentationPolicy.showsFloatingButton(
                isCommentComposerSticky: state.0,
                isCommentComposerFocused: state.1
            ))
            #expect(ExplorePostFieldChatPresentationPolicy.showsMenuAction(
                isCommentComposerSticky: state.0,
                isCommentComposerFocused: state.1
            ))
        }
    }

    @Test func menuActionStaysHiddenWhileFloatingButtonIsVisible() {
        #expect(!ExplorePostFieldChatPresentationPolicy.showsMenuAction(
            isCommentComposerSticky: false,
            isCommentComposerFocused: false
        ))
    }
}
