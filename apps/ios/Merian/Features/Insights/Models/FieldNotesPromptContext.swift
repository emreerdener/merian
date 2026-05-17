import Foundation

enum FieldNotesPromptContext: Equatable {
    case analyzing
    case resolved(subjectId: String?)

    var subjectId: String? {
        switch self {
        case .analyzing:
            return nil
        case .resolved(let subjectId):
            return subjectId
        }
    }

    var suggestedHint: String {
        switch self {
        case .analyzing:
            return "Capture the subject group first, then add behavior, habitat, and anything memorable while the ID runs."
        case .resolved(.some("subj_bird")):
            return "Capture plumage, beak shape, and what it was doing."
        case .resolved(.some("subj_insec")):
            return "Capture wing posture, body texture, and standout markings."
        case .resolved(.some("subj_spid")):
            return "Capture body shape, web details, and distinctive patterns."
        case .resolved(.some("subj_rept")):
            return "Capture skin texture, banding, and exactly where it was resting."
        case .resolved(.some("subj_plan")):
            return "Capture leaves, blooms, and where it was growing."
        case .resolved(.some("subj_mush")):
            return "Capture cap texture, underside details, and what it was growing from."
        case .resolved(.some("subj_mamm")):
            return "Capture fur color, tail shape, and when it was active."
        case .resolved(.some("subj_fish")):
            return "Capture body shape, fin details, and the water environment."
        case .resolved:
            return "Add any field context the camera could not capture, like behavior, habitat, or sounds."
        }
    }
}

enum FieldNotesPromptResolver {
    static func context(for speciesData: SpeciesData?) -> FieldNotesPromptContext {
        guard let speciesData else { return .analyzing }
        return .resolved(subjectId: subjectId(for: speciesData))
    }

    static func subjectId(for speciesData: SpeciesData) -> String? {
        DescribeSubjectResolver.subjectId(for: speciesData)
    }
}
