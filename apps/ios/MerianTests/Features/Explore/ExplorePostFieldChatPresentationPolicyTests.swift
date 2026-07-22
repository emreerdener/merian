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
}
