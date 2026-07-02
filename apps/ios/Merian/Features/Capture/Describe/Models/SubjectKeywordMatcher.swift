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
            scientificName: record.scientificName,
            additionalSearchFields: record.semanticTags
        )
    }

    static func subjectId(
        taxonomy: TaxonomyData?,
        commonName: String?,
        scientificName: String?,
        additionalSearchFields: [String] = []
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
        ] + additionalSearchFields)
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
                "bird", "birds", "avian", "sparrow", "finch", "cardinal", "hawk",
                "eagle", "robin", "pigeon", "dove", "duck", "goose", "owl",
                "warbler", "heron", "jay", "crow", "raven", "gull", "passeriformes",
                "anatidae", "corvidae"
            ]
        ),
        (
            "subj_insec",
            [
                "insect", "insects", "beetle", "butterfly", "moth", "bee",
                "wasp", "fly", "dragonfly", "damselfly", "ant", "bug", "cicada",
                "cricket", "grasshopper", "lepidoptera", "coleoptera", "diptera",
                "hymenoptera", "odonata", "danaus"
            ]
        ),
        (
            "subj_spid",
            [
                "spider", "spiders", "arachnid", "arachnids", "tarantula", "scorpion", "tick", "mite",
                "araneae", "salticidae", "lycosidae"
            ]
        ),
        (
            "subj_rept",
            [
                "reptile", "reptiles", "amphibian", "amphibians", "snake",
                "lizard", "turtle", "tortoise", "frog", "toad", "salamander", "newt", "squamata", "anura",
                "caudata", "testudines"
            ]
        ),
        (
            "subj_plan",
            [
                "plant", "plants", "tree", "flower", "wildflower", "shrub",
                "bush", "houseplant", "houseplants", "potted", "fern", "moss",
                "grass", "weed", "leaf", "leaves", "succulent", "succulents",
                "cactus", "cacti", "oak", "quercus", "rosa", "rosaceae",
                "poaceae", "asteraceae", "pinus", "acer", "monstera",
                "philodendron", "pothos", "dracaena", "sansevieria", "ficus",
                "spathiphyllum", "chlorophytum", "zamioculcas", "peperomia",
                "aglaonema", "crassula", "aloe", "epipremnum", "schefflera",
                "dieffenbachia", "calathea", "maranta", "pilea", "hoya",
                "begonia", "ivy"
            ]
        ),
        (
            "subj_mush",
            [
                "mushroom", "mushrooms", "fungus", "fungi", "fungal", "toadstool",
                "puffball", "lichen", "amanita", "boletus", "agaricus", "polyporales"
            ]
        ),
        (
            "subj_mamm",
            [
                "mammal", "mammals", "rodent", "squirrel", "rabbit", "hare", "raccoon",
                "skunk", "opossum", "mouse", "rat", "bat", "fox", "deer",
                "rodentia", "sciuridae", "canidae", "cervidae"
            ]
        ),
        (
            "subj_fish",
            [
                "fish", "fishes", "shark", "stingray", "manta", "eel", "trout", "salmon",
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
