extension FieldTripCommunityMode {
    var title: String {
        switch self {
        case .smart:
            "For You"
        case .following:
            "Following"
        case .recent:
            "Recent"
        }
    }
}
