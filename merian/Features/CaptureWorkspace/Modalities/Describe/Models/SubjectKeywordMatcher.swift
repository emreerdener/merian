import Foundation

struct SubjectKeywordMatcher {
    static func infer(from text: String) -> String? {
        DescribeSubjectResolver.subjectId(forText: text)
    }
}

enum DescribeSubjectResolver {
    static func subjectId(for speciesData: SpeciesData) -> String? {
        subjectId(
            taxonomy: speciesData.taxonomy,
            commonName: speciesData.commonName,
            scientificName: speciesData.scientificName
        )
    }

    static func subjectId(for record: LocalScanRecord) -> String? {
        let taxonomy = TaxonomyData(
            kingdom: record.taxonomyKingdom,
            phylum: record.taxonomyPhylum,
            className: record.taxonomyClass,
            order: record.taxonomyOrder,
            family: record.taxonomyFamily,
            genus: record.taxonomyGenus
        )
        return subjectId(
            taxonomy: taxonomy,
            commonName: record.commonName,
            scientificName: record.scientificName
        )
    }

    static func subjectId(
        taxonomy: TaxonomyData?,
        commonName: String?,
        scientificName: String?
    ) -> String? {
        if let kingdom = normalize(taxonomy?.kingdom) {
            if kingdom == "fungi" { return "subj_mush" }
            if kingdom == "plantae" { return "subj_plan" }
        }

        if let className = normalize(taxonomy?.className) {
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

        return subjectId(fromSearchFields: [
            commonName,
            scientificName,
            taxonomy?.order,
            taxonomy?.family,
            taxonomy?.genus
        ])
    }

    static func subjectId(forText text: String) -> String? {
        subjectId(fromSearchFields: [text])
    }

    private static func subjectId(fromSearchFields fields: [String?]) -> String? {
        let words = Set(
            fields
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
                .split { !$0.isLetter }
                .map(String.init)
        )

        for heuristic in heuristics where heuristic.tokens.contains(where: words.contains) {
            return heuristic.subjectId
        }
        return nil
    }

    private static let heuristics: [(subjectId: String, tokens: [String])] = [
        (
            "subj_bird",
            [
                "bird", "sparrow", "hawk", "eagle", "robin", "pigeon", "duck",
                "goose", "owl", "warbler", "heron", "passeriformes", "anatidae", "corvidae"
            ]
        ),
        (
            "subj_insec",
            [
                "insect", "beetle", "butterfly", "moth", "bee", "wasp", "fly",
                "dragonfly", "ant", "bug", "lepidoptera", "coleoptera", "diptera",
                "hymenoptera", "odonata", "danaus"
            ]
        ),
        (
            "subj_spid",
            [
                "spider", "arachnid", "tarantula", "scorpion", "tick", "mite",
                "araneae", "salticidae", "lycosidae"
            ]
        ),
        (
            "subj_rept",
            [
                "reptile", "amphibian", "snake", "lizard", "turtle", "tortoise",
                "frog", "toad", "salamander", "newt", "squamata", "anura",
                "caudata", "testudines"
            ]
        ),
        (
            "subj_plan",
            [
                "plant", "tree", "flower", "shrub", "bush", "fern", "moss",
                "grass", "weed", "leaf", "oak", "quercus", "rosa", "rosaceae",
                "poaceae", "asteraceae", "pinus", "acer"
            ]
        ),
        (
            "subj_mush",
            [
                "mushroom", "fungus", "fungi", "toadstool", "puffball", "lichen",
                "amanita", "boletus", "agaricus", "polyporales"
            ]
        ),
        (
            "subj_mamm",
            [
                "mammal", "rodent", "squirrel", "rabbit", "hare", "raccoon",
                "skunk", "opossum", "mouse", "rat", "bat", "fox", "deer",
                "rodentia", "sciuridae", "canidae", "cervidae"
            ]
        ),
        (
            "subj_fish",
            [
                "fish", "shark", "stingray", "manta", "eel", "trout", "salmon",
                "ray", "perciformes", "salmonidae", "salmo", "oncorhynchus"
            ]
        )
    ]

    private static func normalize(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
