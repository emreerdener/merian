import Foundation
import SwiftData

// Added in V39:
//   LocalScanRecord.audioFilePaths — [String]?
//   LocalScanRecord.observationContextsJSON — [String]?
//   OfflineQueuedScan.audioFilePaths — [String]?
//   OfflineQueuedScan.observationContextsJSON — [String]?
enum MerianSchemaV39: VersionedSchema {
    static var versionIdentifier = Schema.Version(39, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV39.LocalScanRecord.self, MerianSchemaV39.OfflineQueuedScan.self,
         MerianSchemaV39.ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}

extension MerianSchemaV39 {

    @Model
    final class LocalScanRecord {
        @Attribute(.unique) var id: String
        var speciesId: String
        var scientificName: String
        var commonName: String
        var timestamp: Date
        var captureDate: Date?
        var localImagePath: String?

        var semanticTags: [String]
        /// Hazard classification returned by the AI. One of: "none" | "poisonous" | "venomous" | "allergenic" | "irritant".
        var hazardType: String = "none"
        var isBiological: Bool
        var isLiveCapture: Bool
        var isInvasive: Bool
        var ecologyType: String
        var wikipediaUrl: String?
        /// Wikipedia summary paragraph for this species. Cached from the Wikipedia REST API.
        @Attribute(originalName: "wikipediaExtract") var wikipediaOverview: String?
        var referenceImageUrl: String?
        var additionalImagePaths: [String]?
        var confidenceScore: Double?
        @Attribute var isLocallyArchived: Bool = false

        var taxonomyKingdom: String?
        var taxonomyPhylum: String?
        var taxonomyClass: String?
        var taxonomyOrder: String?
        var taxonomyFamily: String?
        var taxonomyGenus: String?

        var locationName: String?
        var weatherCondition: String?
        var weatherTemperatureF: Double?

        var collections: [MerianSchemaV39.ScanCollection]? = []

        var similarSpecies: [String]?
        var lookalikesData: Data?
        /// JSON-encoded `[IdentificationCandidate]` — the model's top alternative species when
        /// `confidenceScore` fell below the tier-specific `MerianConfig.diagnosticTrigger` threshold.
        /// Nil for high-confidence scans and all scans captured before V28.
        @Attribute var candidatesData: Data?

        /// Scientific name chosen by the user when they disagreed with the AI's identification.
        /// Nil means no override — AI identification accepted by default. Cloud-synced.
        @Attribute var userIdentificationOverride: String?
        /// Local-only flag set when user taps "Yes, correct" on the CandidatesCard prompt.
        /// Suppresses the "Was the AI correct?" prompt on re-open. Not synced to cloud.
        @Attribute var userConfirmedIdentification: Bool = false

        /// Legacy local moderation flag retained for schema compatibility.
        /// No longer drives Insight confidence or candidate-review UI.
        @Attribute var isFlagged: Bool = false

        @Attribute var iucnRedListStatus: String?
        @Attribute var gpsLatitude: Double?
        @Attribute var gpsLongitude: Double?
        @Attribute var gpsElevation: Double?
        @Attribute var zoomFactor: Double?

        /// Per-scan AI vision reasoning — unique to the specific photo submitted.
        @Attribute var aiReasoning: String?
        @Attribute var habitatDescription: String?
        /// GBIF species usage key for occurrence density heatmap tiles.
        @Attribute var gbifTaxonKey: Int?

        @Attribute var estimatedSizeCm: Double?
        @Attribute var lifeStage: String?
        @Attribute var reproductiveCondition: String?
        @Attribute var individualCount: Int?
        @Attribute var ecologicalInteractions: [String]?
        @Attribute var inferenceTier: String?
        
        /// User-defined custom tags for personal categorization and search indexing.
        @Attribute var customTags: [String] = []

        /// Tracks if a user has opened the scan's insight sheet. Defaults to true so historic scans don't receive "New" badges.
        var hasBeenViewed: Bool = true

        /// Gemini's photographic quality score (0–100) for the submitted image.
        /// Derived from `image_quality.overall_score` in the edge response.
        /// Nil for scans captured before V30.
        @Attribute var imageQualityScore: Int?

        /// All known English vernacular synonyms beyond `commonName`.
        /// Sourced from GBIF vernacular names during background enrichment.
        /// Nil for scans captured before V34 or species not yet enriched.
        @Attribute var alternativeCommonNames: [String]?

        @Attribute var confirmedSpeciesId: String?

        // Changed to optional so SQLite lightweight migration can add the column correctly
        @Attribute var userReviewStateRaw: String? = "unreviewed"

