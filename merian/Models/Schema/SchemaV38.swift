import Foundation
import SwiftData

// Added in V38:
//   LocalScanRecord.audioFilePath — String?
//     Local file path to the audio recording associated with this scan.
enum MerianSchemaV38: VersionedSchema {
    static var versionIdentifier = Schema.Version(38, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV38.LocalScanRecord.self,
         MerianSchemaV38.OfflineQueuedScan.self,
         MerianSchemaV38.ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}

// MARK: - Frozen LocalScanRecord snapshot for MerianSchemaV38
extension MerianSchemaV38 {
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
        var hazardType: String = "none"
        var isBiological: Bool
        var isLiveCapture: Bool
        var isInvasive: Bool
        var ecologyType: String
        var wikipediaUrl: String?
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

        var collections: [MerianSchemaV38.ScanCollection]? = []

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
        @Attribute var individualCount: Int?
        @Attribute var ecologicalInteractions: [String]?
        @Attribute var inferenceTier: String?

        @Attribute var customTags: [String] = []

        var hasBeenViewed: Bool = true

        @Attribute var imageQualityScore: Int?

        @Attribute var alternativeCommonNames: [String]?

        @Attribute var confirmedSpeciesId: String?

        @Attribute var userReviewStateRaw: String? = "unreviewed"

        @Attribute var observationContextJSON: String?

        @Attribute var audioFilePath: String?

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
            collections: [MerianSchemaV38.ScanCollection]? = [],
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
            observationContextJSON: String? = nil,
            audioFilePath: String? = nil
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
            self.audioFilePath = audioFilePath
        }
    }
}

// MARK: - Frozen OfflineQueuedScan snapshot for MerianSchemaV38
extension MerianSchemaV38 {
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

        var scanStateRaw: Int = ScanQueueState.pending.rawValue

        var stagedR2Keys: [String]?

        var observationContextJSON: String?

        var audioFilePath: String?

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
            observationContextJSON: String? = nil,
            audioFilePath: String? = nil
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
            self.observationContextJSON = observationContextJSON
            self.audioFilePath = audioFilePath
        }
    }
}

// MARK: - Frozen ScanCollection snapshot for MerianSchemaV38
extension MerianSchemaV38 {
    @Model
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        var isDeleted: Bool = false

        @Relationship(inverse: \MerianSchemaV38.LocalScanRecord.collections) var scans: [MerianSchemaV38.LocalScanRecord]? = []

        init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), isDeleted: Bool = false, scans: [MerianSchemaV38.LocalScanRecord]? = []) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.isDeleted = isDeleted
            self.scans = scans
        }
    }
}
