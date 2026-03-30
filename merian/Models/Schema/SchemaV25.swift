import Foundation
import SwiftData

// Renamed: diagnosticLookalikeName (String) → diagnosticLookalikes ([String]) for multi-species support.
enum MerianSchemaV25: VersionedSchema {
    static var versionIdentifier = Schema.Version(25, 0, 0)

    static var models: [any PersistentModel.Type] {
        // Fully-qualified references lock each schema's checksum to its own frozen snapshot.
        // Classes are declared in the enum body (not extensions) so @Model macro expansion
        // uses the correct nested type for entity metadata — not the global ActiveSchema type.
        [MerianSchemaV25.LocalScanRecord.self, MerianSchemaV25.OfflineQueuedScan.self,
         MerianSchemaV25.ScanCollection.self, MerianSchemaV25.PendingCloudDeletionTask.self]
    }

    typealias PendingCloudDeletionTask = MerianSchemaV24.PendingCloudDeletionTask
    typealias OfflineQueuedScan        = MerianSchemaV24.OfflineQueuedScan

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

        var collections: [ScanCollection]? = []

        var diagnosticPrimaryRationale: String?
        var diagnosticLookalikes: [String]?
        var diagnosticDifferentiatorsJson: String?

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
             diagnosticPrimaryRationale: String? = nil,
             diagnosticLookalikes: [String]? = nil,
             diagnosticDifferentiatorsJson: String? = nil,
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

            self.diagnosticPrimaryRationale = diagnosticPrimaryRationale
            self.diagnosticLookalikes = diagnosticLookalikes
            self.diagnosticDifferentiatorsJson = diagnosticDifferentiatorsJson
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
