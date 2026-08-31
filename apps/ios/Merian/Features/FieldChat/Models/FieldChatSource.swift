enum FieldChatSource: Equatable {
    case insightScan
    case explorePost
    case speciesDictionary

    var telemetryValue: String {
        switch self {
        case .insightScan:
            "insight_scan"
        case .explorePost:
            "explore_post"
        case .speciesDictionary:
            "species_dictionary"
        }
    }

    var unavailableMessage: String {
        switch self {
        case .insightScan:
            "Field chat isn't available for this scan."
        case .explorePost:
            "This Explore post isn't available for Field chat."
        case .speciesDictionary:
            "This species isn't available for Field chat."
        }
    }
}
