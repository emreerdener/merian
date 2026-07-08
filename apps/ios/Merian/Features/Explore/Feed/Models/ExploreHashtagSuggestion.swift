import Foundation

struct ExploreHashtagSuggestionContext: Equatable {
    var speciesName: String
    var scientificName: String
    var publicLocationLabel: String?
    var fieldNotes: String?
    var ecologyType: String?
    var taxonomyKingdom: String?
    var taxonomyClass: String?
    var taxonomyOrder: String?
    var taxonomyFamily: String?
    var habitatDescription: String?
    var weatherCondition: String?
    var colors: [String]
    var groupTags: [String]
    var semanticTags: [String]
    var isInvasive: Bool
    var imageQualityScore: Int?
    var lifeStage: String?
    var reproductiveCondition: String?
    var ecologicalInteractions: [String]
    var eventHashtags: [String]

    init(
        speciesName: String,
        scientificName: String,
        publicLocationLabel: String?,
        fieldNotes: String?,
        ecologyType: String? = nil,
        taxonomyKingdom: String? = nil,
        taxonomyClass: String? = nil,
        taxonomyOrder: String? = nil,
        taxonomyFamily: String? = nil,
        habitatDescription: String? = nil,
        weatherCondition: String? = nil,
        colors: [String] = [],
        groupTags: [String] = [],
        semanticTags: [String] = [],
        isInvasive: Bool = false,
        imageQualityScore: Int? = nil,
        lifeStage: String? = nil,
        reproductiveCondition: String? = nil,
        ecologicalInteractions: [String] = [],
        eventHashtags: [String] = []
    ) {
        self.speciesName = speciesName
        self.scientificName = scientificName
        self.publicLocationLabel = publicLocationLabel
        self.fieldNotes = fieldNotes
        self.ecologyType = ecologyType
        self.taxonomyKingdom = taxonomyKingdom
        self.taxonomyClass = taxonomyClass
        self.taxonomyOrder = taxonomyOrder
        self.taxonomyFamily = taxonomyFamily
        self.habitatDescription = habitatDescription
        self.weatherCondition = weatherCondition
        self.colors = colors
        self.groupTags = groupTags
        self.semanticTags = semanticTags
        self.isInvasive = isInvasive
        self.imageQualityScore = imageQualityScore
        self.lifeStage = lifeStage
        self.reproductiveCondition = reproductiveCondition
        self.ecologicalInteractions = ecologicalInteractions
        self.eventHashtags = eventHashtags
    }

    func updating(fieldNotes: String?) -> ExploreHashtagSuggestionContext {
        var copy = self
        copy.fieldNotes = fieldNotes
        return copy
    }

    func updating(eventHashtags additionalEventHashtags: [String]) -> ExploreHashtagSuggestionContext {
        var copy = self
        var seen = Set(copy.eventHashtags.compactMap { ExploreHashtagSuggestionEngine.normalizedTag(from: $0) })
        for hashtag in additionalEventHashtags {
            guard let normalized = ExploreHashtagSuggestionEngine.normalizedTag(from: hashtag),
                  seen.insert(normalized).inserted else {
                continue
            }
            copy.eventHashtags.append(normalized)
        }
        return copy
    }
}

enum ExploreHashtagSuggestionEngine {
    private struct Candidate {
        let tag: String
        let score: Int
        let order: Int
    }

    private struct KeywordTag {
        let terms: [String]
        let tag: String
        let score: Int
    }

