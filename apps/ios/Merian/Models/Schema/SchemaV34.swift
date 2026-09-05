import Foundation
import SwiftData

// Added in V34:
//   LocalScanRecord.alternativeCommonNames — [String]?
//     All known English vernacular synonyms beyond `commonName`, sourced from the
//     GBIF vernacular names endpoint during background enrichment.
//     Nil for scans captured before V34 or species not yet enriched; defaults to nil
//     on migration (lightweight — no backfill needed, data populates on next scan).
//
//   UserSpeciesPreference (new entity)
//     SwiftData-backed store for the user's preferred display name per species,
//     keyed by scientificName. V34 initially promoted legacy per-species
//     UserDefaults keys into this device-global entity. V51 replaces that
//     behavior with account-scoped rows and discards unowned legacy values.
//     Also provides the unique checksum anchor distinguishing V34 from V33
//     (V34 has one more entity in its model set).
//
// NOTE: The preference entity is the frozen root reused by V35...V48.
enum MerianSchemaV34: VersionedSchema {
    static var versionIdentifier = Schema.Version(34, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV34.LocalScanRecord.self, MerianSchemaV34.OfflineQueuedScan.self,
         MerianSchemaV34.ScanCollection.self, MerianSchemaV34.PendingCloudDeletionTask.self,
         MerianSchemaV34.UserSpeciesPreference.self]
    }

    typealias OfflineQueuedScan         = MerianSchemaV33.OfflineQueuedScan
    typealias PendingCloudDeletionTask  = MerianSchemaV30.PendingCloudDeletionTask

    // ScanCollection redeclared so its inverse relationship points to V34.LocalScanRecord.
    @Model
    public final class ScanCollection {
        @Attribute(.unique) public var id: String = UUID().uuidString
        public var name: String
        public var createdAt: Date = Date()
        public var isDeleted: Bool = false

        @Relationship(inverse: \LocalScanRecord.collections) public var scans: [LocalScanRecord]? = []

        public init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), isDeleted: Bool = false, scans: [LocalScanRecord]? = []) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.isDeleted = isDeleted
            self.scans = scans
        }
    }

    @Model
    public final class UserSpeciesPreference {
        @Attribute(.unique) public var scientificName: String
        public var preferredCommonName: String
        public var updatedAt: Date = Date()

        public init(scientificName: String, preferredCommonName: String, updatedAt: Date = Date()) {
            self.scientificName = scientificName
            self.preferredCommonName = preferredCommonName
            self.updatedAt = updatedAt
        }
    }

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
        public var hazardType: String = "none"
        public var isBiological: Bool
        public var isLiveCapture: Bool
        public var isInvasive: Bool
        public var ecologyType: String
        public var wikipediaUrl: String?
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

        public var collections: [MerianSchemaV34.ScanCollection]? = []

        public var similarSpecies: [String]?
        public var lookalikesData: Data?
        @Attribute public var candidatesData: Data?

        @Attribute public var userIdentificationOverride: String?
        @Attribute public var userConfirmedIdentification: Bool = false

        @Attribute public var isFlagged: Bool = false

        @Attribute public var iucnRedListStatus: String?
        @Attribute public var gpsLatitude: Double?
        @Attribute public var gpsLongitude: Double?
        @Attribute public var gpsElevation: Double?
        @Attribute public var zoomFactor: Double?

        @Attribute public var aiReasoning: String?
        @Attribute public var habitatDescription: String?
        @Attribute public var gbifTaxonKey: Int?

        @Attribute public var estimatedSizeCm: Double?
        @Attribute public var lifeStage: String?
        @Attribute public var reproductiveCondition: String?
        @Attribute public var individualCount: Int?
        @Attribute public var ecologicalInteractions: [String]?
        @Attribute public var inferenceTier: String?
        
        @Attribute public var customTags: [String] = []

        public var hasBeenViewed: Bool = true

        @Attribute public var imageQualityScore: Int?

        @Attribute public var alternativeCommonNames: [String]?

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
            collections: [MerianSchemaV34.ScanCollection]? = [],
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
            alternativeCommonNames: [String]? = nil) {

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
        }
    }
}
