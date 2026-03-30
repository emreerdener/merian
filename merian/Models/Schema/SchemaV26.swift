import Foundation
import SwiftData

// Removed: diagnosticPrimaryRationale, diagnosticDifferentiatorsJson
// Renamed: diagnosticLookalikes → similarSpecies (backfilled via migrateV25toV26)
enum MerianSchemaV26: VersionedSchema {
    static var versionIdentifier = Schema.Version(26, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV26.LocalScanRecord.self, MerianSchemaV26.OfflineQueuedScan.self,
         MerianSchemaV26.ScanCollection.self, MerianSchemaV26.PendingCloudDeletionTask.self]
    }

    typealias PendingCloudDeletionTask = MerianSchemaV25.PendingCloudDeletionTask
    typealias OfflineQueuedScan        = MerianSchemaV25.OfflineQueuedScan

    // ScanCollection redeclared so its inverse relationship points to V26.LocalScanRecord.
    // Using typealias MerianSchemaV25.ScanCollection would embed a relationship to V25.LocalScanRecord
    // by Swift type identity, causing iOS 26 to resolve V25 and V26 to the same NSManagedObjectModel.
    @Model
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        var isDeleted: Bool = false

        @Relationship(inverse: \LocalScanRecord.collections) var scans: [LocalScanRecord]? = []

        init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), isDeleted: Bool = false, scans: [LocalScanRecord]? = []) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.isDeleted = isDeleted
            self.scans = scans
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

        var collections: [ScanCollection]? = []

        var similarSpecies: [String]?

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

        init(id: String = UUID().uuidString,
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
             hasBeenViewed: Bool = false) {

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
        }
    }
}
