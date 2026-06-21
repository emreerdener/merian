import Foundation
import SwiftData

// MARK: - Migration Scratchpad

/// Thread-safe temporary storage for SwiftData migrations. `SchemaMigrationPlan` closures
/// (`willMigrate`, `didMigrate`) are synchronous and non-isolated, requiring `Sendable` captures.
final class MigrationScratchpad<V: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: [String: V]] = [:]

    subscript(namespace namespace: String, key key: String) -> V? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage[namespace]?[key]
        }
        set {
            lock.lock()
            var namespaced = storage[namespace] ?? [:]
            namespaced[key] = newValue
            storage[namespace] = namespaced
            lock.unlock()
        }
    }

    func removeAll(namespace: String) {
        lock.lock()
        storage.removeValue(forKey: namespace)
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}

enum MerianSchemaV40: VersionedSchema {
    static var versionIdentifier = Schema.Version(40, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV40.LocalScanRecord.self, MerianSchemaV40.OfflineQueuedScan.self,
         MerianSchemaV40.ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}

extension MerianSchemaV40 {
    @Model
    final class LocalScanRecord {
        @Attribute(.unique) var id: String
        var speciesId: String
        var scientificName: String
        var commonName: String
        var timestamp: Date
        var captureDate: Date?
        var capturedMediaJSON: String?

        var semanticTags: [String]
        var hazardType: String = "none"
        var isBiological: Bool
        var isLiveCapture: Bool
        var isInvasive: Bool
        var ecologyType: String
        var wikipediaUrl: String?
        @Attribute(originalName: "wikipediaExtract") var wikipediaOverview: String?
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

        var collections: [MerianSchemaV40.ScanCollection]? = []

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
        @Attribute var observationContextsJSON: [String]?
        @Attribute var coverImagePath: String?

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
            capturedMediaJSON: String? = nil,
            coverImagePath: String? = nil,
            semanticTags: [String] = [],
            hazardType: String = "none",
            isBiological: Bool = true,
            isLiveCapture: Bool = true,
            isInvasive: Bool = false,
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
            collections: [MerianSchemaV40.ScanCollection]? = [],
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
            observationContextsJSON: [String]? = nil
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
        }
    }

    @Model
    final class OfflineQueuedScan {
        @Attribute(.unique) var id: String
        var timestamp: Date
        var capturedMediaJSON: String?

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
            stagedR2Keys: [String]? = nil
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
        }
    }

    @Model
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        var isDeleted: Bool = false

        @Relationship(inverse: \MerianSchemaV40.LocalScanRecord.collections) var scans: [MerianSchemaV40.LocalScanRecord]? = []

        init(
            id: String = UUID().uuidString,
            name: String,
            createdAt: Date = Date(),
            isDeleted: Bool = false,
            scans: [MerianSchemaV40.LocalScanRecord]? = []
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.isDeleted = isDeleted
            self.scans = scans
        }
    }
}

final class MigrationScratchpadSet: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Set<String>] = [:]

    func insert(_ value: String, namespace: String) {
        lock.lock()
        var namespaced = storage[namespace] ?? []
        namespaced.insert(value)
        storage[namespace] = namespaced
        lock.unlock()
    }

    func contains(_ value: String, namespace: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage[namespace]?.contains(value) ?? false
    }

    func removeAll(namespace: String) {
        lock.lock()
        storage.removeValue(forKey: namespace)
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}

// MARK: - Migration Plan

enum MerianSchemaV41: VersionedSchema {
    static var versionIdentifier = Schema.Version(41, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV41.LocalScanRecord.self, MerianSchemaV41.OfflineQueuedScan.self, MerianSchemaV41.CapturedMediaEntry.self,
         MerianSchemaV41.ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}

extension MerianSchemaV41 {
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
                self.kindRaw = PersistedCapturedMediaKind.image.rawValue
                self.storageRaw = reference.storage.rawValue
                self.mediaPath = reference.serializedPath
                self.observationContextJSON = ""
            case .audio(let reference):
                self.kindRaw = PersistedCapturedMediaKind.audio.rawValue
                self.storageRaw = reference.storage.rawValue
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

