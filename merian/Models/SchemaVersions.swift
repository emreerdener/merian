import Foundation
import SwiftData

enum MerianSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self]
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
        
        var isDeleted: Bool
        
        init(id: String = UUID().uuidString,
             timestamp: Date = Date(),
             localImagePaths: [String] = [],
             gpsLatitude: Double? = nil,
             gpsLongitude: Double? = nil,
             gpsElevation: Double? = nil,
             weatherCondition: String? = nil,
             weatherTemperatureF: Double? = nil,
             blurScore: Double? = nil,
             isDeleted: Bool = false) {
            
            self.id = id
            self.timestamp = timestamp
            self.localImagePaths = localImagePaths
            self.gpsLatitude = gpsLatitude
            self.gpsLongitude = gpsLongitude
            self.gpsElevation = gpsElevation
            self.weatherCondition = weatherCondition
            self.weatherTemperatureF = weatherTemperatureF
            self.blurScore = blurScore
            self.isDeleted = isDeleted
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
        var referenceImageUrl: String?
        var additionalImagePaths: [String]?
        var confidenceScore: Double?
        
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
             confidenceScore: Double? = nil) {
            
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
        }
    }
}

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

enum MerianSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self]
    }
    
    typealias OfflineQueuedScan = MerianSchemaV2.OfflineQueuedScan
    
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
        
        var taxonomyKingdom: String?
        var taxonomyPhylum: String?
        var taxonomyClass: String?
        var taxonomyOrder: String?
        var taxonomyFamily: String?
        var taxonomyGenus: String?
        
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
             isLocallyArchived: Bool = false,
             taxonomyKingdom: String? = nil,
             taxonomyPhylum: String? = nil,
             taxonomyClass: String? = nil,
             taxonomyOrder: String? = nil,
             taxonomyFamily: String? = nil,
             taxonomyGenus: String? = nil) {
            
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
            
            self.taxonomyKingdom = taxonomyKingdom
            self.taxonomyPhylum = taxonomyPhylum
            self.taxonomyClass = taxonomyClass
            self.taxonomyOrder = taxonomyOrder
            self.taxonomyFamily = taxonomyFamily
            self.taxonomyGenus = taxonomyGenus
        }
    }
}

enum MerianSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self]
    }
    
    typealias OfflineQueuedScan = MerianSchemaV3.OfflineQueuedScan
    
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
             taxonomyGenus: String? = nil) {
            
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
        }
    }
}

enum MerianSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self]
    }
    
    typealias OfflineQueuedScan = MerianSchemaV4.OfflineQueuedScan
    
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
             weatherTemperatureF: Double? = nil) {
            
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
        }
    }
}

enum MerianSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self]
    }
    
    @Model
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        
        @Relationship(inverse: \LocalScanRecord.collections) var scans: [LocalScanRecord]? = []
        
        init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), scans: [LocalScanRecord]? = []) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.scans = scans
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
        
        var isDeleted: Bool
        
        init(id: String = UUID().uuidString,
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
             isDeleted: Bool = false) {
            
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
            self.isDeleted = isDeleted
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
             collections: [ScanCollection]? = []) {
            
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
        }
    }
}

enum MerianSchemaV7: VersionedSchema {
    static var versionIdentifier = Schema.Version(7, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
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
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        
        @Relationship(inverse: \LocalScanRecord.collections) var scans: [LocalScanRecord]? = []
        
        init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), scans: [LocalScanRecord]? = []) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.scans = scans
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
        
        var isDeleted: Bool
        
        init(id: String = UUID().uuidString,
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
             isDeleted: Bool = false) {
            
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
            self.isDeleted = isDeleted
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
             collections: [ScanCollection]? = []) {
            
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
        }
    }
}

enum MerianSchemaV8: VersionedSchema {
    static var versionIdentifier = Schema.Version(8, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
    }
    
    typealias LocalScanRecord = MerianSchemaV7.LocalScanRecord
    typealias ScanCollection = MerianSchemaV7.ScanCollection
    typealias PendingCloudDeletionTask = MerianSchemaV7.PendingCloudDeletionTask
    
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
        
        var isDeleted: Bool
        
        init(id: String = UUID().uuidString,
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
             isDeleted: Bool = false) {
            
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
            self.isDeleted = isDeleted
        }
    }
}

enum MerianSchemaV9: VersionedSchema {
    static var versionIdentifier = Schema.Version(9, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
    }
    
    typealias OfflineQueuedScan = MerianSchemaV8.OfflineQueuedScan
    typealias PendingCloudDeletionTask = MerianSchemaV8.PendingCloudDeletionTask
    
    @Model
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        
        @Relationship(inverse: \LocalScanRecord.collections) var scans: [LocalScanRecord]? = []
        
        init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), scans: [LocalScanRecord]? = []) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
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
             diagnosticDifferentiatorsJson: String? = nil) {
            
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
        }
    }
}

enum MerianSchemaV10: VersionedSchema {
    static var versionIdentifier = Schema.Version(10, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
    }
    
    typealias OfflineQueuedScan = MerianSchemaV9.OfflineQueuedScan
    typealias PendingCloudDeletionTask = MerianSchemaV9.PendingCloudDeletionTask
    
    @Model
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        
        @Relationship(inverse: \LocalScanRecord.collections) var scans: [LocalScanRecord]? = []
        
        init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), scans: [LocalScanRecord]? = []) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
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
        
        @Attribute var iucnRedListStatus: String? = nil
        
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
             iucnRedListStatus: String? = nil) {
            
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
        }
    }
}

enum MerianMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MerianSchemaV1.self, MerianSchemaV2.self, MerianSchemaV3.self, MerianSchemaV4.self, MerianSchemaV5.self, MerianSchemaV6.self, MerianSchemaV7.self, MerianSchemaV8.self, MerianSchemaV9.self, MerianSchemaV10.self]
    }
    
    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6, migrateV6toV7, migrateV7toV8, migrateV8toV9, migrateV9toV10]
    }
    
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV1.self,
        toVersion: MerianSchemaV2.self
    )
    
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV2.self,
        toVersion: MerianSchemaV3.self
    )
    
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV3.self,
        toVersion: MerianSchemaV4.self
    )
    
    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV4.self,
        toVersion: MerianSchemaV5.self
    )
    
    static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV5.self,
        toVersion: MerianSchemaV6.self
    )
    
    static let migrateV6toV7 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV6.self,
        toVersion: MerianSchemaV7.self
    )
    
    static let migrateV7toV8 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV7.self,
        toVersion: MerianSchemaV8.self
    )
    
    static let migrateV8toV9 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV8.self,
        toVersion: MerianSchemaV9.self
    )
    
    static let migrateV9toV10 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV9.self,
        toVersion: MerianSchemaV10.self
    )
}
