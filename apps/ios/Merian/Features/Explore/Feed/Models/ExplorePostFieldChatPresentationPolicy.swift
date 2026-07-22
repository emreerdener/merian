enum ExplorePostFieldChatPresentationPolicy {
    static func showsFloatingButton(
        isFieldChatAvailable: Bool,
        isCommentComposerSticky: Bool,
        isCommentComposerFocused: Bool
    ) -> Bool {
        isFieldChatAvailable && !isCommentComposerSticky && !isCommentComposerFocused
    }

    static func showsMenuAction(
        isFieldChatAvailable: Bool,
        isCommentComposerSticky: Bool,
        isCommentComposerFocused: Bool
    ) -> Bool {
        isFieldChatAvailable && (isCommentComposerSticky || isCommentComposerFocused)
    }
}
