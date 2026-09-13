extension ExplorePostLocationSharing {
    var title: String {
        switch self {
        case .open:
            return "Open"
        case .obscured:
            return "Obscured"
        case .privateLocation:
            return "Private"
        }
    }

    var systemImage: String {
        switch self {
        case .open:
            return "mappin.and.ellipse"
        case .obscured:
            return "location.viewfinder"
        case .privateLocation:
            return "location.slash"
        }
    }

    var detail: String {
        switch self {
        case .open:
            return "Show broad label and add to Explore Map."
        case .obscured:
            return "Show broad label and keep off Explore Map."
        case .privateLocation:
            return "Share this post without public location."
        }
    }
}