    private static let maximumSuggestions = 8
    private static let maximumPublishedHashtags = 5
    private static let minimumTagLength = 2
    private static let maximumTagLength = 40

    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "but", "by", "for", "from",
        "in", "into", "is", "it", "near", "of", "on", "or", "the", "to",
        "under", "with"
    ]

    private static let reservedTags: Set<String> = [
        "featured"
    ]

    private static let keywordTags: [KeywordTag] = [
        KeywordTag(terms: ["bio blitz", "bioblitz"], tag: "bioblitz", score: 98),
        KeywordTag(terms: ["bio blitz", "bioblitz"], tag: "citybioblitz", score: 96),
        KeywordTag(terms: ["pollinator", "pollinators", "bee", "butterfly", "bloom", "flower"], tag: "pollinators", score: 78),
        KeywordTag(terms: ["creek", "stream", "river", "shore", "water"], tag: "freshwater", score: 76),
        KeywordTag(terms: ["creek", "stream"], tag: "creeklife", score: 70),
        KeywordTag(terms: ["pond", "lake"], tag: "pondlife", score: 70),
        KeywordTag(terms: ["wetland", "marsh", "swamp"], tag: "wetlands", score: 70),
        KeywordTag(terms: ["underwater", "aquatic"], tag: "aquaticlife", score: 68),
        KeywordTag(terms: ["nest", "nesting"], tag: "nesting", score: 68),
        KeywordTag(terms: ["juvenile", "young", "larva", "larvae"], tag: "juvenile", score: 66),
        KeywordTag(terms: ["feeding", "foraging", "eating"], tag: "foraging", score: 64),
        KeywordTag(terms: ["night", "nocturnal", "dusk"], tag: "nightfind", score: 62),
        KeywordTag(terms: ["school", "schooling"], tag: "schoolingfish", score: 62),
        KeywordTag(terms: ["native"], tag: "nativewildlife", score: 58),
        KeywordTag(terms: ["invasive"], tag: "invasive", score: 58)
    ]

    static func suggestions(
        for context: ExploreHashtagSuggestionContext,
        selectedHashtags: [String] = []
    ) -> [String] {
        let selected = Set(selectedHashtags.compactMap { normalizedTag(from: $0) })
        let remainingSlots = max(0, maximumPublishedHashtags - selected.count)
        guard remainingSlots > 0 else { return [] }

        var candidates: [Candidate] = []
        var order = 0

        func add(_ rawValue: String?, score: Int) {
            guard let tag = normalizedTag(from: rawValue), !reservedTags.contains(tag) else { return }
            candidates.append(Candidate(tag: tag, score: score, order: order))
            order += 1
        }

        for eventTag in context.eventHashtags {
            add(eventTag, score: 110)
        }

        add(context.speciesName, score: 100)
        for namePart in meaningfulWords(in: context.speciesName).prefix(2) {
            add(namePart, score: 52)
        }

        let scientificWords = meaningfulWords(in: context.scientificName)
        if let genus = scientificWords.first {
            add(genus, score: 74)
        }

        for tag in groupTags(for: context) {
            add(tag, score: 72)
        }

        for sourceTag in context.groupTags + context.semanticTags {
            add(sourceTag, score: 56)
        }

        for color in context.colors.prefix(2) {
            add(color, score: 46)
        }

        if context.isInvasive {
            add("invasive", score: 80)
        }

        if context.imageQualityScore ?? 0 >= 85 {
            add("fieldguide", score: 48)
        }

        if let publicLocationLabel = context.publicLocationLabel {
            add("localwildlife", score: 64)
            add("localnature", score: 60)
            add(locationTag(from: publicLocationLabel), score: 84)
        }

        let keywordText = [
            context.fieldNotes,
            context.habitatDescription,
            context.weatherCondition,
            context.lifeStage,
            context.reproductiveCondition,
            context.ecologicalInteractions.joined(separator: " ")
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        for keywordTag in keywordTags where keywordTag.terms.contains(where: { keywordText.contains($0) }) {
            add(keywordTag.tag, score: keywordTag.score)
        }

        if keywordText.contains("rain") {
            add("afterrain", score: 58)
        }

        var bestByTag: [String: Candidate] = [:]
        for candidate in candidates where !selected.contains(candidate.tag) {
            guard candidate.tag.count >= minimumTagLength, candidate.tag.count <= maximumTagLength else { continue }
            if let existing = bestByTag[candidate.tag] {
                if candidate.score > existing.score || (candidate.score == existing.score && candidate.order < existing.order) {
                    bestByTag[candidate.tag] = candidate
                }
            } else {
                bestByTag[candidate.tag] = candidate
            }
        }

        return bestByTag.values
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.order < rhs.order : lhs.score > rhs.score
            }
            .prefix(min(maximumSuggestions, remainingSlots + 3))
            .map(\.tag)
    }

    static func normalizedInputTags(from text: String, limit: Int = maximumPublishedHashtags) -> [String] {
        var tags: [String] = []
        var seen = Set<String>()
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))

        for token in text.components(separatedBy: separators) {
            guard let cleaned = normalizedTag(from: token), seen.insert(cleaned).inserted else { continue }
            tags.append(cleaned)
            if tags.count == limit { break }
        }

        return tags
    }

    static func normalizedTag(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }

        let folded = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        guard !folded.isEmpty else { return nil }

        var scalars: [UnicodeScalar] = []
        var previousWasUnderscore = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
                previousWasUnderscore = false
            } else if scalar == "_", !previousWasUnderscore, !scalars.isEmpty {
                scalars.append(scalar)
                previousWasUnderscore = true
            }
        }

        while scalars.last == UnicodeScalar("_") {
            scalars.removeLast()
        }

        let tag = String(String.UnicodeScalarView(scalars))
        guard tag.count >= minimumTagLength, tag.count <= maximumTagLength else { return nil }
        guard !stopWords.contains(tag), !reservedTags.contains(tag) else { return nil }

        return tag
    }

    private static func meaningfulWords(in value: String) -> [String] {
        value
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .compactMap { normalizedTag(from: $0) }
            .filter { !stopWords.contains($0) }
    }

    private static func groupTags(for context: ExploreHashtagSuggestionContext) -> [String] {
        let className = context.taxonomyClass?.lowercased()
        let kingdom = context.taxonomyKingdom?.lowercased()
        let ecologyType = context.ecologyType?.lowercased()
        let searchableText = [
            context.speciesName,
            context.scientificName,
            context.taxonomyClass,
            context.taxonomyOrder,
            context.taxonomyFamily,
            context.habitatDescription,
            context.groupTags.joined(separator: " ")
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if ["actinopterygii", "chondrichthyes", "sarcopterygii"].contains(className)
            || searchableText.contains("fish") {
            return ecologyType?.contains("fresh") == true || searchableText.contains("freshwater")
                ? ["freshwaterfish", "fish", "aquaticlife"]
                : ["fish", "aquaticlife"]
        }

        switch className {
        case "aves":
            return ["birding", "birds"]
        case "mammalia":
            return ["mammals", "wildlife"]
        case "insecta", "entognatha":
            return ["insects", "bugs"]
        case "arachnida":
            return ["arachnids", "spiders"]
        case "reptilia", "squamata":
            return ["reptiles", "herping"]
        case "amphibia":
            return ["amphibians", "herping"]
        default:
            if kingdom == "plantae" {
                return ["plants", "botany"]
            }
            if kingdom == "fungi" {
                return ["fungi", "mycology"]
            }
            return ["biodiversity", "communityscience"]
        }
    }

    private static func locationTag(from label: String) -> String? {
        let parts = label
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }

        if parts.count >= 2 {
            return normalizedTag(from: parts.prefix(2).joined())
        }

        return normalizedTag(from: "\(parts[0]) nature")
    }
}
