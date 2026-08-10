import Foundation

// MARK: - Capture Telemetry

/// Sensor and environment state captured at the moment of shutter press.
/// Passed to both the live inference path and the offline queue.
struct CaptureTelemetry: Sendable {
    let subjectDistanceInMeters: Float?
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let gpsElevation: Double?
    let locationName: String?
    let weatherCondition: String?
    let weatherTemperatureF: Double?
    let timeOfDay: String?
    let timestamp: String?
    /// Active zoom factor at shutter press. Nil when 1× (adds no signal).
    /// Omitted from offline-queue retries since zoom is not persisted in the schema.
    var zoomFactor: CGFloat?
    var estimatedSizeCm: Double?
}

// MARK: - Convenience Initializers

extension CaptureTelemetry {
    @MainActor
    init(from inferenceEngine: InferenceEngine) {
        self.init(
            subjectDistanceInMeters: inferenceEngine.activeDistanceInMeters,
            gpsLatitude: inferenceEngine.activeLatitude,
            gpsLongitude: inferenceEngine.activeLongitude,
            gpsElevation: inferenceEngine.activeElevation,
            locationName: inferenceEngine.activeLocationName,
            weatherCondition: inferenceEngine.activeWeatherCondition,
            weatherTemperatureF: inferenceEngine.activeTemperatureF,
            timeOfDay: nil,
            timestamp: DateUtilities.iso8601Formatter.string(from: Date()),
            estimatedSizeCm: nil
        )
    }

    init(
        from context: EnvironmentContext,
        distance: Float?,
        zoom: CGFloat? = nil,
        estimatedSizeCm: Double? = nil,
        requiresExplicitCaptureDate: Bool = false
    ) {
        let reliableElevation: Double? = context.location.flatMap { loc in
            (loc.verticalAccuracy >= 0 && loc.verticalAccuracy <= 25) ? loc.altitude : nil
        }
        let timestampDate = requiresExplicitCaptureDate
            ? context.captureDate
            : context.captureDate ?? context.location?.timestamp ?? Date()

        var t = CaptureTelemetry(
            subjectDistanceInMeters: distance,
            gpsLatitude: context.location?.coordinate.latitude,
            gpsLongitude: context.location?.coordinate.longitude,
            gpsElevation: reliableElevation,
            locationName: context.locationName,
            weatherCondition: context.weatherCondition,
            weatherTemperatureF: context.weatherTemperature,
            timeOfDay: nil,
            timestamp: timestampDate.map { DateUtilities.iso8601Formatter.string(from: $0) },
            estimatedSizeCm: estimatedSizeCm
        )
        t.zoomFactor = zoom
        self = t
    }
}

// MARK: - Species Data

struct PetIdentification: Codable, Equatable, Hashable, Sendable {
    let speciesGroup: String
    let label: String
    let labelType: String
    let confidenceScore: Double
    let evidence: [String]

    private enum CodingKeys: String, CodingKey {
        case speciesGroup
        case label
        case labelType
        case confidenceScore
        case evidence
    }

    private enum SnakeCodingKeys: String, CodingKey {
        case speciesGroup = "species_group"
        case label
        case labelType = "label_type"
        case confidenceScore = "confidence_score"
        case evidence
    }

    init(
        speciesGroup: String,
        label: String,
        labelType: String,
        confidenceScore: Double,
        evidence: [String]
    ) {
        self.speciesGroup = speciesGroup
        self.label = label
        self.labelType = labelType
        self.confidenceScore = confidenceScore
        self.evidence = evidence
    }

