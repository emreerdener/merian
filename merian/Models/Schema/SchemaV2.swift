import Foundation
import SwiftData

// Added: isLocallyArchived on LocalScanRecord
enum MerianSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self]
    }

    typealias OfflineQueuedScan = MerianSchemaV1.OfflineQueuedScan

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
        var referenceImageUrl: String?
        var additionalImagePaths: [String]?
        var confidenceScore: Double?
        @Attribute var isLocallyArchived: Bool = false

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
             referenceImageUrl: String? = nil,
             additionalImagePaths: [String]? = nil,
             confidenceScore: Double? = nil,
             isLocallyArchived: Bool = false) {

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
            self.referenceImageUrl = referenceImageUrl
            self.additionalImagePaths = additionalImagePaths
            self.confidenceScore = confidenceScore
            self.isLocallyArchived = isLocallyArchived
        }
    }
}
