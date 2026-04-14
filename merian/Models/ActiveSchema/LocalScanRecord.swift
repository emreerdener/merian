import Foundation
import SwiftData

@Model
public final class LocalScanRecord {
    @Attribute(.unique) public var id: String
    public var speciesId: String
    public var scientificName: String
    public var commonName: String
    public var timestamp: Date
    public var captureDate: Date?
    public var localImagePath: String?

    public var semanticTags: [String]
    /// Hazard classification returned by the AI. One of: "none" | "poisonous" | "venomous" | "allergenic" | "irritant".
    public var hazardType: String = "none"
    public var isBiological: Bool
    public var isLiveCapture: Bool
    public var isInvasive: Bool
    public var ecologyType: String
    public var wikipediaUrl: String?
    /// Wikipedia summary paragraph for this species. Cached from the Wikipedia REST API.
    @Attribute(originalName: "wikipediaExtract") public var wikipediaOverview: String?
    public var referenceImageUrl: String?
    public var additionalImagePaths: [String]?
    public var confidenceScore: Double?
    @Attribute public var isLocallyArchived: Bool = false

    public var taxonomyKingdom: String?
    public var taxonomyPhylum: String?
    public var taxonomyClass: String?
    public var taxonomyOrder: String?
    public var taxonomyFamily: String?
    public var taxonomyGenus: String?

    public var locationName: String?
    public var weatherCondition: String?
    public var weatherTemperatureF: Double?

    public var collections: [ScanCollection]? = []

    public var similarSpecies: [String]?
    public var lookalikesData: Data?
    /// JSON-encoded `[IdentificationCandidate]` — the model's top alternative species when
    /// `confidenceScore` fell below the tier-specific `MerianConfig.diagnosticTrigger` threshold.
    /// Nil for high-confidence scans and all scans captured before V28.
    @Attribute public var candidatesData: Data?

    /// Scientific name chosen by the user when they disagreed with the AI's identification.
    /// Nil means no override — AI identification accepted by default. Cloud-synced.
    @Attribute public var userIdentificationOverride: String?
    /// Local-only flag set when user taps "Yes, correct" on the CandidatesCard prompt.
    /// Suppresses the "Was the AI correct?" prompt on re-open. Not synced to cloud.
    @Attribute public var userConfirmedIdentification: Bool = false

    /// Set to true when the user flags an identification for manual moderation review.
    /// Retains the "Under Review" state across app sessions locally.
    @Attribute public var isFlagged: Bool = false

    @Attribute public var iucnRedListStatus: String?
    @Attribute public var gpsLatitude: Double?
    @Attribute public var gpsLongitude: Double?
    @Attribute public var gpsElevation: Double?
    @Attribute public var zoomFactor: Double?

    /// Per-scan AI vision reasoning — unique to the specific photo submitted.
    @Attribute public var aiReasoning: String?
    @Attribute public var habitatDescription: String?
    /// GBIF species usage key for occurrence density heatmap tiles.
    @Attribute public var gbifTaxonKey: Int?

    @Attribute public var estimatedSizeCm: Double?
    @Attribute public var lifeStage: String?
    @Attribute public var reproductiveCondition: String?
    @Attribute public var individualCount: Int?
    @Attribute public var ecologicalInteractions: [String]?
    @Attribute public var inferenceTier: String?
    
    /// User-defined custom tags for personal categorization and search indexing.
    @Attribute public var customTags: [String] = []

    /// Tracks if a user has opened the scan's insight sheet. Defaults to true so historic scans don't receive "New" badges.
    public var hasBeenViewed: Bool = true

    /// Gemini's photographic quality score (0–100) for the submitted image.
    /// Derived from `image_quality.overall_score` in the edge response.
    /// Nil for scans captured before V30.
    @Attribute public var imageQualityScore: Int?

    /// All known English vernacular synonyms beyond `commonName`.
    /// Sourced from GBIF vernacular names during background enrichment.
    /// Nil for scans captured before V34 or species not yet enriched.
    @Attribute public var alternativeCommonNames: [String]?

    @Attribute public var confirmedSpeciesId: String?

    // Changed to optional so SQLite lightweight migration can add the column correctly
    @Attribute public var userReviewStateRaw: String? = "unreviewed"

    /// Raw JSON string of the structured `ObservationContext` staged by the user before submission.
    /// Set once at scan creation; never mutated after.
    /// `nil` for image-only scans or scans captured before V37.
    @Attribute public var observationContextJSON: String?

    public var userReviewState: UserReviewState {
        get { UserReviewState(rawValue: userReviewStateRaw ?? UserReviewState.unreviewed.rawValue) ?? .unreviewed }
        set { userReviewStateRaw = newValue.rawValue }
    }