    init(from decoder: Decoder) throws {
        let camelContainer = try decoder.container(keyedBy: CodingKeys.self)
        let snakeContainer = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.speciesGroup = try camelContainer.decodeIfPresent(String.self, forKey: .speciesGroup)
            ?? snakeContainer.decode(String.self, forKey: .speciesGroup)
        self.label = try camelContainer.decode(String.self, forKey: .label)
        self.labelType = try camelContainer.decodeIfPresent(String.self, forKey: .labelType)
            ?? snakeContainer.decode(String.self, forKey: .labelType)
        self.confidenceScore = try camelContainer.decodeIfPresent(Double.self, forKey: .confidenceScore)
            ?? snakeContainer.decode(Double.self, forKey: .confidenceScore)
        self.evidence = try camelContainer.decodeIfPresent([String].self, forKey: .evidence)
            ?? snakeContainer.decode([String].self, forKey: .evidence)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SnakeCodingKeys.self)
        try container.encode(speciesGroup, forKey: .speciesGroup)
        try container.encode(label, forKey: .label)
        try container.encode(labelType, forKey: .labelType)
        try container.encode(confidenceScore, forKey: .confidenceScore)
        try container.encode(evidence, forKey: .evidence)
    }

    var isDisplayable: Bool {
        confidenceScore >= 0.70 && !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Parsed result from the AI edge function, representing a single identified biological observation.
struct SpeciesData {
    let scanId: String?
    var commonName: String
    var scientificName: String
    var insightData: InsightData
    let confidenceScore: Double
    /// Gemini's self-reported image sharpness score (0 = sharp, 1 = very blurry).
    /// Populated from live inference only — nil when loading from local SwiftData records.
    let blurScore: Double?
    var similarSpecies: SimilarSpecies?
    var wikipediaUrl: String?
    /// Wikipedia summary paragraph cached from the Wikipedia REST API.
    var wikipediaOverview: String?
    var referenceImageUrl: String?

    let isBiological: Bool
    let isLiveCapture: Bool
    let isInvasive: Bool
    let invasiveStatusRegion: String?
    let invasiveRationale: String?
    let invasiveConfidence: Double?
    let ecologyType: String
    var taxonomy: TaxonomyData?
    var isNewDiscovery: Bool = false
    var isNewToMerianDictionary: Bool = false

    // Context metadata from the scan session.
    var locationName: String?
    var weatherCondition: String?
    var weatherTemperatureF: Double?
    var gpsElevation: Double?
    var gpsLatitude: Double?
    var gpsLongitude: Double?
    var colors: [String]?
    var groupTags: [String]?
    var iucnRedListStatus: String?
    var zoomFactor: Double?
    
    // Extended Ecological Telemetry
    var estimatedSizeCm: Double?
    var lifeStage: String?
    var reproductiveCondition: String?
    var sex: String?
    var sexConfidence: Double?
    var sexEvidence: String?
    var individualCount: Int?
    var ecologicalInteractions: [String]?

    // Species Insights
    var aiReasoning: String?
    var habitatDescription: String?
    var gbifTaxonKey: Int?
    var inferenceTier: String?

    /// All known English vernacular synonyms beyond `commonName`.
    /// Sourced from GBIF vernacular names on first enrichment; served from the
    /// species_dictionary cache on subsequent cache hits. Do not use absence as a
    /// novelty signal; use `isNewToMerianDictionary`.
    var alternativeCommonNames: [String]?
    var petIdentification: PetIdentification?

    /// Per-scan alternative candidates the model considered when confidence was below the
    /// tier-specific `MerianConfig.diagnosticTrigger` threshold. Nil for confident scans.
    var candidates: [IdentificationCandidate]?

    /// Gemini's photographic quality score (0–100) for the submitted image.
    /// Derived from `image_quality.overall_score` in the edge response.
    /// Persisted to `LocalScanRecord.imageQualityScore` and `public.scans.image_quality_score`
    /// for future community reference-photo curation. Nil for scans captured before V30.
    let imageQualityScore: Int?

    /// The AI's original scientific name — never mutated after init.
    /// Preserved so CandidatesCard can show "AI originally suggested X" when override is active.
    let aiScientificName: String

    /// Scientific name chosen by the user when they disagreed with the AI. Nil = no action taken.
    var userIdentificationOverride: String?

    /// True when user tapped "Yes, correct" — suppresses the "Was the AI correct?" prompt locally.
    var userConfirmedIdentification: Bool

    /// True when the user flagged the AI's identification for manual review.
    var isFlagged: Bool

    /// True when the user swiped through all alternative candidates without making a selection.
    var alternativesExhausted: Bool = false

    var audioFilePaths: [String]?
    var videoFilePaths: [String]?
}

// MARK: - Subject Classification

enum ReferenceImageVisibilityPolicy {
    static func shouldSuppress(
        isHumanSubject: Bool,
        scientificName: String
    ) -> Bool {
        if isHumanSubject { return true }

        let normalizedScientificName = scientificName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedScientificName == "felis catus"
            || normalizedScientificName == "canis lupus familiaris"
    }
}

extension SpeciesData {
    /// True for local, non-persisted inference fallback rows such as network timeouts.
    /// These placeholders use `isBiological == false` only to avoid biological result UI;
    /// they are not model classifications and should not be treated as non-biological scans.
    var isInferenceErrorPlaceholder: Bool {
        guard scanId == nil else { return false }
        let normalizedCommonName = commonName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedCommonName == "network timeout"
            || normalizedCommonName == "analysis failed"
            || normalizedCommonName == "analysis delayed"
            || normalizedCommonName == "restoring scan"
            || normalizedCommonName == "approval needed"
            || normalizedCommonName == "upgrade needed"
            || normalizedCommonName == "daily limit reached"
            || normalizedCommonName == "retrying shortly"
            || normalizedCommonName == "try another capture"
    }

    var isClassifiedNonBiological: Bool {
        !isBiological && !isInferenceErrorPlaceholder
    }

    /// True when the AI identified the subject as a human.
    /// Used to suppress candidates and third-party reference images (Wikipedia/GBIF)
    /// which are inappropriate to surface for human subjects.
    /// Checks both common and scientific name so either field alone is sufficient.
    var isHumanSubject: Bool {
        commonName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "human"
            || scientificName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "homo sapiens"
    }

    /// Third-party reference photos are not shown for people, domestic cats, or
    /// domestic dogs. Wild felids and canids retain their reference galleries.
    var shouldSuppressReferenceImages: Bool {
        ReferenceImageVisibilityPolicy.shouldSuppress(
            isHumanSubject: isHumanSubject,
            scientificName: scientificName
        )
    }
}

// MARK: - Sanitization Helpers

extension SpeciesData {
    /// Sanitizes an incoming array of alternative common names by splitting any comma-separated
    /// strings into individual names, stripping whitespace, and deduplicating.
    static func sanitizeAlternativeNames(_ names: [String]?) -> [String]? {
        guard let names = names else { return nil }
        let sanitized = names
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        // Deduplicate while preserving order if possible (Set doesn't, but an Array filter with Set can)
        var seen = Set<String>()
        let unique = sanitized.filter { seen.insert($0.lowercased()).inserted }
        return unique.isEmpty ? nil : unique
    }
}

// MARK: - Edge Response Init

extension SpeciesData {
    /// Initializes from an `EdgeResponse` returned by the AI edge function.
    init(
        fromEdgeResponse edgeRes: EdgeResponse,
        locationName: String?,
        weatherCondition: String?,
        weatherTemperatureF: Double?,
        gpsElevation: Double? = nil,
        gpsLatitude: Double? = nil,
        gpsLongitude: Double? = nil
    ) {
        let insight = InsightData(
            aiReasoning: edgeRes.insight_data?.ai_reasoning ?? "",
            hazardType: edgeRes.insight_data?.hazard_type ?? "none"
        )

        let taxonomyData = TaxonomyData(
            kingdom: edgeRes.taxonomy?.kingdom,
            phylum: edgeRes.taxonomy?.phylum,
            className: edgeRes.taxonomy?.class,
            order: edgeRes.taxonomy?.order,
            family: edgeRes.taxonomy?.family,
            genus: edgeRes.taxonomy?.genus
        )

        self.scanId = edgeRes.scan_id
        
        let primaryRawNames = edgeRes.common_name?.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        self.commonName = primaryRawNames?.first ?? "Unknown Subject"
        self.scientificName = edgeRes.scientific_name ?? "Taxonomy Unavailable"
        self.insightData = insight
        self.confidenceScore = edgeRes.confidence_score ?? 0.0
        self.blurScore = edgeRes.blur_score
        self.similarSpecies = nil  // populated async via enrich-scan
        self.wikipediaUrl = edgeRes.wikipedia_url
        self.wikipediaOverview = edgeRes.wikipedia_overview
        self.referenceImageUrl = ExternalReferenceImagePolicy.sanitizedURLList(
            edgeRes.reference_image_url
        )
        self.isBiological = edgeRes.is_biological_subject ?? true
        self.isLiveCapture = edgeRes.is_live_capture ?? true
        self.isInvasive = edgeRes.is_invasive ?? false
        self.invasiveStatusRegion = edgeRes.invasive_status_region
        self.invasiveRationale = edgeRes.invasive_rationale
        self.invasiveConfidence = edgeRes.invasive_confidence
        self.ecologyType = edgeRes.ecology_type ?? "unknown"
        self.taxonomy = taxonomyData
        self.isNewToMerianDictionary = isBiological ? (edgeRes.is_new_to_merian_dictionary ?? false) : false
        self.locationName = locationName
        self.weatherCondition = weatherCondition
        self.weatherTemperatureF = weatherTemperatureF
        self.gpsElevation = gpsElevation
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.colors = edgeRes.colors
        self.groupTags = edgeRes.group_tags
        self.iucnRedListStatus = edgeRes.iucn_red_list_status
        self.zoomFactor = nil  // populated by the caller from CaptureTelemetry
        self.estimatedSizeCm = edgeRes.estimated_size_cm
        self.lifeStage = edgeRes.life_stage
        self.reproductiveCondition = edgeRes.reproductive_condition
        self.sex = edgeRes.sex
        self.sexConfidence = edgeRes.sex_confidence
        self.sexEvidence = edgeRes.sex_evidence
        self.individualCount = edgeRes.individual_count
        self.ecologicalInteractions = edgeRes.ecological_interactions
        self.aiReasoning = edgeRes.insight_data?.ai_reasoning  // per-scan; unique to the specific photo submitted
        self.habitatDescription = edgeRes.species_insights?.habitat_description
        self.gbifTaxonKey = edgeRes.gbif_taxon_key
        self.inferenceTier = edgeRes.inference_tier
        self.alternativeCommonNames = SpeciesData.sanitizeAlternativeNames(edgeRes.alternative_common_names)
        if let petDTO = edgeRes.pet_identification {
            let petIdentification = PetIdentification(
                speciesGroup: petDTO.speciesGroup,
                label: petDTO.label,
                labelType: petDTO.labelType,
                confidenceScore: petDTO.confidenceScore,
                evidence: petDTO.evidence
            )
            self.petIdentification = petIdentification.isDisplayable ? petIdentification : nil
        } else {
            self.petIdentification = nil
        }
        self.candidates = isBiological ? edgeRes.candidates.map { entries in
            entries.map { 
                let splitCandidateCommon = $0.common_name?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                return IdentificationCandidate(scientificName: $0.scientific_name, commonName: splitCandidateCommon, confidenceScore: $0.confidence_score, distinguishingFeature: $0.distinguishing_feature) 
            }
        } : nil
        self.imageQualityScore = edgeRes.image_quality?.overall_score
        self.aiScientificName = edgeRes.scientific_name ?? "Taxonomy Unavailable"
        self.userIdentificationOverride = nil
        self.userConfirmedIdentification = false
        self.isFlagged = false
        self.alternativesExhausted = false
        self.audioFilePaths = nil // Set by InferenceEngine or InferenceProcessingActor
        self.videoFilePaths = nil
    }
}

// MARK: - Memberwise Init

extension SpeciesData {
    /// Full memberwise initializer, used for local construction and offline mocking.
    init(
        scanId: String? = nil,
        commonName: String,
        scientificName: String,
        insightData: InsightData,
        confidenceScore: Double,
        blurScore: Double? = nil,
        similarSpecies: SimilarSpecies? = nil,
        wikipediaUrl: String? = nil,
        wikipediaOverview: String? = nil,
        referenceImageUrl: String? = nil,
        isBiological: Bool = true,
        isLiveCapture: Bool = true,
        isInvasive: Bool = false,
        invasiveStatusRegion: String? = nil,
        invasiveRationale: String? = nil,
        invasiveConfidence: Double? = nil,
        ecologyType: String = "unknown",
        taxonomy: TaxonomyData? = nil,
        isNewToMerianDictionary: Bool = false,
        locationName: String? = nil,
        weatherCondition: String? = nil,
        weatherTemperatureF: Double? = nil,
        gpsElevation: Double? = nil,
        gpsLatitude: Double? = nil,
        gpsLongitude: Double? = nil,
        colors: [String]? = nil,
        groupTags: [String]? = nil,
        iucnRedListStatus: String? = nil,
        zoomFactor: Double? = nil,
        estimatedSizeCm: Double? = nil,
        lifeStage: String? = nil,
        reproductiveCondition: String? = nil,
        sex: String? = nil,
        sexConfidence: Double? = nil,
        sexEvidence: String? = nil,
        individualCount: Int? = nil,
        ecologicalInteractions: [String]? = nil,
        aiReasoning: String? = nil,
        habitatDescription: String? = nil,
        gbifTaxonKey: Int? = nil,
        inferenceTier: String? = nil,
        alternativeCommonNames: [String]? = nil,
        petIdentification: PetIdentification? = nil,
        candidates: [IdentificationCandidate]? = nil,
        imageQualityScore: Int? = nil,
        aiScientificName: String = "",
        userIdentificationOverride: String? = nil,
        userConfirmedIdentification: Bool = false,
        isFlagged: Bool = false,
        alternativesExhausted: Bool = false,
        audioFilePaths: [String]? = nil,
        videoFilePaths: [String]? = nil
    ) {
        self.scanId = scanId
        self.commonName = commonName
        self.scientificName = scientificName
        self.insightData = insightData
        self.confidenceScore = confidenceScore
        self.blurScore = blurScore
        self.similarSpecies = similarSpecies
        self.wikipediaUrl = wikipediaUrl
        self.wikipediaOverview = wikipediaOverview
        self.referenceImageUrl = ExternalReferenceImagePolicy.sanitizedURLList(referenceImageUrl)
        self.isBiological = isBiological
        self.isLiveCapture = isLiveCapture
        self.isInvasive = isInvasive
        self.invasiveStatusRegion = invasiveStatusRegion
        self.invasiveRationale = invasiveRationale
        self.invasiveConfidence = invasiveConfidence
        self.ecologyType = ecologyType
        self.taxonomy = taxonomy
        self.isNewToMerianDictionary = isNewToMerianDictionary
        self.locationName = locationName
        self.weatherCondition = weatherCondition
        self.weatherTemperatureF = weatherTemperatureF
        self.gpsElevation = gpsElevation
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.colors = colors
        self.groupTags = groupTags
        self.iucnRedListStatus = iucnRedListStatus
        self.zoomFactor = zoomFactor
        self.estimatedSizeCm = estimatedSizeCm
        self.lifeStage = lifeStage
        self.reproductiveCondition = reproductiveCondition
        self.sex = sex
        self.sexConfidence = sexConfidence
        self.sexEvidence = sexEvidence
        self.individualCount = individualCount
        self.ecologicalInteractions = ecologicalInteractions
        self.aiReasoning = aiReasoning
        self.habitatDescription = habitatDescription
        self.gbifTaxonKey = gbifTaxonKey
        self.inferenceTier = inferenceTier
        self.alternativeCommonNames = SpeciesData.sanitizeAlternativeNames(alternativeCommonNames)
        self.petIdentification = petIdentification?.isDisplayable == true ? petIdentification : nil
        self.candidates = candidates
        self.imageQualityScore = imageQualityScore
        self.aiScientificName = aiScientificName.isEmpty ? scientificName : aiScientificName
        self.userIdentificationOverride = userIdentificationOverride
        self.userConfirmedIdentification = userConfirmedIdentification
        self.isFlagged = isFlagged
        self.alternativesExhausted = alternativesExhausted
        self.audioFilePaths = audioFilePaths
        self.videoFilePaths = videoFilePaths
    }
}

// MARK: - Supporting Types

struct TaxonomyData {
    let kingdom: String?
    let phylum: String?
    let className: String?
    let order: String?
    let family: String?
    let genus: String?
}

extension TaxonomyData {
    static func normalizeComponent(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.caseInsensitiveCompare("unknown") != .orderedSame else {
            return nil
        }
        return trimmed
    }

    var hasUsableLookalikeValidation: Bool {
        Self.normalizeComponent(kingdom) != nil &&
        (Self.normalizeComponent(order) != nil || Self.normalizeComponent(family) != nil)
    }
}

struct InsightData {
    /// Per-scan AI vision reasoning — unique to the specific photo submitted.
    let aiReasoning: String
    /// AI-classified hazard type. One of: `"none"` | `"poisonous"` | `"venomous"` | `"allergenic"` | `"irritant"`.
    let hazardType: String
    var isHazardous: Bool { hazardType != "none" }
}

struct SimilarSpeciesEntry: Codable {
    let speciesId: String?
    let scientificName: String
    let commonName: String?
    let referenceImageUrl: String?
    let iucnRedListStatus: String?
    let similarityReason: String?
    let visualTraits: [String]
    let similarityConfidence: Double?
    let relationshipSource: String?
    let reviewStatus: String?
    let isBidirectional: Bool?
    let sortOrder: Int?

    init(
        scientificName: String,
        commonName: String?,
        referenceImageUrl: String?,
        iucnRedListStatus: String?,
        speciesId: String? = nil,
        similarityReason: String? = nil,
        visualTraits: [String] = [],
        similarityConfidence: Double? = nil,
        relationshipSource: String? = nil,
        reviewStatus: String? = nil,
        isBidirectional: Bool? = nil,
        sortOrder: Int? = nil
    ) {
        self.speciesId = speciesId
        self.scientificName = scientificName
        self.commonName = commonName
        self.referenceImageUrl = ExternalReferenceImagePolicy.sanitizedURL(referenceImageUrl)
        self.iucnRedListStatus = iucnRedListStatus
        self.similarityReason = similarityReason
        self.visualTraits = visualTraits
        self.similarityConfidence = similarityConfidence
        self.relationshipSource = relationshipSource
        self.reviewStatus = reviewStatus
        self.isBidirectional = isBidirectional
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case speciesId
        case scientificName
        case commonName
        case referenceImageUrl
        case iucnRedListStatus
        case similarityReason = "reason"
        case visualTraits
        case similarityConfidence = "confidence"
        case relationshipSource = "source"
        case reviewStatus
        case isBidirectional
        case sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speciesId = try container.decodeIfPresent(String.self, forKey: .speciesId)
        scientificName = try container.decode(String.self, forKey: .scientificName)
        commonName = try container.decodeIfPresent(String.self, forKey: .commonName)
        referenceImageUrl = ExternalReferenceImagePolicy.sanitizedURL(
            try container.decodeIfPresent(String.self, forKey: .referenceImageUrl)
        )
        iucnRedListStatus = try container.decodeIfPresent(String.self, forKey: .iucnRedListStatus)
        similarityReason = try container.decodeIfPresent(String.self, forKey: .similarityReason)
        visualTraits = try container.decodeIfPresent([String].self, forKey: .visualTraits) ?? []
        similarityConfidence = try container.decodeIfPresent(Double.self, forKey: .similarityConfidence)
        relationshipSource = try container.decodeIfPresent(String.self, forKey: .relationshipSource)
        reviewStatus = try container.decodeIfPresent(String.self, forKey: .reviewStatus)
        isBidirectional = try container.decodeIfPresent(Bool.self, forKey: .isBidirectional)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(speciesId, forKey: .speciesId)
        try container.encode(scientificName, forKey: .scientificName)
        try container.encodeIfPresent(commonName, forKey: .commonName)
        try container.encodeIfPresent(referenceImageUrl, forKey: .referenceImageUrl)
        try container.encodeIfPresent(iucnRedListStatus, forKey: .iucnRedListStatus)
        try container.encodeIfPresent(similarityReason, forKey: .similarityReason)
        if !visualTraits.isEmpty {
            try container.encode(visualTraits, forKey: .visualTraits)
        }
        try container.encodeIfPresent(similarityConfidence, forKey: .similarityConfidence)
        try container.encodeIfPresent(relationshipSource, forKey: .relationshipSource)
        try container.encodeIfPresent(reviewStatus, forKey: .reviewStatus)
        try container.encodeIfPresent(isBidirectional, forKey: .isBidirectional)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
    }

    static func normalizeScientificName(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    func displayCommonName(comparedTo currentCommonName: String?) -> String? {
        guard let commonName = commonName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !commonName.isEmpty else {
            return nil
        }

        let currentCommon = currentCommonName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard commonName.caseInsensitiveCompare(currentCommon) != .orderedSame else {
            return nil
        }
        return commonName
    }

}

struct SimilarSpecies {
    let entries: [SimilarSpeciesEntry]

    /// Backwards-compatible accessor returning the flat array of scientific names.
    var lookalikes: [String] { entries.map(\.scientificName) }

    func filteredEntries(excludingScientificName scientificName: String?, excludingCommonName: String? = nil) -> [SimilarSpeciesEntry] {
        let excludedScientificName = SimilarSpeciesEntry.normalizeScientificName(scientificName)
        let excludedCommonName = excludingCommonName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        var seenScientificNames = Set<String>()

        return entries.compactMap { entry in
            let normalizedScientificName = SimilarSpeciesEntry.normalizeScientificName(entry.scientificName)
            guard !normalizedScientificName.isEmpty else { return nil }
            guard normalizedScientificName != excludedScientificName else { return nil }
            
            if let excludedCommonName = excludedCommonName,
               let entryCommon = entry.commonName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !entryCommon.isEmpty,
               entryCommon == excludedCommonName {
                return nil
            }
            
            guard seenScientificNames.insert(normalizedScientificName).inserted else { return nil }
            return entry
        }
    }
}

/// A single alternative species the model actively considered during identification.
/// Scan-specific — reflects genuine uncertainty for this image, not a fixed species-level list.
struct IdentificationCandidate: Codable {
    let scientificName: String
    let commonName: String?
    let confidenceScore: Double
    /// The single most important observable trait separating this candidate from the primary ID.
    let distinguishingFeature: String?

    init(scientificName: String, commonName: String? = nil, confidenceScore: Double, distinguishingFeature: String? = nil) {
        self.scientificName = scientificName
        self.commonName = commonName
        self.confidenceScore = confidenceScore
        self.distinguishingFeature = distinguishingFeature
    }
}
