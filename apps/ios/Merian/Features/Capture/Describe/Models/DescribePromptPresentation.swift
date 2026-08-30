import Foundation

enum DescribePromptFlow: Equatable {
    case standard
    case reanalysis(subjectId: String?)

    var isReanalysis: Bool {
        if case .reanalysis = self { return true }
        return false
    }

    var inputPlaceholder: String {
        switch self {
        case .standard:
            return DescribePromptCopy.standardInputPlaceholder
        case .reanalysis:
            return DescribePromptCopy.reanalysisInputPlaceholder
        }
    }
}

enum DescribePromptMediaContext: Equatable {
    case none
    case photo
    case audio
    case description
    case mixed
}

enum DescribePromptCopy {
    static let standardInputPlaceholder =
        "e.g., A bright green beetle with gold stripes resting on an oak leaf..."
    static let reanalysisHeading = "What would you like to reanalyze?"
    static let reanalysisSubheading =
        "Tell the AI what to reconsider: the likely species, visible traits, " +
        "behavior, habitat, or anything the first result missed."
    static let reanalysisInputPlaceholder =
        "e.g., Recheck this as a houseplant. Focus on leaf shape, growth habit, " +
        "variegation, and the potting environment."
}
