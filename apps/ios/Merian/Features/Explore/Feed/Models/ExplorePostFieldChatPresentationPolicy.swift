enum ExplorePostFieldChatPresentationPolicy {
    static func showsFloatingButton(
        isCommentComposerSticky: Bool,
        isCommentComposerFocused: Bool
    ) -> Bool {
        !isCommentComposerSticky && !isCommentComposerFocused
    }

    static func showsMenuAction(
        isCommentComposerSticky: Bool,
        isCommentComposerFocused: Bool
    ) -> Bool {
        isCommentComposerSticky || isCommentComposerFocused
    }
}
