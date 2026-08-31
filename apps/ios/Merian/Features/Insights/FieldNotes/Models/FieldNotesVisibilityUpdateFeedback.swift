enum FieldNotesVisibilityUpdateFeedback {
    case success(isPublic: Bool)
    case failure(String)

    var message: String {
        switch self {
        case .success(let isPublic):
            return isPublic ? "Field notes are now public on Explore" : "Field notes are now private"
        case .failure(let message):
            return message
        }
    }
}