        static func makeEntries(from items: [SerializedMediaItem]) -> [MerianSchemaV41.CapturedMediaEntry] {
            items.enumerated().map { index, item in
                MerianSchemaV41.CapturedMediaEntry(orderIndex: index, item: item)
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
        @Relationship(deleteRule: .cascade) var capturedMediaEntries: [MerianSchemaV41.CapturedMediaEntry]? = []

        var semanticTags: [String]
        var hazardType: String = "none"
        var isBiological: Bool
        var isLiveCapture: Bool
        var isInvasive: Bool
        var ecologyType: String
        var wikipediaUrl: String?
        @Attribute(originalName: "wikipediaExtract") var wikipediaOverview: String?
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

        var collections: [MerianSchemaV41.ScanCollection]? = []

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
        @Attribute var observationContextsJSON: [String]?
        @Attribute var coverImagePath: String?

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
            capturedMediaJSON: String? = nil,
            coverImagePath: String? = nil,
            semanticTags: [String] = [],
            hazardType: String = "none",
            isBiological: Bool = true,
            isLiveCapture: Bool = true,
            isInvasive: Bool = false,
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
            collections: [MerianSchemaV41.ScanCollection]? = [],
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
            observationContextsJSON: [String]? = nil
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
        }
    }

    @Model
    final class OfflineQueuedScan {
        @Attribute(.unique) var id: String
        var timestamp: Date
        var capturedMediaJSON: String?
        @Relationship(deleteRule: .cascade) var capturedMediaEntries: [MerianSchemaV41.CapturedMediaEntry]? = []

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
            stagedR2Keys: [String]? = nil
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
        }
    }

    @Model
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        var isDeleted: Bool = false

        @Relationship(inverse: \MerianSchemaV41.LocalScanRecord.collections) var scans: [MerianSchemaV41.LocalScanRecord]? = []

        init(
            id: String = UUID().uuidString,
            name: String,
            createdAt: Date = Date(),
            isDeleted: Bool = false,
            scans: [MerianSchemaV41.LocalScanRecord]? = []
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.isDeleted = isDeleted
            self.scans = scans
        }
    }
}

enum MerianSchemaV42: VersionedSchema {
    static var versionIdentifier = Schema.Version(42, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV42.LocalScanRecord.self, MerianSchemaV42.OfflineQueuedScan.self, MerianSchemaV42.CapturedMediaEntry.self,
         MerianSchemaV42.ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}

extension MerianSchemaV42 {
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
                self.kindRaw = PersistedCapturedMediaKind.image.rawValue
                self.storageRaw = reference.storage.rawValue
                self.mediaPath = reference.serializedPath
                self.observationContextJSON = ""
            case .audio(let reference):
                self.kindRaw = PersistedCapturedMediaKind.audio.rawValue
                self.storageRaw = reference.storage.rawValue
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
        @Relationship(deleteRule: .cascade) var capturedMediaEntries: [MerianSchemaV42.CapturedMediaEntry]? = []

        var semanticTags: [String]
        var hazardType: String = "none"
        var isBiological: Bool
        var isLiveCapture: Bool
        var isInvasive: Bool
        var ecologyType: String
        var wikipediaUrl: String?
        @Attribute(originalName: "wikipediaExtract") var wikipediaOverview: String?
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

