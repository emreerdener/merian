import Foundation
import SwiftData

// Frozen from the active V50 model graph before the V51 collection-tombstone
// repair. These types are the immutable source side of V50 -> V51 and must never
// follow active schema edits. A genuine released-binary install-over remains the
// external compatibility proof.
extension MerianSchemaV50 {
    @Model
    final class CapturedMediaEntry {
        @Attribute(.unique) var id: String
        var orderIndex: Int
        var kindRaw: String
        var storageRaw: String
        var mediaPath: String
        var observationContextJSON: String

        init(
            id: String = UUID().uuidString,
            orderIndex: Int,
            item: SerializedMediaItem
        ) {
            self.id = id
            self.orderIndex = orderIndex

            switch item {
            case .image(let reference):
                kindRaw = PersistedCapturedMediaKind.image.rawValue
                storageRaw = reference.storage.rawValue
                mediaPath = reference.serializedPath
                observationContextJSON = ""
            case .audio(let reference):
                kindRaw = PersistedCapturedMediaKind.audio.rawValue
                storageRaw = reference.storage.rawValue
                mediaPath = reference.serializedPath
                observationContextJSON = ""
            case .video(let reference):
                kindRaw = PersistedCapturedMediaKind.video.rawValue
                storageRaw = reference.video.storage.rawValue
                mediaPath = reference.serializedPath
                observationContextJSON = ""
            case .description(let context):
                kindRaw = PersistedCapturedMediaKind.description.rawValue
                storageRaw = ""
                mediaPath = ""
                let contextData = try? JSONEncoder().encode(context)
                observationContextJSON = contextData.flatMap {
                    String(data: $0, encoding: .utf8)
                } ?? ""
            }
        }

        static func makeEntries(
            from items: [SerializedMediaItem]
        ) -> [MerianSchemaV50.CapturedMediaEntry] {
            items.enumerated().map { index, item in
                MerianSchemaV50.CapturedMediaEntry(
                    orderIndex: index,
                    item: item
                )
            }
        }
    }

    @Model
    final class LocalScanRecord {
        @Attribute(.unique) var id: String
        var speciesId: String
        var scientificName: String
        var commonName: String
        var timestamp: Date
        var captureDate: Date?
        var capturedMediaJSON: String?
        @Relationship(deleteRule: .cascade)
        var capturedMediaEntries: [MerianSchemaV50.CapturedMediaEntry]? = []

        var semanticTags: [String]
        var hazardType: String = "none"
        var isBiological: Bool
        var isLiveCapture: Bool
        var isInvasive: Bool
        @Attribute var invasiveStatusRegion: String?
        @Attribute var invasiveRationale: String?
        @Attribute var invasiveConfidence: Double?
        var ecologyType: String
        var wikipediaUrl: String?
        @Attribute(originalName: "wikipediaExtract")
        var wikipediaOverview: String?
        var referenceImageUrl: String?
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

        var collections: [MerianSchemaV50.ScanCollection]? = []

        var similarSpecies: [String]?
        var lookalikesData: Data?
        @Attribute var candidatesData: Data?
        @Attribute var userIdentificationOverride: String?
        @Attribute var userConfirmedIdentification: Bool = false
        @Attribute var isFlagged: Bool = false

        @Attribute var iucnRedListStatus: String?
        @Attribute var gpsLatitude: Double?
        @Attribute var gpsLongitude: Double?
        @Attribute var gpsElevation: Double?
        @Attribute var zoomFactor: Double?

        @Attribute var aiReasoning: String?
        @Attribute var habitatDescription: String?
        @Attribute var gbifTaxonKey: Int?

        @Attribute var estimatedSizeCm: Double?
        @Attribute var lifeStage: String?
        @Attribute var reproductiveCondition: String?
        @Attribute var sex: String?
        @Attribute var sexConfidence: Double?
        @Attribute var sexEvidence: String?
        @Attribute var individualCount: Int?
        @Attribute var ecologicalInteractions: [String]?
        @Attribute var inferenceTier: String?
        @Attribute var customTags: [String] = []
        var hasBeenViewed: Bool = true
        @Attribute var imageQualityScore: Int?
        @Attribute var alternativeCommonNames: [String]?
        @Attribute var petIdentificationData: Data?
        @Attribute var confirmedSpeciesId: String?
        @Attribute var userReviewStateRaw: String? = "unreviewed"
        @Attribute var observationContextsJSON: [String]?
        @Attribute var fieldNotes: String?
        @Attribute var coverImagePath: String?

