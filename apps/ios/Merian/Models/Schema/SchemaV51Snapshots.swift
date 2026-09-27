import Foundation
import SwiftData

/// Immutable outgoing V51 shapes copied before adding result provenance to V52.
/// Relationship endpoints use only V51 model identities.
extension MerianSchemaV51 {
    @Model
    public final class LocalScanRecord {
        @Attribute(.unique) public var id: String
        public var speciesId: String
        public var scientificName: String
        public var commonName: String
        public var timestamp: Date
        public var captureDate: Date?
        public var capturedMediaJSON: String?
        @Relationship(deleteRule: .cascade) public var capturedMediaEntries: [MerianSchemaV51.CapturedMediaEntry]? = []

        public var semanticTags: [String]
        /// Hazard classification returned by the AI. One of: "none" | "poisonous" | "venomous" | "allergenic" | "irritant".
        public var hazardType: String = "none"
        public var isBiological: Bool
        public var isLiveCapture: Bool
        public var isInvasive: Bool
        @Attribute public var invasiveStatusRegion: String?
        @Attribute public var invasiveRationale: String?
        @Attribute public var invasiveConfidence: Double?
        public var ecologyType: String
        public var wikipediaUrl: String?
        /// Wikipedia summary paragraph for this species. Cached from the Wikipedia REST API.
        @Attribute(originalName: "wikipediaExtract") public var wikipediaOverview: String?
        public var referenceImageUrl: String?
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

        public var collections: [MerianSchemaV51.ScanCollection]? = []

        public var similarSpecies: [String]?
        public var lookalikesData: Data?
        /// JSON-encoded `[IdentificationCandidate]` — the model's top alternative species when
        /// `confidenceScore` fell below the tier-specific `InferenceConfidencePolicy.Bands.diagnosticTrigger` threshold.
        /// Nil for high-confidence scans and all scans captured before V28.
        @Attribute public var candidatesData: Data?

        /// Scientific name chosen by the user when they disagreed with the AI's identification.
        /// Nil means no override — AI identification accepted by default. Cloud-synced.
        @Attribute public var userIdentificationOverride: String?
        /// Local-only flag set when user taps "Yes, correct" on the CandidatesCard prompt.
        /// Suppresses the "Was the AI correct?" prompt on re-open. Not synced to cloud.
        @Attribute public var userConfirmedIdentification: Bool = false

        /// Legacy local moderation flag retained for schema compatibility.
        /// No longer drives Insight confidence or candidate-review UI.
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
        @Attribute public var sex: String?
        @Attribute public var sexConfidence: Double?
        @Attribute public var sexEvidence: String?
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

        /// JSON-encoded `PetIdentification` for dog/cat breed or coat labels.
        /// Kept separate from scientific/common names so taxonomy remains species-grade.
        @Attribute public var petIdentificationData: Data?

        @Attribute public var confirmedSpeciesId: String?

        // Changed to optional so SQLite lightweight migration can add the column correctly
        @Attribute public var userReviewStateRaw: String? = "unreviewed"

        /// Raw JSON array of structured `ObservationContext`s staged by the user before submission.
        /// Replaced singular JSON string from V38.
        @Attribute public var observationContextsJSON: [String]?

        /// Private user-authored notes about the discovery itself.
        /// Distinct from `ObservationContext`, which is prompt input for the analysis pipeline.
        @Attribute public var fieldNotes: String?

        public var userReviewState: UserReviewState {
            get { UserReviewState(rawValue: userReviewStateRaw ?? UserReviewState.unreviewed.rawValue) ?? .unreviewed }
            set { userReviewStateRaw = newValue.rawValue }
        }

        @Attribute public var coverImagePath: String?