        var collections: [MerianSchemaV42.ScanCollection]? = []

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
        @Attribute var observationContextsJSON: [String]?
        @Attribute var fieldNotes: String?
        @Attribute var coverImagePath: String?

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
            capturedMediaJSON: String? = nil,
            coverImagePath: String? = nil,
            semanticTags: [String] = [],
            hazardType: String = "none",
            isBiological: Bool = true,
            isLiveCapture: Bool = true,
            isInvasive: Bool = false,
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
            collections: [MerianSchemaV42.ScanCollection]? = [],
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
            self.fieldNotes = fieldNotes
        }
    }

    @Model
    final class OfflineQueuedScan {
        @Attribute(.unique) var id: String
        var timestamp: Date
        var capturedMediaJSON: String?
        @Relationship(deleteRule: .cascade) var capturedMediaEntries: [MerianSchemaV42.CapturedMediaEntry]? = []

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
        @Attribute var fieldNotes: String?
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
            fieldNotes: String? = nil
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
            self.fieldNotes = fieldNotes
        }
    }

    @Model
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        var isDeleted: Bool = false

        @Relationship(inverse: \MerianSchemaV42.LocalScanRecord.collections) var scans: [MerianSchemaV42.LocalScanRecord]? = []

        init(
            id: String = UUID().uuidString,
            name: String,
            createdAt: Date = Date(),
            isDeleted: Bool = false,
            scans: [MerianSchemaV42.LocalScanRecord]? = []
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.isDeleted = isDeleted
            self.scans = scans
        }
    }
}

enum MerianSchemaV43: VersionedSchema {
    static var versionIdentifier = Schema.Version(43, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, CapturedMediaEntry.self,
         ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}

enum MerianSchemaV44: VersionedSchema {
    static var versionIdentifier = Schema.Version(44, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, CapturedMediaEntry.self,
         ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}

// MARK: - Migration Plan
enum MerianMigrationPlan: SchemaMigrationPlan {
    private static func migrationNamespace(for context: ModelContext) -> String {
        context.container.configurations
            .map { $0.url.standardizedFileURL.path }
            .sorted()
            .joined(separator: "|")
    }

    private static func saveMigrationContext(_ context: ModelContext, stage: String) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            MerianLog.general.error("Migration \(stage) save failed; rolled back context: \(error.localizedDescription)")
            throw error
        }
    }

    private static func migrationFirstImagePath(in items: [SerializedMediaItem]) -> String? {
        for item in items {
            if case .image(let reference) = item {
                return reference.serializedPath
            }
        }
        return nil
    }

    private static func replaceMigratedCapturedMedia(
        on scan: MerianSchemaV41.LocalScanRecord,
        with items: [SerializedMediaItem]
    ) {
        if let context = scan.modelContext {
            for existingEntry in scan.capturedMediaEntries ?? [] {
                context.delete(existingEntry)
            }
        }

        scan.capturedMediaJSON = MediaJSONParser.jsonString(from: items)
        scan.coverImagePath = migrationFirstImagePath(in: items)
        scan.capturedMediaEntries = MerianSchemaV41.CapturedMediaEntry.makeEntries(from: items)
    }

    private static func replaceMigratedCapturedMedia(
        on scan: MerianSchemaV41.OfflineQueuedScan,
        with items: [SerializedMediaItem]
    ) {
        if let context = scan.modelContext {
            for existingEntry in scan.capturedMediaEntries ?? [] {
                context.delete(existingEntry)
            }
        }

        scan.capturedMediaJSON = MediaJSONParser.jsonString(from: items)
        scan.coverImagePath = migrationFirstImagePath(in: items)
        scan.capturedMediaEntries = MerianSchemaV41.CapturedMediaEntry.makeEntries(from: items)
    }

