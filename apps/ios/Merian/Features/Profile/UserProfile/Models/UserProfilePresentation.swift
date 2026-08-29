import Foundation

enum UserProfilePresentation: Identifiable {
    case usernameEditor
    case displayNameEditor
    case avatarCrop(IdentifiableImage)

    var id: String {
        switch self {
        case .usernameEditor:
            "username-editor"
        case .displayNameEditor:
            "display-name-editor"
        case .avatarCrop(let image):
            "avatar-crop-\(image.id.uuidString)"
        }
    }

    var usesFullscreenCover: Bool {
        if case .avatarCrop = self { return true }
        return false
    }
}

enum UserProfileAvatarPresentationPolicy {
    static func canAcceptPreparedAvatar(
        requestID: UUID,
        currentRequestID: UUID?,
        hasActivePresentation: Bool,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled && !hasActivePresentation && currentRequestID == requestID
    }
}