        /// Raw JSON array of structured `ObservationContext`s staged by the user before submission.
        /// Replaced singular JSON string from V38.
        @Attribute var observationContextsJSON: [String]?

        /// Local file paths to the audio recordings associated with this scan.
        /// Added in SchemaV39 to support multi-modal captures.
        @Attribute var audioFilePaths: [String]?

        var userReviewState: UserReviewState {
            get { UserReviewState(rawValue: userReviewStateRaw ?? UserReviewState.unreviewed.rawValue) ?? .unreviewed }
            set { userReviewStateRaw = newValue.rawValue }
        }

        init(
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
            observationContextsJSON: [String]? = nil,
            audioFilePaths: [String]? = nil
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
            self.observationContextsJSON = observationContextsJSON
            self.audioFilePaths = audioFilePaths
        }
    }

    @Model
    final class OfflineQueuedScan {
        @Attribute(.unique) var id: String
        var timestamp: Date
        var localImagePaths: [String]

        var gpsLatitude: Double?
        var gpsLongitude: Double?
        var gpsElevation: Double?
        var weatherCondition: String?
        var weatherTemperatureF: Double?
        var blurScore: Double?
        var subjectDistanceInMeters: Float?
        var locationName: String?
        var isFlashFired: Bool?
        var cameraPitchDegrees: Double?
        var compassHeading: Double?
        var relativeHumidity: Double?
        var uvIndex: Int?
        @Attribute var zoomFactor: Double?

        /// Raw value of `ScanQueueState`. Stored as `Int` for `#Predicate` compatibility.
        /// Use `queueState` for typed access. Replaces the old `isUploaded` / `isDeleted` booleans.
        var scanStateRaw: Int = ScanQueueState.pending.rawValue

        /// R2 object keys written at upload confirmation time.
        /// Eliminates auth-dependent key reconstruction at inference time.
        var stagedR2Keys: [String]?

        /// JSON-encoded `ObservationContext`s serialized at enqueue time.
        /// Preserved so the offline-retry path can reconstruct the full combined
        /// multimodal payload without requiring the user to re-enter details.
        var observationContextsJSON: [String]?

        /// File paths to the audio recordings staged with this scan.
        var audioFilePaths: [String]?

        // MARK: - Typed accessor

        var queueState: ScanQueueState {
            get { ScanQueueState(rawValue: scanStateRaw) ?? .pending }
            set { scanStateRaw = newValue.rawValue }
        }

        init(
            id: String = UUID().uuidString,
            timestamp: Date = Date(),
            localImagePaths: [String] = [],
            gpsLatitude: Double? = nil,
            gpsLongitude: Double? = nil,
            gpsElevation: Double? = nil,
            weatherCondition: String? = nil,
            weatherTemperatureF: Double? = nil,
            blurScore: Double? = nil,
            subjectDistanceInMeters: Float? = nil,
            locationName: String? = nil,
            isFlashFired: Bool? = nil,
            cameraPitchDegrees: Double? = nil,
            compassHeading: Double? = nil,
            relativeHumidity: Double? = nil,
            uvIndex: Int? = nil,
            zoomFactor: Double? = nil,
            scanState: ScanQueueState = .pending,
            stagedR2Keys: [String]? = nil,
            observationContextsJSON: [String]? = nil,
            audioFilePaths: [String]? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.localImagePaths = localImagePaths
            self.gpsLatitude = gpsLatitude
            self.gpsLongitude = gpsLongitude
            self.gpsElevation = gpsElevation
            self.weatherCondition = weatherCondition
            self.weatherTemperatureF = weatherTemperatureF
            self.blurScore = blurScore
            self.subjectDistanceInMeters = subjectDistanceInMeters
            self.locationName = locationName
            self.isFlashFired = isFlashFired
            self.cameraPitchDegrees = cameraPitchDegrees
            self.compassHeading = compassHeading
            self.relativeHumidity = relativeHumidity
            self.uvIndex = uvIndex
            self.zoomFactor = zoomFactor
            self.scanStateRaw = scanState.rawValue
            self.stagedR2Keys = stagedR2Keys
            self.observationContextsJSON = observationContextsJSON
            self.audioFilePaths = audioFilePaths
        }
    }
}

// MARK: - Frozen ScanCollection snapshot for MerianSchemaV39
extension MerianSchemaV39 {
    @Model
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        var isDeleted: Bool = false

        @Relationship(inverse: \MerianSchemaV39.LocalScanRecord.collections) var scans: [MerianSchemaV39.LocalScanRecord]? = []

        init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), isDeleted: Bool = false, scans: [MerianSchemaV39.LocalScanRecord]? = []) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.isDeleted = isDeleted
            self.scans = scans
        }
    }
}