    static var schemas: [any VersionedSchema.Type] {
        [
            MerianSchemaV1.self,
            MerianSchemaV2.self,
            MerianSchemaV3.self,
            MerianSchemaV4.self,
            MerianSchemaV5.self,
            MerianSchemaV6.self,
            MerianSchemaV7.self,
            MerianSchemaV8.self,
            MerianSchemaV9.self,
            MerianSchemaV10.self,
            MerianSchemaV11.self,
            MerianSchemaV12.self,
            MerianSchemaV13.self,
            MerianSchemaV14.self,
            MerianSchemaV15.self,
            MerianSchemaV16.self,
            MerianSchemaV17.self,
            MerianSchemaV18.self,
            MerianSchemaV19.self,
            MerianSchemaV20.self,
            MerianSchemaV21.self,
            MerianSchemaV22.self,
            MerianSchemaV23.self,
            MerianSchemaV24.self,
            MerianSchemaV25.self,
            MerianSchemaV26.self,
            MerianSchemaV27.self,
            MerianSchemaV28.self,
            MerianSchemaV29.self,
            MerianSchemaV30.self,
            MerianSchemaV31.self,
            MerianSchemaV32.self,
            MerianSchemaV33.self,
            MerianSchemaV34.self,
            MerianSchemaV35.self,
            MerianSchemaV36.self,
            MerianSchemaV37.self,
            MerianSchemaV38.self,
            MerianSchemaV39.self,
            MerianSchemaV40.self,
            MerianSchemaV41.self,
            MerianSchemaV42.self,
            MerianSchemaV43.self,
            MerianSchemaV44.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            migrateV1toV2,
            migrateV2toV3,
            migrateV3toV4,
            migrateV4toV5,
            migrateV5toV6,
            migrateV6toV7,
            migrateV7toV8,
            migrateV8toV9,
            migrateV9toV10,
            migrateV10toV11,
            migrateV11toV12,
            migrateV12toV13,
            migrateV13toV14,
            migrateV14toV15,
            migrateV15toV16,
            migrateV16toV17,
            migrateV17toV18,
            migrateV18toV19,
            migrateV19toV20,
            migrateV20toV21,
            migrateV21toV22,
            migrateV22toV23,
            migrateV23toV24,
            migrateV24toV25,
            migrateV25toV26,
            migrateV26toV27,
            migrateV27toV28,
            migrateV28toV29,
            migrateV29toV30,
            migrateV30toV31,
            migrateV31toV32,
            migrateV32toV33,
            migrateV33toV34,
            migrateV34toV35,
            migrateV35toV36,
            migrateV36toV37,
            migrateV37toV38,
            migrateV38toV39,
            migrateV39toV40,
            migrateV40toV41,
            migrateV41toV42,
            migrateV42toV43,
            migrateV43toV44
        ]
    }