        init(
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
            collections: [MerianSchemaV50.ScanCollection]? = [],
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
    final class OfflineQueuedScan {
        @Attribute(.unique) var id: String
        var timestamp: Date
        var capturedMediaJSON: String?
        @Relationship(deleteRule: .cascade)
        var capturedMediaEntries: [MerianSchemaV50.CapturedMediaEntry]? = []

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
        var scanStateRaw: Int = ScanQueueState.pending.rawValue
        var stagedR2Keys: [String]?
        @Attribute var inferenceImagePaths: [String]?
        @Attribute var visualMediaItemsJSON: String?
        @Attribute var fieldNotes: String?
        @Attribute var queueAttemptCount: Int = 0
        @Attribute var queueLastAttemptAt: Date?
        @Attribute var queueNextRetryAt: Date?
        @Attribute var queueLastErrorCode: String?
        @Attribute var queueLastErrorMessage: String?
        @Attribute var queueLastHTTPStatus: Int?
        @Attribute var queueLastServerStatus: String?
        @Attribute var queueLastServerStage: String?
        @Attribute var queueLastServerRetryAfter: Date?
        @Attribute var queueUpdatedAt: Date = Date()
        @Attribute var queueNeedsAttention: Bool = false
        @Attribute var queueSchemaRepairGeneration: Int = 1
        @Attribute var coverImagePath: String?

        var queueState: ScanQueueState {
            get { ScanQueueState(rawValue: scanStateRaw) ?? .pending }
            set { scanStateRaw = newValue.rawValue }
        }

        init(
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
            scanStateRaw = scanState.rawValue
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
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        var isDeleted: Bool = false
        @Relationship(
            inverse: \MerianSchemaV50.LocalScanRecord.collections
        )
        var scans: [MerianSchemaV50.LocalScanRecord]? = []

        init(
            id: String = UUID().uuidString,
            name: String,
            createdAt: Date = Date(),
            isDeleted: Bool = false,
            scans: [MerianSchemaV50.LocalScanRecord]? = []
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.isDeleted = isDeleted
            self.scans = scans
        }
    }

    @Model
    final class PendingCloudDeletionTask {
        @Attribute(.unique) var scanId: String
        var timestamp: Date = Date()

        init(scanId: String, timestamp: Date = Date()) {
            self.scanId = scanId
            self.timestamp = timestamp
        }
    }

    @Model
    final class UserSpeciesPreference {
        @Attribute(.unique) var scientificName: String
        var preferredCommonName: String
        var updatedAt: Date = Date()

        init(
            scientificName: String,
            preferredCommonName: String,
            updatedAt: Date = Date()
        ) {
            self.scientificName = scientificName
            self.preferredCommonName = preferredCommonName
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class OfflineJobRecord {
        @Attribute(.unique) var id: String
        var kindRaw: String
        var subjectId: String?
        var priority: Int
        var statusRaw: String
        var createdAt: Date
        var updatedAt: Date
        var lastAttemptAt: Date?
        var nextRunAt: Date?
        var attemptCount: Int
        var lastErrorCode: String?
        var lastErrorMessage: String?
        var lastHTTPStatus: Int?
        var serverStatus: String?
        var serverStage: String?
        var serverRetryAfter: Date?
        var requiresUnconstrainedNetwork: Bool
        var allowsCellular: Bool
        var approximateBytes: Int64
        var metadataJSON: String?

        var kind: OfflineJobKind {
            get { OfflineJobKind(rawValue: kindRaw) ?? .future }
            set { kindRaw = newValue.rawValue }
        }

        var status: OfflineJobStatus {
            get { OfflineJobStatus(rawValue: statusRaw) ?? .pending }
            set { statusRaw = newValue.rawValue }
        }

        init(
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
            kindRaw = kind.rawValue
            self.subjectId = subjectId
            self.priority = priority
            statusRaw = status.rawValue
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
    final class OfflineQueueEvent {
        @Attribute(.unique) var id: String
        var jobId: String?
        var scanId: String?
        var kindRaw: String
        var createdAt: Date
        var message: String?
        var errorCode: String?
        var httpStatus: Int?
        var metadataJSON: String?

        var kind: OfflineQueueEventKind {
            get { OfflineQueueEventKind(rawValue: kindRaw) ?? .diagnostics }
            set { kindRaw = newValue.rawValue }
        }

        init(
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
            kindRaw = kind.rawValue
            self.createdAt = createdAt
            self.message = message
            self.errorCode = errorCode
            self.httpStatus = httpStatus
            self.metadataJSON = metadataJSON
        }
    }

    /// Durable preference captured from the live Capture UI for a queued scan.
    ///
    /// This companion was introduced in V50 and is kept in the frozen snapshot
    /// so the V50 source graph cannot drift when active models evolve.
    @Model
    final class OfflineQueuedScanGoalHint {
        @Attribute(.unique) var scanId: String
        var userFieldTripId: String
        var itemId: String

        init(
            scanId: String,
            userFieldTripId: String,
            itemId: String
        ) {
            self.scanId = scanId
            self.userFieldTripId = userFieldTripId
            self.itemId = itemId
        }
    }
}