        public init(
            id: String = UUID().uuidString,
            speciesId: String,
            scientificName: String,
            commonName: String,
            timestamp: Date = Date(),
            captureDate: Date? = nil,
            capturedMediaJSON: String? = nil,
            coverImagePath: String? = nil,
            semanticTags: [String] = [],
            hazardType: String = "none",
            isBiological: Bool = true,
            isLiveCapture: Bool = true,
            isInvasive: Bool = false,
            invasiveStatusRegion: String? = nil,
            invasiveRationale: String? = nil,
            invasiveConfidence: Double? = nil,
            ecologyType: String = "unknown",
            wikipediaUrl: String? = nil,
            wikipediaOverview: String? = nil,
            referenceImageUrl: String? = nil,
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
            collections: [MerianSchemaV51.ScanCollection]? = [],
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
            sex: String? = nil,
            sexConfidence: Double? = nil,
            sexEvidence: String? = nil,
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
            petIdentificationData: Data? = nil,
            confirmedSpeciesId: String? = nil,
            userReviewStateRaw: String? = nil,
            fieldNotes: String? = nil
        ) {

            self.id = id
            self.speciesId = speciesId
            self.scientificName = scientificName
            self.commonName = commonName
            self.timestamp = timestamp
            self.captureDate = captureDate
            self.capturedMediaJSON = capturedMediaJSON
            self.coverImagePath = coverImagePath
            self.semanticTags = semanticTags
            self.hazardType = hazardType
            self.isBiological = isBiological
            self.isLiveCapture = isLiveCapture
            self.isInvasive = isInvasive
            self.invasiveStatusRegion = invasiveStatusRegion
            self.invasiveRationale = invasiveRationale
            self.invasiveConfidence = invasiveConfidence
            self.ecologyType = ecologyType
            self.wikipediaUrl = wikipediaUrl
            self.wikipediaOverview = wikipediaOverview
            self.referenceImageUrl = referenceImageUrl
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
            self.sex = sex
            self.sexConfidence = sexConfidence
            self.sexEvidence = sexEvidence
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
            self.petIdentificationData = petIdentificationData
            self.confirmedSpeciesId = confirmedSpeciesId
            self.userReviewStateRaw = userReviewStateRaw
            self.fieldNotes = fieldNotes
        }
    }

    @Model
    public final class OfflineQueuedScan {
        @Attribute(.unique) public var id: String
        public var timestamp: Date
        public var capturedMediaJSON: String?
        @Relationship(deleteRule: .cascade) public var capturedMediaEntries: [MerianSchemaV51.CapturedMediaEntry]? = []

        public var gpsLatitude: Double?
        public var gpsLongitude: Double?
        public var gpsElevation: Double?
        public var weatherCondition: String?
        public var weatherTemperatureF: Double?
        public var blurScore: Double?
        public var subjectDistanceInMeters: Float?
        public var locationName: String?
        public var isFlashFired: Bool?
        public var cameraPitchDegrees: Double?
        public var compassHeading: Double?
        public var relativeHumidity: Double?
        public var uvIndex: Int?
        @Attribute public var zoomFactor: Double?

        /// Raw value of `ScanQueueState`. Stored as `Int` for `#Predicate` compatibility.
        /// Use `queueState` for typed access. Replaces the old `isUploaded` / `isDeleted` booleans.
        public var scanStateRaw: Int = ScanQueueState.pending.rawValue

        /// R2 object keys written at upload confirmation time.
        /// Eliminates auth-dependent key reconstruction at inference time.
        public var stagedR2Keys: [String]?

        /// Documents-relative image files used for inference replay. This is intentionally separate
        /// from `capturedMediaJSON`, whose images are user-visible display/share media.
        @Attribute public var inferenceImagePaths: [String]?

        /// Encoded `[IdentifyVisualMediaItem]` matching `inferenceImagePaths`.
        @Attribute public var visualMediaItemsJSON: String?

        /// Private user-authored notes captured while the scan is still in flight.
        @Attribute public var fieldNotes: String?

        /// Durable retry and diagnostics fields. These replace the older process-local retry counter
        /// so app relaunches keep the queue's real state.
        @Attribute public var queueAttemptCount: Int = 0
        @Attribute public var queueLastAttemptAt: Date?
        @Attribute public var queueNextRetryAt: Date?
        @Attribute public var queueLastErrorCode: String?
        @Attribute public var queueLastErrorMessage: String?
        @Attribute public var queueLastHTTPStatus: Int?
        @Attribute public var queueLastServerStatus: String?
        @Attribute public var queueLastServerStage: String?
        @Attribute public var queueLastServerRetryAfter: Date?
        @Attribute public var queueUpdatedAt: Date = Date()
        @Attribute public var queueNeedsAttention: Bool = false
        @Attribute public var queueSchemaRepairGeneration: Int = 1

        // MARK: - Typed accessor

        public var queueState: ScanQueueState {
            get { ScanQueueState(rawValue: scanStateRaw) ?? .pending }
            set { scanStateRaw = newValue.rawValue }
        }

        @Attribute public var coverImagePath: String?

