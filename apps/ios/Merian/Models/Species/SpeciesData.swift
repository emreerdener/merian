import Foundation

enum SpeciesDataPresentationRole: Sendable, Equatable {
    case inferenceResult
    case inferenceError
}

/// Parsed result from the AI edge function, representing a single identified biological observation.
struct SpeciesData: Sendable {
    let scanId: String?
    /// Explicit UI semantics for this transient value. Error routing must never
    /// be inferred from user-facing copy such as `commonName`.
    let presentationRole: SpeciesDataPresentationRole
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

    // Extended ecological telemetry.
    var estimatedSizeCm: Double?
    var lifeStage: String?
    var reproductiveCondition: String?
    var sex: String?
    var sexConfidence: Double?
    var sexEvidence: String?
    var individualCount: Int?
    var ecologicalInteractions: [String]?

    // Species insights.
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
    /// tier-specific `InferenceConfidencePolicy.Bands.diagnosticTrigger` threshold. Nil for
    /// confident scans.
    var candidates: [IdentificationCandidate]?

    /// Gemini's photographic quality score (0–100) for the submitted image.
    /// Derived from `image_quality.overall_score` in the Edge response. Persisted to
    /// `LocalScanRecord.imageQualityScore` and `public.scans.image_quality_score` for future
    /// community reference-photo curation. Nil for scans captured before V30.
    let imageQualityScore: Int?

    /// The AI's original scientific name — never mutated after init.
    /// Preserved so identification review can show the original suggestion after an override.
    let aiScientificName: String

    /// Scientific name chosen by the user when they disagreed with the AI. Nil means no action.
    var userIdentificationOverride: String?
    /// True when the user confirmed the AI identification; suppresses the review prompt locally.
    var userConfirmedIdentification: Bool
    /// True when the user flagged the AI identification for manual review.
    var isFlagged: Bool
    /// True when the user exhausted the alternative candidates without choosing one.
    var alternativesExhausted: Bool = false

    var audioFilePaths: [String]?
    var videoFilePaths: [String]?
}

extension SpeciesData {
    /// Full memberwise initializer, used for local construction and offline mocking.
    init(
        scanId: String? = nil,
        presentationRole: SpeciesDataPresentationRole = .inferenceResult,
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
        self.presentationRole = presentationRole
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
        self.habitatDescription = habitatDescription?.trimmedNonEmptyValue
        self.gbifTaxonKey = gbifTaxonKey
        self.inferenceTier = inferenceTier
        self.alternativeCommonNames = SpeciesData.sanitizeAlternativeNames(
            alternativeCommonNames
        )
        self.petIdentification = petIdentification?.isDisplayable == true
            ? petIdentification
            : nil
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
