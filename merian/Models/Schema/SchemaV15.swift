import Foundation
import SwiftData

// Added: aiReasoning, habitatDescription, and globalDistributionRegions for Premium Insights
enum MerianSchemaV15: VersionedSchema {
    static var versionIdentifier = Schema.Version(15, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
    }

    typealias PendingCloudDeletionTask = MerianSchemaV14.PendingCloudDeletionTask
    typealias OfflineQueuedScan = MerianSchemaV14.OfflineQueuedScan

    // ScanCollection is redeclared (structurally identical to V14) so its inverse relationship
    // points to V15.LocalScanRecord instead of V14.LocalScanRecord. Without this, SwiftData
    // computes the same checksum for V14 and V15, crashing with "Duplicate version checksums".
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
        var insightDescription: String
        var timestamp: Date
        var localImagePath: String?

        var semanticTags: [String]
        var isPoisonous: Bool
        var isBiological: Bool
        var isLiveCapture: Bool
        var isInvasive: Bool
        var ecologyType: String
        var wikipediaUrl: String?
        var wikipediaExtract: String?
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

        var diagnosticPrimaryRationale: String?
        var diagnosticLookalikeName: String?
        var diagnosticDifferentiatorsJson: String?

        @Attribute var iucnRedListStatus: String?
        @Attribute var gpsLatitude: Double?
        @Attribute var gpsLongitude: Double?
        @Attribute var gpsElevation: Double?
        @Attribute var zoomFactor: Double?
        
        // Premium Insights Features
        @Attribute var aiReasoning: String?
        @Attribute var habitatDescription: String?
        @Attribute var globalDistributionRegionsJson: String?

        init(id: String = UUID().uuidString,
             speciesId: String,
             scientificName: String,
             commonName: String,
             insightDescription: String,
             timestamp: Date = Date(),
             localImagePath: String? = nil,
             semanticTags: [String] = [],
             isPoisonous: Bool = false,
             isBiological: Bool = true,
             isLiveCapture: Bool = true,
             isInvasive: Bool = false,
             ecologyType: String = "unknown",
             wikipediaUrl: String? = nil,
             wikipediaExtract: String? = nil,
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
             diagnosticPrimaryRationale: String? = nil,
             diagnosticLookalikeName: String? = nil,
             diagnosticDifferentiatorsJson: String? = nil,
             iucnRedListStatus: String? = nil,
             gpsLatitude: Double? = nil,
             gpsLongitude: Double? = nil,
             gpsElevation: Double? = nil,
             zoomFactor: Double? = nil,
             aiReasoning: String? = nil,
             habitatDescription: String? = nil,
             globalDistributionRegionsJson: String? = nil) {

            self.id = id
            self.speciesId = speciesId
            self.scientificName = scientificName
            self.commonName = commonName
            self.insightDescription = insightDescription
            self.timestamp = timestamp
            self.localImagePath = localImagePath
            self.semanticTags = semanticTags
            self.isPoisonous = isPoisonous
            self.isBiological = isBiological
            self.isLiveCapture = isLiveCapture
            self.isInvasive = isInvasive
            self.ecologyType = ecologyType
            self.wikipediaUrl = wikipediaUrl
            self.wikipediaExtract = wikipediaExtract
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

            self.diagnosticPrimaryRationale = diagnosticPrimaryRationale
            self.diagnosticLookalikeName = diagnosticLookalikeName
            self.diagnosticDifferentiatorsJson = diagnosticDifferentiatorsJson
            self.iucnRedListStatus = iucnRedListStatus
            self.gpsLatitude = gpsLatitude
            self.gpsLongitude = gpsLongitude
            self.gpsElevation = gpsElevation
            self.zoomFactor = zoomFactor
            
            self.aiReasoning = aiReasoning
            self.habitatDescription = habitatDescription
            self.globalDistributionRegionsJson = globalDistributionRegionsJson
        }
    }
}