    static let migrateV43toV44 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV43.self,
        toVersion: MerianSchemaV44.self
    )

    static let migrateV41toV42 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV41.self,
        toVersion: MerianSchemaV42.self
    )

    static let migrateV42toV43 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV42.self,
        toVersion: MerianSchemaV43.self
    )

    // Lightweight: adds alternativeCommonNames column to LocalScanRecord and the
    // UserSpeciesPreference table. V33 has 4 entities; V34 has 5 (adds UserSpeciesPreference),
    // which anchors the checksum difference. All entities use global Swift classes in
    // both versions, so no cast errors occur during or after migration.
    static let migrateV33toV34 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV33.self,
        toVersion: MerianSchemaV34.self
    )

    static let migrateV34toV35 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV34.self,
        toVersion: MerianSchemaV35.self
    )

    static let migrateV35toV36 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV35.self,
        toVersion: MerianSchemaV36.self
    )

    static let migrateV36toV37 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV36.self,
        toVersion: MerianSchemaV37.self
    )

    static let migrateV37toV38 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV37.self,
        toVersion: MerianSchemaV38.self
    )

    static let _v38LocalAudioBackfill = MigrationScratchpad<[String]>()
    static let _v38LocalContextBackfill = MigrationScratchpad<[String]>()
    static let _v38OfflineAudioBackfill = MigrationScratchpad<[String]>()
    static let _v38OfflineContextBackfill = MigrationScratchpad<[String]>()
    static let _v38LocalAdditionalImagesBackfill = MigrationScratchpad<[String]>()
    static let _v38LocalSemanticTagsBackfill = MigrationScratchpad<[String]>()
    static let _v38OfflineLocalImagesBackfill = MigrationScratchpad<[String]>()

    static let migrateV38toV39 = MigrationStage.custom(
        fromVersion: MerianSchemaV38.self,
        toVersion: MerianSchemaV39.self,
        willMigrate: { context in
            let namespace = migrationNamespace(for: context)
            let localScans = try context.fetch(FetchDescriptor<MerianSchemaV38.LocalScanRecord>())
            for scan in localScans {
                if let audio = scan.audioFilePath {
                    _v38LocalAudioBackfill[namespace: namespace, key: scan.id] = [audio]
                }
                if let ctx = scan.observationContextJSON {
                    _v38LocalContextBackfill[namespace: namespace, key: scan.id] = [ctx]
                }
                if let images = scan.additionalImagePaths {
                    _v38LocalAdditionalImagesBackfill[namespace: namespace, key: scan.id] = images
                }
                _v38LocalSemanticTagsBackfill[namespace: namespace, key: scan.id] = scan.semanticTags
            }

            let offlineScans = try context.fetch(FetchDescriptor<MerianSchemaV38.OfflineQueuedScan>())
            for scan in offlineScans {
                if let audio = scan.audioFilePath {
                    _v38OfflineAudioBackfill[namespace: namespace, key: scan.id] = [audio]
                }
                if let ctx = scan.observationContextJSON {
                    _v38OfflineContextBackfill[namespace: namespace, key: scan.id] = [ctx]
                }
                _v38OfflineLocalImagesBackfill[namespace: namespace, key: scan.id] = scan.localImagePaths
            }
        },
        didMigrate: { context in
            let namespace = migrationNamespace(for: context)
            let localScans = try context.fetch(FetchDescriptor<MerianSchemaV39.LocalScanRecord>())
            for scan in localScans {
                if let audio = _v38LocalAudioBackfill[namespace: namespace, key: scan.id] {
                    scan.audioFilePaths = audio
                }
                if let ctx = _v38LocalContextBackfill[namespace: namespace, key: scan.id] {
                    scan.observationContextsJSON = ctx
                }
            }

            let offlineScans = try context.fetch(FetchDescriptor<MerianSchemaV39.OfflineQueuedScan>())
            for scan in offlineScans {
                if let audio = _v38OfflineAudioBackfill[namespace: namespace, key: scan.id] {
                    scan.audioFilePaths = audio
                }
                if let ctx = _v38OfflineContextBackfill[namespace: namespace, key: scan.id] {
                    scan.observationContextsJSON = ctx
                }
            }

            try saveMigrationContext(context, stage: "V38->V39 didMigrate")
            _v38LocalAudioBackfill.removeAll(namespace: namespace)
            _v38LocalContextBackfill.removeAll(namespace: namespace)
            _v38OfflineAudioBackfill.removeAll(namespace: namespace)
            _v38OfflineContextBackfill.removeAll(namespace: namespace)
            _v38LocalAdditionalImagesBackfill.removeAll(namespace: namespace)
            _v38LocalSemanticTagsBackfill.removeAll(namespace: namespace)
            _v38OfflineLocalImagesBackfill.removeAll(namespace: namespace)
        }
    )

    static let _v39LocalMediaBackfill = MigrationScratchpad<String>()
    static let _v39OfflineMediaBackfill = MigrationScratchpad<String>()
    static let _v39LocalCoverBackfill = MigrationScratchpad<String>()
    static let _v39OfflineCoverBackfill = MigrationScratchpad<String>()

    static let migrateV39toV40 = MigrationStage.custom(

        fromVersion: MerianSchemaV39.self,
        toVersion: MerianSchemaV40.self,
        willMigrate: { context in
            let namespace = migrationNamespace(for: context)
            // V39 to V40: backfill capturedMediaJSON
            let localScans = try context.fetch(FetchDescriptor<MerianSchemaV39.LocalScanRecord>())
            for scan in localScans {
                var items: [SerializedMediaItem] = []
                
                // Historical best-approximation sequence: Image -> Description -> Audio
                if let localPath = scan.localImagePath {
                    items.append(.image(StoredMediaReference(legacyPath: localPath)))
                }
                for path in scan.additionalImagePaths ?? [] {
                    items.append(.image(StoredMediaReference(legacyPath: path)))
                }
                
                if let contextsJSON = scan.observationContextsJSON {
                    for ctxJSON in contextsJSON {
                        if let data = ctxJSON.data(using: .utf8),
                           let ctx = try? JSONDecoder().decode(ObservationContext.self, from: data) {
                            items.append(.description(ctx))
                        }
                    }
                }
                
                for audioPath in scan.audioFilePaths ?? [] {
                    items.append(.audio(StoredMediaReference(legacyPath: audioPath)))
                }
                
                if let data = try? JSONEncoder().encode(items) {
                    _v39LocalMediaBackfill[namespace: namespace, key: scan.id] = String(data: data, encoding: .utf8)
                }
                if let firstImage = items.first(where: { if case .image = $0 { return true } else { return false } }) {
                    if case .image(let reference) = firstImage {
                        _v39LocalCoverBackfill[namespace: namespace, key: scan.id] = reference.serializedPath
                    }
                }
            }

            let offlineScans = try context.fetch(FetchDescriptor<MerianSchemaV39.OfflineQueuedScan>())
            for scan in offlineScans {
                var items: [SerializedMediaItem] = []
                
                for path in scan.localImagePaths {
                    items.append(.image(StoredMediaReference(legacyPath: path)))
                }
                
                if let contextsJSON = scan.observationContextsJSON {
                    for ctxJSON in contextsJSON {
                        if let data = ctxJSON.data(using: .utf8),
                           let ctx = try? JSONDecoder().decode(ObservationContext.self, from: data) {
                            items.append(.description(ctx))
                        }
                    }
                }
                
                for audioPath in scan.audioFilePaths ?? [] {
                    items.append(.audio(StoredMediaReference(legacyPath: audioPath)))
                }
                
                if let data = try? JSONEncoder().encode(items) {
                    _v39OfflineMediaBackfill[namespace: namespace, key: scan.id] = String(data: data, encoding: .utf8)
                }
                if let firstImage = items.first(where: { if case .image = $0 { return true } else { return false } }) {
                    if case .image(let reference) = firstImage {
                        _v39OfflineCoverBackfill[namespace: namespace, key: scan.id] = reference.serializedPath
                    }
                }
            }
        },
        didMigrate: { context in
            let namespace = migrationNamespace(for: context)
            let localScans = try context.fetch(FetchDescriptor<MerianSchemaV40.LocalScanRecord>())
            for scan in localScans {
                if let json = _v39LocalMediaBackfill[namespace: namespace, key: scan.id] {
                    scan.capturedMediaJSON = json
                    scan.coverImagePath = _v39LocalCoverBackfill[namespace: namespace, key: scan.id]
                } else {
                    scan.capturedMediaJSON = "[]"
                }
            }
            
            let offlineScans = try context.fetch(FetchDescriptor<MerianSchemaV40.OfflineQueuedScan>())
            for scan in offlineScans {
                if let json = _v39OfflineMediaBackfill[namespace: namespace, key: scan.id] {
                    scan.capturedMediaJSON = json
                    scan.coverImagePath = _v39OfflineCoverBackfill[namespace: namespace, key: scan.id]
                } else {
                    scan.capturedMediaJSON = "[]"
                }
            }
            
            try saveMigrationContext(context, stage: "V39->V40 didMigrate")
            _v39LocalMediaBackfill.removeAll(namespace: namespace)
            _v39OfflineMediaBackfill.removeAll(namespace: namespace)
            _v39LocalCoverBackfill.removeAll(namespace: namespace)
            _v39OfflineCoverBackfill.removeAll(namespace: namespace)
        }
    )

    static let migrateV40toV41 = MigrationStage.custom(
        fromVersion: MerianSchemaV40.self,
        toVersion: MerianSchemaV41.self,
        willMigrate: { _ in },
        didMigrate: { context in
            let localScans = try context.fetch(FetchDescriptor<MerianSchemaV41.LocalScanRecord>())
            for scan in localScans {
                guard scan.capturedMediaEntries?.isEmpty ?? true,
                      let jsonString = scan.capturedMediaJSON,
                      let items = MediaJSONParser.serializedItems(jsonString: jsonString) else {
                    continue
                }
                replaceMigratedCapturedMedia(on: scan, with: items)
            }

            let offlineScans = try context.fetch(FetchDescriptor<MerianSchemaV41.OfflineQueuedScan>())
            for scan in offlineScans {
                guard scan.capturedMediaEntries?.isEmpty ?? true,
                      let jsonString = scan.capturedMediaJSON,
                      let items = MediaJSONParser.serializedItems(jsonString: jsonString) else {
                    continue
                }
                replaceMigratedCapturedMedia(on: scan, with: items)
            }

            try saveMigrationContext(context, stage: "V40->V41 didMigrate")
        }
    )

    // Temporary backfill storage for V32→V33 migration.
    // Captures the old Bool state before the column is dropped, then writes scanStateRaw in didMigrate.
    static let _scanStateBackfill = MigrationScratchpad<Int>()

    static let migrateV32toV33 = MigrationStage.custom(
        fromVersion: MerianSchemaV32.self,
        toVersion: MerianSchemaV33.self,
        willMigrate: { context in
            let namespace = migrationNamespace(for: context)
            let scans = try context.fetch(FetchDescriptor<MerianSchemaV32.OfflineQueuedScan>())
            for scan in scans {
                let state: Int
                if scan.isDeleted {
                    state = ScanQueueState.failed.rawValue
                } else if scan.isUploaded {
                    state = ScanQueueState.staged.rawValue
                } else {
                    state = ScanQueueState.pending.rawValue
                }
                _scanStateBackfill[namespace: namespace, key: scan.id] = state
            }
        },
        didMigrate: { context in
            let namespace = migrationNamespace(for: context)
            let scans = try context.fetch(FetchDescriptor<MerianSchemaV33.OfflineQueuedScan>())
            for scan in scans {
                if let state = _scanStateBackfill[namespace: namespace, key: scan.id] {
                    scan.scanStateRaw = state
                }
            }
            try saveMigrationContext(context, stage: "V32->V33 didMigrate")
            _scanStateBackfill.removeAll(namespace: namespace)
        }
    )

    static let migrateV31toV32 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV31.self,
        toVersion: MerianSchemaV32.self
    )

    static let migrateV30toV31 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV30.self,
        toVersion: MerianSchemaV31.self
    )

    static let migrateV29toV30 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV29.self,
        toVersion: MerianSchemaV30.self
    )

    static let migrateV28toV29 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV28.self,
        toVersion: MerianSchemaV29.self
    )

    static let migrateV27toV28 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV27.self,
        toVersion: MerianSchemaV28.self
    )

    static let migrateV26toV27 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV26.self,
        toVersion: MerianSchemaV27.self
    )

    static let migrateV19toV20 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV19.self,
        toVersion: MerianSchemaV20.self
    )

    static let migrateV20toV21 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV20.self,
        toVersion: MerianSchemaV21.self
    )

    static let migrateV21toV22 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV21.self,
        toVersion: MerianSchemaV22.self
    )

    static let migrateV22toV23 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV22.self,
        toVersion: MerianSchemaV23.self
    )

    static let migrateV23toV24 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV23.self,
        toVersion: MerianSchemaV24.self
    )

    static let migrateV24toV25 = MigrationStage.custom(
        fromVersion: MerianSchemaV24.self,
        toVersion: MerianSchemaV25.self,
        willMigrate: { context in
            let namespace = migrationNamespace(for: context)
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV24.LocalScanRecord>())
            for record in allRecords {
                if let string = record.diagnosticLookalikeName, !string.isEmpty {
                    let array = string.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    _diagnosticLookalikesBackfill[namespace: namespace, key: record.id] = array
                }
            }
        },
        didMigrate: { context in
            let namespace = migrationNamespace(for: context)
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV25.LocalScanRecord>())
            for record in allRecords {
                if let array = _diagnosticLookalikesBackfill[namespace: namespace, key: record.id] {
                    record.diagnosticLookalikes = array
                }
            }
            try saveMigrationContext(context, stage: "V24->V25 didMigrate")
            _diagnosticLookalikesBackfill.removeAll(namespace: namespace)
        }
    )

    // Temporary storage for preserving the lookalikes array when discarding diagnostic string columns for V26.
    static let _similarSpeciesBackfill = MigrationScratchpad<[String]>()

    static let migrateV25toV26 = MigrationStage.custom(
        fromVersion: MerianSchemaV25.self,
        toVersion: MerianSchemaV26.self,
        willMigrate: { context in
            let namespace = migrationNamespace(for: context)
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV25.LocalScanRecord>())
            for record in allRecords {
                if let lookalikes = record.diagnosticLookalikes, !lookalikes.isEmpty {
                    _similarSpeciesBackfill[namespace: namespace, key: record.id] = lookalikes
                }
            }
        },
        didMigrate: { context in
            let namespace = migrationNamespace(for: context)
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV26.LocalScanRecord>())
            for record in allRecords {
                if let array = _similarSpeciesBackfill[namespace: namespace, key: record.id] {
                    record.similarSpecies = array
                }
            }
            try saveMigrationContext(context, stage: "V25->V26 didMigrate")
            _similarSpeciesBackfill.removeAll(namespace: namespace)
        }
    )

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

    static let migrateV10toV11 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV10.self,
        toVersion: MerianSchemaV11.self
    )

    static let migrateV11toV12 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV11.self,
        toVersion: MerianSchemaV12.self
    )

    static let migrateV12toV13 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV12.self,
        toVersion: MerianSchemaV13.self
    )

    static let migrateV13toV14 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV13.self,
        toVersion: MerianSchemaV14.self
    )

    static let migrateV14toV15 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV14.self,
        toVersion: MerianSchemaV15.self
    )

    // Temporary storage for passing poisonous IDs from willMigrate (V15 context) to didMigrate (V16 context).
    static let _poisonousIds = MigrationScratchpadSet()

    // Temporary storage for backfilling aiReasoning from insightDescription for pre-V16 records.
    static let _insightDescriptionBackfill = MigrationScratchpad<String>()

    // Temporary storage for migrating diagnosticLookalikeName (comma-separated string) to diagnosticLookalikes (array) for pre-V25 records.
    static let _diagnosticLookalikesBackfill = MigrationScratchpad<[String]>()

    static let migrateV15toV16 = MigrationStage.custom(
        fromVersion: MerianSchemaV15.self,
        toVersion: MerianSchemaV16.self,
        willMigrate: { context in
            let namespace = migrationNamespace(for: context)
            // Read all records that were marked isPoisonous = true in V15.
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV15.LocalScanRecord>())
            for record in allRecords where record.isPoisonous {
                _poisonousIds.insert(record.id, namespace: namespace)
            }
        },
        didMigrate: { context in
            let namespace = migrationNamespace(for: context)
            // Set hazardType = "poisonous" for the records that had isPoisonous = true.
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV16.LocalScanRecord>())
            for record in allRecords where _poisonousIds.contains(record.id, namespace: namespace) {
                record.hazardType = "poisonous"
            }
            try saveMigrationContext(context, stage: "V15->V16 didMigrate")
            _poisonousIds.removeAll(namespace: namespace)
        }
    )

    static let migrateV17toV18 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV17.self,
        toVersion: MerianSchemaV18.self
    )

    static let migrateV18toV19 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV18.self,
        toVersion: MerianSchemaV19.self
    )

    static let migrateV16toV17 = MigrationStage.custom(
        fromVersion: MerianSchemaV16.self,
        toVersion: MerianSchemaV17.self,
        willMigrate: { context in
            let namespace = migrationNamespace(for: context)
            // Preserve insight descriptions for records that never had aiReasoning set.
            // insightDescription is removed in V17; copy its value into aiReasoning for continuity.
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV16.LocalScanRecord>())
            for record in allRecords {
                if record.aiReasoning == nil && !record.insightDescription.isEmpty {
                    _insightDescriptionBackfill[namespace: namespace, key: record.id] = record.insightDescription
                }
            }
        },
        didMigrate: { context in
            let namespace = migrationNamespace(for: context)
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV17.LocalScanRecord>())
            for record in allRecords {
                if let description = _insightDescriptionBackfill[namespace: namespace, key: record.id] {
                    record.aiReasoning = description
                }
            }
            try saveMigrationContext(context, stage: "V16->V17 didMigrate")
            _insightDescriptionBackfill.removeAll(namespace: namespace)
        }
    )
}