    public init(
        id: String = UUID().uuidString,
        speciesId: String,
        scientificName: String,
        commonName: String,
        timestamp: Date = Date(),
        captureDate: Date? = nil,
        localImagePath: String? = nil,
        semanticTags: [String] = [],
        hazardType: String = "none",
        isBiological: Bool = true,
        isLiveCapture: Bool = true,
        isInvasive: Bool = false,
        ecologyType: String = "unknown",
        wikipediaUrl: String? = nil,
        wikipediaOverview: String? = nil,
        referenceImageUrl: String? = nil,
        additionalImagePaths: [String]? = nil,
        confidenceScore: Double? = nil,
        isLocallyArchived: Bool = false,
        taxonomyKingdom: String? = nil,
        taxonomyPhylum: String? = nil,
        taxonomyClass: String? = nil,
        taxonomyOrder: String? = nil,
        taxonomyFamily: String? = nil,
        taxonomyGenus: String? = nil,
        locationName: String? = nil,
        weatherCondition: String? = nil,
        weatherTemperatureF: Double? = nil,
        collections: [ScanCollection]? = [],
        similarSpecies: [String]? = nil,
        lookalikesData: Data? = nil,
        candidatesData: Data? = nil,
        iucnRedListStatus: String? = nil,
        gpsLatitude: Double? = nil,
        gpsLongitude: Double? = nil,
        gpsElevation: Double? = nil,
        zoomFactor: Double? = nil,
        aiReasoning: String? = nil,
        habitatDescription: String? = nil,
        gbifTaxonKey: Int? = nil,
        estimatedSizeCm: Double? = nil,
        lifeStage: String? = nil,
        reproductiveCondition: String? = nil,
        individualCount: Int? = nil,
        ecologicalInteractions: [String]? = nil,
        inferenceTier: String? = nil,
        customTags: [String] = [],
        hasBeenViewed: Bool = false,
        userIdentificationOverride: String? = nil,
        userConfirmedIdentification: Bool = false,
        isFlagged: Bool = false,
        imageQualityScore: Int? = nil,
        alternativeCommonNames: [String]? = nil,
        confirmedSpeciesId: String? = nil,
        userReviewStateRaw: String? = nil,
        observationContextJSON: String? = nil
    ) {

        self.id = id
        self.speciesId = speciesId
        self.scientificName = scientificName
        self.commonName = commonName
        self.timestamp = timestamp
        self.captureDate = captureDate
        self.localImagePath = localImagePath
        self.semanticTags = semanticTags
        self.hazardType = hazardType
        self.isBiological = isBiological
        self.isLiveCapture = isLiveCapture
        self.isInvasive = isInvasive
        self.ecologyType = ecologyType
        self.wikipediaUrl = wikipediaUrl
        self.wikipediaOverview = wikipediaOverview
        self.referenceImageUrl = referenceImageUrl
        self.additionalImagePaths = additionalImagePaths
        self.confidenceScore = confidenceScore
        self.isLocallyArchived = isLocallyArchived

        self.taxonomyKingdom = taxonomyKingdom
        self.taxonomyPhylum = taxonomyPhylum
        self.taxonomyClass = taxonomyClass
        self.taxonomyOrder = taxonomyOrder
        self.taxonomyFamily = taxonomyFamily
        self.taxonomyGenus = taxonomyGenus

        self.locationName = locationName
        self.weatherCondition = weatherCondition
        self.weatherTemperatureF = weatherTemperatureF

        self.collections = collections

        self.similarSpecies = similarSpecies
        self.lookalikesData = lookalikesData
        self.candidatesData = candidatesData
        self.iucnRedListStatus = iucnRedListStatus
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.gpsElevation = gpsElevation
        self.zoomFactor = zoomFactor

        self.aiReasoning = aiReasoning
        self.habitatDescription = habitatDescription
        self.gbifTaxonKey = gbifTaxonKey

        self.estimatedSizeCm = estimatedSizeCm
        self.lifeStage = lifeStage
        self.reproductiveCondition = reproductiveCondition
        self.individualCount = individualCount
        self.ecologicalInteractions = ecologicalInteractions
        self.inferenceTier = inferenceTier
        self.customTags = customTags
        self.hasBeenViewed = hasBeenViewed
        self.userIdentificationOverride = userIdentificationOverride
        self.userConfirmedIdentification = userConfirmedIdentification
        self.isFlagged = isFlagged
        self.imageQualityScore = imageQualityScore
        self.alternativeCommonNames = alternativeCommonNames
        self.confirmedSpeciesId = confirmedSpeciesId
        self.userReviewStateRaw = userReviewStateRaw
        self.observationContextJSON = observationContextJSON
    }
}