        public init(
            id: String = UUID().uuidString,
            timestamp: Date = Date(),
            capturedMediaJSON: String? = nil,
            coverImagePath: String? = nil,
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
            inferenceImagePaths: [String]? = nil,
            visualMediaItemsJSON: String? = nil,
            fieldNotes: String? = nil,
            queueAttemptCount: Int = 0,
            queueLastAttemptAt: Date? = nil,
            queueNextRetryAt: Date? = nil,
            queueLastErrorCode: String? = nil,
            queueLastErrorMessage: String? = nil,
            queueLastHTTPStatus: Int? = nil,
            queueLastServerStatus: String? = nil,
            queueLastServerStage: String? = nil,
            queueLastServerRetryAfter: Date? = nil,
            queueUpdatedAt: Date = Date(),
            queueNeedsAttention: Bool = false,
            queueSchemaRepairGeneration: Int = 1
        ) {
            self.id = id
            self.timestamp = timestamp
            self.capturedMediaJSON = capturedMediaJSON
            self.coverImagePath = coverImagePath
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
            self.inferenceImagePaths = inferenceImagePaths
            self.visualMediaItemsJSON = visualMediaItemsJSON
            self.fieldNotes = fieldNotes
            self.queueAttemptCount = queueAttemptCount
            self.queueLastAttemptAt = queueLastAttemptAt
            self.queueNextRetryAt = queueNextRetryAt
            self.queueLastErrorCode = queueLastErrorCode
            self.queueLastErrorMessage = queueLastErrorMessage
            self.queueLastHTTPStatus = queueLastHTTPStatus
            self.queueLastServerStatus = queueLastServerStatus
            self.queueLastServerStage = queueLastServerStage
            self.queueLastServerRetryAfter = queueLastServerRetryAfter
            self.queueUpdatedAt = queueUpdatedAt
            self.queueNeedsAttention = queueNeedsAttention
            self.queueSchemaRepairGeneration = queueSchemaRepairGeneration
        }
    }

    @Model
    public final class CapturedMediaEntry {
        @Attribute(.unique) public var id: String
        public var orderIndex: Int
        public var kindRaw: String
        public var storageRaw: String
        public var mediaPath: String
        public var observationContextJSON: String

        init(
            id: String = UUID().uuidString,
            orderIndex: Int,
            item: SerializedMediaItem
        ) {
            self.id = id
            self.orderIndex = orderIndex

            switch item {
            case .image(let reference):
                self.kindRaw = PersistedCapturedMediaKind.image.rawValue
                self.storageRaw = reference.storage.rawValue
                self.mediaPath = reference.serializedPath
                self.observationContextJSON = ""
            case .audio(let reference):
                self.kindRaw = PersistedCapturedMediaKind.audio.rawValue
                self.storageRaw = reference.storage.rawValue
                self.mediaPath = reference.serializedPath
                self.observationContextJSON = ""
            case .video(let reference):
                self.kindRaw = PersistedCapturedMediaKind.video.rawValue
                self.storageRaw = reference.video.storage.rawValue
                self.mediaPath = reference.serializedPath
                self.observationContextJSON = ""
            case .description(let context):
                self.kindRaw = PersistedCapturedMediaKind.description.rawValue
                self.storageRaw = ""
                self.mediaPath = ""
                let contextData = try? JSONEncoder().encode(context)
                self.observationContextJSON = contextData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            }
        }

        var kind: PersistedCapturedMediaKind? {
            PersistedCapturedMediaKind(rawValue: kindRaw)
        }

        var serializedItem: SerializedMediaItem? {
            switch kind {
            case .image:
                guard let storage = MediaStorageLocation(rawValue: storageRaw), !mediaPath.isEmpty else {
                    return nil
                }
                return .image(StoredMediaReference(storage: storage, path: mediaPath))
            case .audio:
                guard let storage = MediaStorageLocation(rawValue: storageRaw), !mediaPath.isEmpty else {
                    return nil
                }
                return .audio(StoredMediaReference(storage: storage, path: mediaPath))
            case .video:
                guard let storage = MediaStorageLocation(rawValue: storageRaw), !mediaPath.isEmpty else {
                    return nil
                }
                return .video(StoredVideoMediaReference(StoredMediaReference(storage: storage, path: mediaPath)))
            case .description:
                guard let contextData = observationContextJSON.data(using: .utf8),
                      let context = try? JSONDecoder().decode(ObservationContext.self, from: contextData) else {
                    return nil
                }
                return .description(context)
            case .none:
                return nil
            }
        }
    }

    @Model
    public final class ScanCollection {
        @Attribute(.unique) public var id: String = UUID().uuidString
        public var name: String
        public var createdAt: Date = Date()
        @Attribute(originalName: "isDeleted")
        public var isPendingDeletion: Bool = false

        @Relationship(inverse: \MerianSchemaV51.LocalScanRecord.collections) public var scans: [MerianSchemaV51.LocalScanRecord]? = []

        public init(
            id: String = UUID().uuidString,
            name: String,
            createdAt: Date = Date(),
            isPendingDeletion: Bool = false,
            scans: [MerianSchemaV51.LocalScanRecord]? = []
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.isPendingDeletion = isPendingDeletion
            self.scans = scans
        }
    }

    @Model
    public final class PendingCloudDeletionTask {
        @Attribute(.unique) public var scanId: String
        public var timestamp: Date = Date()

