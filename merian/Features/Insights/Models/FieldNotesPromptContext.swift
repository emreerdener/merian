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
        if let kingdom = normalize(speciesData.taxonomy?.kingdom) {
            if kingdom == "fungi" { return "subj_mush" }
            if kingdom == "plantae" { return "subj_plan" }
        }

        if let className = normalize(speciesData.taxonomy?.className) {
            switch className {
            case "aves":
                return "subj_bird"
            case "insecta":
                return "subj_insec"
            case "arachnida":
                return "subj_spid"
            case "mammalia":
                return "subj_mamm"
            case "amphibia", "reptilia":
                return "subj_rept"
            case "actinopterygii", "chondrichthyes", "myxini", "cephalaspidomorphi", "sarcopterygii":
                return "subj_fish"
            default:
                break
            }
        }

        let searchCorpus = [
            speciesData.commonName,
            speciesData.scientificName,
            speciesData.taxonomy?.order,
            speciesData.taxonomy?.family,
            speciesData.taxonomy?.genus
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let searchWords = Set(
            searchCorpus
                .split { !$0.isLetter }
                .map(String.init)
        )

        let heuristics: [(subjectId: String, tokens: [String])] = [
            ("subj_bird", ["bird", "sparrow", "owl", "hawk", "eagle", "warbler", "duck", "goose", "heron"]),
            ("subj_insec", ["insect", "beetle", "butterfly", "moth", "bee", "wasp", "dragonfly"]),
            ("subj_spid", ["spider", "arachnid", "tarantula", "tick", "mite"]),
            ("subj_rept", ["snake", "lizard", "frog", "toad", "salamander", "newt", "turtle", "reptile", "amphibian"]),
            ("subj_plan", ["plant", "flower", "tree", "shrub", "fern", "grass", "moss", "leaf"]),
            ("subj_mush", ["mushroom", "fungus", "fungi", "toadstool", "lichen"]),
            ("subj_mamm", ["mammal", "rodent", "rabbit", "hare", "squirrel", "mouse", "bat", "fox", "raccoon", "deer"]),
            ("subj_fish", ["fish", "shark", "ray", "eel", "salmon", "trout"])
        ]

        for heuristic in heuristics where heuristic.tokens.contains(where: { token in
            searchWords.contains(token) || searchCorpus.contains(token)
        }) {
            return heuristic.subjectId
        }

        return nil
    }

    private static func normalize(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