        public init(scanId: String, timestamp: Date = Date()) {
            self.scanId = scanId
            self.timestamp = timestamp
        }
    }

    @Model
    public final class UserSpeciesPreference {
        @Attribute(.unique) public var id: String = UUID().uuidString
        public var ownerUserId: String = ""
        public var scientificName: String
        public var preferredCommonName: String
        public var updatedAt: Date = Date()

        public init(
            ownerUserID: UUID,
            scientificName: String,
            preferredCommonName: String,
            updatedAt: Date = Date()
        ) {
            id = Self.identifier(
                ownerUserID: ownerUserID,
                scientificName: scientificName
            )
            ownerUserId = ownerUserID.uuidString.lowercased()
            self.scientificName = scientificName
            self.preferredCommonName = preferredCommonName
            self.updatedAt = updatedAt
        }

        public static func identifier(
            ownerUserID: UUID,
            scientificName: String
        ) -> String {
            "\(ownerUserID.uuidString.lowercased())|\(scientificName)"
        }
    }

    @Model
    public final class OfflineJobRecord {
        @Attribute(.unique) public var id: String
        public var kindRaw: String
        public var subjectId: String?
        public var priority: Int
        public var statusRaw: String
        public var createdAt: Date
        public var updatedAt: Date
        public var lastAttemptAt: Date?
        public var nextRunAt: Date?
        public var attemptCount: Int
        public var lastErrorCode: String?
        public var lastErrorMessage: String?
        public var lastHTTPStatus: Int?
        public var serverStatus: String?
        public var serverStage: String?
        public var serverRetryAfter: Date?
        public var requiresUnconstrainedNetwork: Bool
        public var allowsCellular: Bool
        public var approximateBytes: Int64
        public var metadataJSON: String?

        public var kind: OfflineJobKind {
            get { OfflineJobKind(rawValue: kindRaw) ?? .future }
            set { kindRaw = newValue.rawValue }
        }

        public var status: OfflineJobStatus {
            get { OfflineJobStatus(rawValue: statusRaw) ?? .pending }
            set { statusRaw = newValue.rawValue }
        }

        public init(
            id: String,
            kind: OfflineJobKind,
            subjectId: String? = nil,
            priority: Int = 0,
            status: OfflineJobStatus = .pending,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            lastAttemptAt: Date? = nil,
            nextRunAt: Date? = nil,
            attemptCount: Int = 0,
            lastErrorCode: String? = nil,
            lastErrorMessage: String? = nil,
            lastHTTPStatus: Int? = nil,
            serverStatus: String? = nil,
            serverStage: String? = nil,
            serverRetryAfter: Date? = nil,
            requiresUnconstrainedNetwork: Bool = false,
            allowsCellular: Bool = true,
            approximateBytes: Int64 = 0,
            metadataJSON: String? = nil
        ) {
            self.id = id
            self.kindRaw = kind.rawValue
            self.subjectId = subjectId
            self.priority = priority
            self.statusRaw = status.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.lastAttemptAt = lastAttemptAt
            self.nextRunAt = nextRunAt
            self.attemptCount = attemptCount
            self.lastErrorCode = lastErrorCode
            self.lastErrorMessage = lastErrorMessage
            self.lastHTTPStatus = lastHTTPStatus
            self.serverStatus = serverStatus
            self.serverStage = serverStage
            self.serverRetryAfter = serverRetryAfter
            self.requiresUnconstrainedNetwork = requiresUnconstrainedNetwork
            self.allowsCellular = allowsCellular
            self.approximateBytes = approximateBytes
            self.metadataJSON = metadataJSON
        }
    }

    @Model
    public final class OfflineQueueEvent {
        @Attribute(.unique) public var id: String
        public var jobId: String?
        public var scanId: String?
        public var kindRaw: String
        public var createdAt: Date
        public var message: String?
        public var errorCode: String?
        public var httpStatus: Int?
        public var metadataJSON: String?

        public var kind: OfflineQueueEventKind {
            get { OfflineQueueEventKind(rawValue: kindRaw) ?? .diagnostics }
            set { kindRaw = newValue.rawValue }
        }

        public init(
            id: String = UUID().uuidString,
            jobId: String? = nil,
            scanId: String? = nil,
            kind: OfflineQueueEventKind,
            createdAt: Date = Date(),
            message: String? = nil,
            errorCode: String? = nil,
            httpStatus: Int? = nil,
            metadataJSON: String? = nil
        ) {
            self.id = id
            self.jobId = jobId
            self.scanId = scanId
            self.kindRaw = kind.rawValue
            self.createdAt = createdAt
            self.message = message
            self.errorCode = errorCode
            self.httpStatus = httpStatus
            self.metadataJSON = metadataJSON
        }
    }
}
