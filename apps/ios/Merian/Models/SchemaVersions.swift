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

    func values(namespace: String) -> [V] {
        lock.lock()
        defer { lock.unlock() }
        guard let namespaced = storage[namespace] else { return [] }
        return Array(namespaced.values)
    }

    func allValues() -> [V] {
        lock.lock()
        defer { lock.unlock() }
        return storage.values.flatMap { Array($0.values) }
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
        [MerianSchemaV43.LocalScanRecord.self, MerianSchemaV43.OfflineQueuedScan.self, MerianSchemaV43.CapturedMediaEntry.self,
         MerianSchemaV43.ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}

enum MerianSchemaV44: VersionedSchema {
    static var versionIdentifier = Schema.Version(44, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV44.LocalScanRecord.self, MerianSchemaV44.OfflineQueuedScan.self, MerianSchemaV44.CapturedMediaEntry.self,
         MerianSchemaV44.ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}

enum MerianSchemaV45: VersionedSchema {
    static var versionIdentifier = Schema.Version(45, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV45.LocalScanRecord.self, MerianSchemaV45.OfflineQueuedScan.self, MerianSchemaV45.CapturedMediaEntry.self,
         MerianSchemaV45.ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}

enum MerianSchemaV46: VersionedSchema {
    static var versionIdentifier = Schema.Version(46, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV46.LocalScanRecord.self, MerianSchemaV46.OfflineQueuedScan.self, MerianSchemaV46.CapturedMediaEntry.self,
         MerianSchemaV46.ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}

enum MerianSchemaV47: VersionedSchema {
    static var versionIdentifier = Schema.Version(47, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV47.LocalScanRecord.self, MerianSchemaV47.OfflineQueuedScan.self, MerianSchemaV47.CapturedMediaEntry.self,
         MerianSchemaV47.ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}

enum MerianSchemaV48: VersionedSchema {
    static var versionIdentifier = Schema.Version(48, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, MerianSchemaV48.OfflineQueuedScan.self, CapturedMediaEntry.self,
         ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self, OfflineJobRecord.self, OfflineQueueEvent.self]
    }
}

enum MerianSchemaV48OptionalQueue: VersionedSchema {
    static var versionIdentifier = Schema.Version(48, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, MerianSchemaV48OptionalQueue.OfflineQueuedScan.self, CapturedMediaEntry.self,
         ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self, OfflineJobRecord.self, OfflineQueueEvent.self]
    }
}

enum MerianSchemaV49: VersionedSchema {
    static var versionIdentifier = Schema.Version(49, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, CapturedMediaEntry.self,
         ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self, OfflineJobRecord.self, OfflineQueueEvent.self]
    }
}

enum MerianSchemaV50: VersionedSchema {
    static var versionIdentifier = Schema.Version(50, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, MerianSchemaV49OfflineQueuedScan.self, CapturedMediaEntry.self,
         ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self, OfflineJobRecord.self, OfflineQueueEvent.self,
         MerianSchemaV50.OfflineQueuedScanGoalHint.self]
    }
}

private typealias MerianSchemaV49OfflineQueuedScan = OfflineQueuedScan
private typealias MerianSchemaV49OfflineJobRecord = OfflineJobRecord
private typealias MerianSchemaV49OfflineQueueEvent = OfflineQueueEvent

extension MerianSchemaV50 {
    /// Durable preference captured from the live Capture UI for a queued scan.
    ///
    /// This scan-keyed companion keeps the released V49 queue entity byte-for-byte
    /// stable while allowing V50 to add the two optional-as-a-pair goal identifiers.
    /// Rows are created only when Capture supplies an eligible preferred goal.
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

extension MerianSchemaV48 {
    fileprivate typealias OfflineJobRecord = MerianSchemaV49OfflineJobRecord
    fileprivate typealias OfflineQueueEvent = MerianSchemaV49OfflineQueueEvent

    @Model
    final class OfflineQueuedScan {
        @Attribute(.unique) var id: String
        var timestamp: Date
        var capturedMediaJSON: String?
        @Relationship(deleteRule: .cascade) var capturedMediaEntries: [CapturedMediaEntry]? = []

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
        @Attribute var coverImagePath: String?

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
            queueNeedsAttention: Bool = false
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
        }
    }
}

extension MerianSchemaV48OptionalQueue {
    @Model
    final class OfflineQueuedScan {
        @Attribute(.unique) var id: String
        var timestamp: Date
        var capturedMediaJSON: String?
        @Relationship(deleteRule: .cascade) var capturedMediaEntries: [CapturedMediaEntry]? = []

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
        @Attribute var queueAttemptCount: Int?
        @Attribute var queueLastAttemptAt: Date?
        @Attribute var queueNextRetryAt: Date?
        @Attribute var queueLastErrorCode: String?
        @Attribute var queueLastErrorMessage: String?
        @Attribute var queueLastHTTPStatus: Int?
        @Attribute var queueLastServerStatus: String?
        @Attribute var queueLastServerStage: String?
        @Attribute var queueLastServerRetryAfter: Date?
        @Attribute var queueUpdatedAt: Date?
        @Attribute var queueNeedsAttention: Bool?
        @Attribute var coverImagePath: String?

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
            queueAttemptCount: Int? = nil,
            queueLastAttemptAt: Date? = nil,
            queueNextRetryAt: Date? = nil,
            queueLastErrorCode: String? = nil,
            queueLastErrorMessage: String? = nil,
            queueLastHTTPStatus: Int? = nil,
            queueLastServerStatus: String? = nil,
            queueLastServerStage: String? = nil,
            queueLastServerRetryAfter: Date? = nil,
            queueUpdatedAt: Date? = nil,
            queueNeedsAttention: Bool? = nil
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
        }
    }
}

extension MerianSchemaV49 {
    fileprivate typealias OfflineQueuedScan = MerianSchemaV49OfflineQueuedScan
    fileprivate typealias OfflineJobRecord = MerianSchemaV49OfflineJobRecord
    fileprivate typealias OfflineQueueEvent = MerianSchemaV49OfflineQueueEvent
}

extension MerianSchemaV47 {
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
                observationContextJSON = contextData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
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
        @Relationship(deleteRule: .cascade) var capturedMediaEntries: [MerianSchemaV47.CapturedMediaEntry]? = []

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

        var collections: [MerianSchemaV47.ScanCollection]? = []

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
            collections: [MerianSchemaV47.ScanCollection]? = [],
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
            self.observationContextsJSON = observationContextsJSON
            self.fieldNotes = fieldNotes
        }
    }

    @Model
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        var isDeleted: Bool = false

        @Relationship(inverse: \MerianSchemaV47.LocalScanRecord.collections) var scans: [MerianSchemaV47.LocalScanRecord]? = []

        init(
            id: String = UUID().uuidString,
            name: String,
            createdAt: Date = Date(),
            isDeleted: Bool = false,
            scans: [MerianSchemaV47.LocalScanRecord]? = []
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.isDeleted = isDeleted
            self.scans = scans
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
        @Attribute var inferenceImagePaths: [String]?
        @Attribute var visualMediaItemsJSON: String?
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
            inferenceImagePaths: [String]? = nil,
            visualMediaItemsJSON: String? = nil,
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
            self.inferenceImagePaths = inferenceImagePaths
            self.visualMediaItemsJSON = visualMediaItemsJSON
            self.fieldNotes = fieldNotes
        }
    }
}

extension MerianSchemaV44 {
    typealias CapturedMediaEntry = MerianSchemaV43.CapturedMediaEntry
    typealias OfflineQueuedScan = MerianSchemaV43.OfflineQueuedScan

    @Model
    final class LocalScanRecord {
        @Attribute(.unique) var id: String
        var speciesId: String
        var scientificName: String
        var commonName: String
        var timestamp: Date
        var captureDate: Date?
        var capturedMediaJSON: String?
        @Relationship(deleteRule: .cascade) var capturedMediaEntries: [CapturedMediaEntry]? = []

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

        var collections: [MerianSchemaV44.ScanCollection]? = []

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
            collections: [MerianSchemaV44.ScanCollection]? = [],
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
            self.observationContextsJSON = observationContextsJSON
            self.fieldNotes = fieldNotes
        }
    }

    @Model
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        var isDeleted: Bool = false

        @Relationship(inverse: \MerianSchemaV44.LocalScanRecord.collections) var scans: [MerianSchemaV44.LocalScanRecord]? = []

        init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), isDeleted: Bool = false, scans: [MerianSchemaV44.LocalScanRecord]? = []) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.isDeleted = isDeleted
            self.scans = scans
        }
    }
}

extension MerianSchemaV45 {
    typealias CapturedMediaEntry = MerianSchemaV44.CapturedMediaEntry
    typealias OfflineQueuedScan = MerianSchemaV44.OfflineQueuedScan

    @Model
    final class LocalScanRecord {
        @Attribute(.unique) var id: String
        var speciesId: String
        var scientificName: String
        var commonName: String
        var timestamp: Date
        var captureDate: Date?
        var capturedMediaJSON: String?
        @Relationship(deleteRule: .cascade) var capturedMediaEntries: [MerianSchemaV45.CapturedMediaEntry]? = []

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

        var collections: [MerianSchemaV45.ScanCollection]? = []

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
            collections: [MerianSchemaV45.ScanCollection]? = [],
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
            self.observationContextsJSON = observationContextsJSON
            self.fieldNotes = fieldNotes
        }
    }

    @Model
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        var isDeleted: Bool = false

        @Relationship(inverse: \MerianSchemaV45.LocalScanRecord.collections) var scans: [MerianSchemaV45.LocalScanRecord]? = []

        init(
            id: String = UUID().uuidString,
            name: String,
            createdAt: Date = Date(),
            isDeleted: Bool = false,
            scans: [MerianSchemaV45.LocalScanRecord]? = []
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.isDeleted = isDeleted
            self.scans = scans
        }
    }
}

extension MerianSchemaV46 {
    typealias CapturedMediaEntry = MerianSchemaV45.CapturedMediaEntry
    typealias OfflineQueuedScan = MerianSchemaV45.OfflineQueuedScan

    @Model
    final class LocalScanRecord {
        @Attribute(.unique) var id: String
        var speciesId: String
        var scientificName: String
        var commonName: String
        var timestamp: Date
        var captureDate: Date?
        var capturedMediaJSON: String?
        @Relationship(deleteRule: .cascade) var capturedMediaEntries: [MerianSchemaV46.CapturedMediaEntry]? = []

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

        var collections: [MerianSchemaV46.ScanCollection]? = []

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
            collections: [MerianSchemaV46.ScanCollection]? = [],
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
            self.observationContextsJSON = observationContextsJSON
            self.fieldNotes = fieldNotes
        }
    }

    @Model
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        var isDeleted: Bool = false

        @Relationship(inverse: \MerianSchemaV46.LocalScanRecord.collections) var scans: [MerianSchemaV46.LocalScanRecord]? = []

        init(
            id: String = UUID().uuidString,
            name: String,
            createdAt: Date = Date(),
            isDeleted: Bool = false,
            scans: [MerianSchemaV46.LocalScanRecord]? = []
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.isDeleted = isDeleted
            self.scans = scans
        }
    }
}

extension MerianSchemaV43 {
    typealias CapturedMediaEntry = MerianSchemaV42.CapturedMediaEntry
    typealias OfflineQueuedScan = MerianSchemaV42.OfflineQueuedScan

    @Model
    final class LocalScanRecord {
        @Attribute(.unique) var id: String
        var speciesId: String
        var scientificName: String
        var commonName: String
        var timestamp: Date
        var captureDate: Date?
        var capturedMediaJSON: String?
        @Relationship(deleteRule: .cascade) var capturedMediaEntries: [MerianSchemaV43.CapturedMediaEntry]? = []

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

        var collections: [MerianSchemaV43.ScanCollection]? = []

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
            collections: [MerianSchemaV43.ScanCollection]? = [],
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
            self.confirmedSpeciesId = confirmedSpeciesId
            self.userReviewStateRaw = userReviewStateRaw
            self.observationContextsJSON = observationContextsJSON
            self.fieldNotes = fieldNotes
        }
    }

    @Model
    final class ScanCollection {
        @Attribute(.unique) var id: String = UUID().uuidString
        var name: String
        var createdAt: Date = Date()
        var isDeleted: Bool = false

        @Relationship(inverse: \MerianSchemaV43.LocalScanRecord.collections) var scans: [MerianSchemaV43.LocalScanRecord]? = []

        init(
            id: String = UUID().uuidString,
            name: String,
            createdAt: Date = Date(),
            isDeleted: Bool = false,
            scans: [MerianSchemaV43.LocalScanRecord]? = []
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.isDeleted = isDeleted
            self.scans = scans
        }
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

    private struct V49QueuedScanMigrationSnapshot: Sendable {
        let id: String
        let timestamp: Date
        let capturedMediaJSON: String?
        let coverImagePath: String?
        let gpsLatitude: Double?
        let gpsLongitude: Double?
        let gpsElevation: Double?
        let weatherCondition: String?
        let weatherTemperatureF: Double?
        let blurScore: Double?
        let subjectDistanceInMeters: Float?
        let locationName: String?
        let isFlashFired: Bool?
        let cameraPitchDegrees: Double?
        let compassHeading: Double?
        let relativeHumidity: Double?
        let uvIndex: Int?
        let zoomFactor: Double?
        let scanStateRaw: Int
        let stagedR2Keys: [String]?
        let inferenceImagePaths: [String]?
        let visualMediaItemsJSON: String?
        let fieldNotes: String?
        let queueAttemptCount: Int?
        let queueLastAttemptAt: Date?
        let queueNextRetryAt: Date?
        let queueLastErrorCode: String?
        let queueLastErrorMessage: String?
        let queueLastHTTPStatus: Int?
        let queueLastServerStatus: String?
        let queueLastServerStage: String?
        let queueLastServerRetryAfter: Date?
        let queueUpdatedAt: Date?
        let queueNeedsAttention: Bool?

        init(_ scan: MerianSchemaV42.OfflineQueuedScan) {
            id = scan.id
            timestamp = scan.timestamp
            capturedMediaJSON = scan.capturedMediaJSON
            coverImagePath = scan.coverImagePath
            gpsLatitude = scan.gpsLatitude
            gpsLongitude = scan.gpsLongitude
            gpsElevation = scan.gpsElevation
            weatherCondition = scan.weatherCondition
            weatherTemperatureF = scan.weatherTemperatureF
            blurScore = scan.blurScore
            subjectDistanceInMeters = scan.subjectDistanceInMeters
            locationName = scan.locationName
            isFlashFired = scan.isFlashFired
            cameraPitchDegrees = scan.cameraPitchDegrees
            compassHeading = scan.compassHeading
            relativeHumidity = scan.relativeHumidity
            uvIndex = scan.uvIndex
            zoomFactor = scan.zoomFactor
            scanStateRaw = scan.scanStateRaw
            stagedR2Keys = scan.stagedR2Keys
            inferenceImagePaths = nil
            visualMediaItemsJSON = nil
            fieldNotes = scan.fieldNotes
            queueAttemptCount = nil
            queueLastAttemptAt = nil
            queueNextRetryAt = nil
            queueLastErrorCode = nil
            queueLastErrorMessage = nil
            queueLastHTTPStatus = nil
            queueLastServerStatus = nil
            queueLastServerStage = nil
            queueLastServerRetryAfter = nil
            queueUpdatedAt = nil
            queueNeedsAttention = nil
        }

        init(_ scan: MerianSchemaV47.OfflineQueuedScan) {
            id = scan.id
            timestamp = scan.timestamp
            capturedMediaJSON = scan.capturedMediaJSON
            coverImagePath = scan.coverImagePath
            gpsLatitude = scan.gpsLatitude
            gpsLongitude = scan.gpsLongitude
            gpsElevation = scan.gpsElevation
            weatherCondition = scan.weatherCondition
            weatherTemperatureF = scan.weatherTemperatureF
            blurScore = scan.blurScore
            subjectDistanceInMeters = scan.subjectDistanceInMeters
            locationName = scan.locationName
            isFlashFired = scan.isFlashFired
            cameraPitchDegrees = scan.cameraPitchDegrees
            compassHeading = scan.compassHeading
            relativeHumidity = scan.relativeHumidity
            uvIndex = scan.uvIndex
            zoomFactor = scan.zoomFactor
            scanStateRaw = scan.scanStateRaw
            stagedR2Keys = scan.stagedR2Keys
            inferenceImagePaths = scan.inferenceImagePaths
            visualMediaItemsJSON = scan.visualMediaItemsJSON
            fieldNotes = scan.fieldNotes
            queueAttemptCount = nil
            queueLastAttemptAt = nil
            queueNextRetryAt = nil
            queueLastErrorCode = nil
            queueLastErrorMessage = nil
            queueLastHTTPStatus = nil
            queueLastServerStatus = nil
            queueLastServerStage = nil
            queueLastServerRetryAfter = nil
            queueUpdatedAt = nil
            queueNeedsAttention = nil
        }

        init(_ scan: MerianSchemaV48.OfflineQueuedScan) {
            id = scan.id
            timestamp = scan.timestamp
            capturedMediaJSON = scan.capturedMediaJSON
            coverImagePath = scan.coverImagePath
            gpsLatitude = scan.gpsLatitude
            gpsLongitude = scan.gpsLongitude
            gpsElevation = scan.gpsElevation
            weatherCondition = scan.weatherCondition
            weatherTemperatureF = scan.weatherTemperatureF
            blurScore = scan.blurScore
            subjectDistanceInMeters = scan.subjectDistanceInMeters
            locationName = scan.locationName
            isFlashFired = scan.isFlashFired
            cameraPitchDegrees = scan.cameraPitchDegrees
            compassHeading = scan.compassHeading
            relativeHumidity = scan.relativeHumidity
            uvIndex = scan.uvIndex
            zoomFactor = scan.zoomFactor
            scanStateRaw = scan.scanStateRaw
            stagedR2Keys = scan.stagedR2Keys
            inferenceImagePaths = scan.inferenceImagePaths
            visualMediaItemsJSON = scan.visualMediaItemsJSON
            fieldNotes = scan.fieldNotes
            queueAttemptCount = scan.queueAttemptCount
            queueLastAttemptAt = scan.queueLastAttemptAt
            queueNextRetryAt = scan.queueNextRetryAt
            queueLastErrorCode = scan.queueLastErrorCode
            queueLastErrorMessage = scan.queueLastErrorMessage
            queueLastHTTPStatus = scan.queueLastHTTPStatus
            queueLastServerStatus = scan.queueLastServerStatus
            queueLastServerStage = scan.queueLastServerStage
            queueLastServerRetryAfter = scan.queueLastServerRetryAfter
            queueUpdatedAt = scan.queueUpdatedAt
            queueNeedsAttention = scan.queueNeedsAttention
        }

        init(_ scan: MerianSchemaV48OptionalQueue.OfflineQueuedScan) {
            id = scan.id
            timestamp = scan.timestamp
            capturedMediaJSON = scan.capturedMediaJSON
            coverImagePath = scan.coverImagePath
            gpsLatitude = scan.gpsLatitude
            gpsLongitude = scan.gpsLongitude
            gpsElevation = scan.gpsElevation
            weatherCondition = scan.weatherCondition
            weatherTemperatureF = scan.weatherTemperatureF
            blurScore = scan.blurScore
            subjectDistanceInMeters = scan.subjectDistanceInMeters
            locationName = scan.locationName
            isFlashFired = scan.isFlashFired
            cameraPitchDegrees = scan.cameraPitchDegrees
            compassHeading = scan.compassHeading
            relativeHumidity = scan.relativeHumidity
            uvIndex = scan.uvIndex
            zoomFactor = scan.zoomFactor
            scanStateRaw = scan.scanStateRaw
            stagedR2Keys = scan.stagedR2Keys
            inferenceImagePaths = scan.inferenceImagePaths
            visualMediaItemsJSON = scan.visualMediaItemsJSON
            fieldNotes = scan.fieldNotes
            queueAttemptCount = scan.queueAttemptCount
            queueLastAttemptAt = scan.queueLastAttemptAt
            queueNextRetryAt = scan.queueNextRetryAt
            queueLastErrorCode = scan.queueLastErrorCode
            queueLastErrorMessage = scan.queueLastErrorMessage
            queueLastHTTPStatus = scan.queueLastHTTPStatus
            queueLastServerStatus = scan.queueLastServerStatus
            queueLastServerStage = scan.queueLastServerStage
            queueLastServerRetryAfter = scan.queueLastServerRetryAfter
            queueUpdatedAt = scan.queueUpdatedAt
            queueNeedsAttention = scan.queueNeedsAttention
        }
    }

    private static let _v49QueuedScanBackfill = MigrationScratchpad<V49QueuedScanMigrationSnapshot>()

    private static func migrationFirstImagePath(in items: [SerializedMediaItem]) -> String? {
        CapturedMediaSnapshot(items: items).primaryImagePath
    }

    private static func replaceMigratedCapturedMedia(
        on scan: MerianSchemaV41.LocalScanRecord,
        with items: [SerializedMediaItem],
        context: ModelContext
    ) {
        for existingEntry in scan.capturedMediaEntries ?? [] {
            context.delete(existingEntry)
        }

        let entries = MerianSchemaV41.CapturedMediaEntry.makeEntries(from: items)
        entries.forEach { context.insert($0) }
        scan.capturedMediaJSON = MediaJSONParser.jsonString(from: items)
        scan.coverImagePath = migrationFirstImagePath(in: items)
        scan.capturedMediaEntries = entries
    }

    private static func replaceMigratedCapturedMedia(
        on scan: MerianSchemaV41.OfflineQueuedScan,
        with items: [SerializedMediaItem],
        context: ModelContext
    ) {
        for existingEntry in scan.capturedMediaEntries ?? [] {
            context.delete(existingEntry)
        }

        let entries = MerianSchemaV41.CapturedMediaEntry.makeEntries(from: items)
        entries.forEach { context.insert($0) }
        scan.capturedMediaJSON = MediaJSONParser.jsonString(from: items)
        scan.coverImagePath = migrationFirstImagePath(in: items)
        scan.capturedMediaEntries = entries
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
            MerianSchemaV47.self,
            MerianSchemaV48.self,
            MerianSchemaV49.self,
            MerianSchemaV50.self
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
            migrateV42toV49,
            migrateV43toV49,
            migrateV48toV49,
            migrateV49toV50
        ]
    }

    private static func initializeV49OfflineQueueRecords(
        in context: ModelContext,
        stage: String
    ) throws {
        let now = Date()
        let namespace = migrationNamespace(for: context)
        let namespacedSnapshots = _v49QueuedScanBackfill.values(namespace: namespace)
        let snapshots = namespacedSnapshots.isEmpty ? _v49QueuedScanBackfill.allValues() : namespacedSnapshots
        let queuedScans = try context.fetch(FetchDescriptor<MerianSchemaV49.OfflineQueuedScan>())
        let snapshotIds = Set(snapshots.map(\.id))
        var existingScansById = Dictionary(uniqueKeysWithValues: queuedScans.map { ($0.id, $0) })

        let existingJobs = try context.fetch(FetchDescriptor<MerianSchemaV49.OfflineJobRecord>())
        var existingJobIds = Set(existingJobs.map(\.id))

        func insertSchedulerRows(scanId: String, createdAt: Date) {
            let jobId = "scan-ingestion:\(scanId)"
            if !existingJobIds.contains(jobId) {
                let job = MerianSchemaV49.OfflineJobRecord(
                    id: jobId,
                    kind: .scanIngestion,
                    subjectId: scanId,
                    priority: 100,
                    status: .pending,
                    createdAt: createdAt,
                    updatedAt: now
                )
                context.insert(job)
                existingJobIds.insert(jobId)
            }

            context.insert(MerianSchemaV49.OfflineQueueEvent(
                jobId: jobId,
                scanId: scanId,
                kind: .queued,
                createdAt: now,
                message: "Queued scan migrated through startup recovery schema repair."
            ))
        }

        func replaceQueuedCapturedMedia(
            on scan: MerianSchemaV49.OfflineQueuedScan,
            capturedMediaJSON: String?
        ) {
            for existingEntry in scan.capturedMediaEntries ?? [] {
                context.delete(existingEntry)
            }

            guard let jsonString = capturedMediaJSON,
                  let items = MediaJSONParser.serializedItems(jsonString: jsonString) else {
                scan.capturedMediaEntries = []
                return
            }

            let entries = CapturedMediaEntry.makeEntries(from: items)
            entries.forEach { context.insert($0) }
            scan.capturedMediaEntries = entries
        }

        func normalizeQueueMetadata(on scan: MerianSchemaV49.OfflineQueuedScan) {
            scan.queueAttemptCount = 0
            scan.queueUpdatedAt = now
            scan.queueNeedsAttention = false
            scan.queueSchemaRepairGeneration = 1
        }

        func apply(
            snapshot: V49QueuedScanMigrationSnapshot,
            to scan: MerianSchemaV49.OfflineQueuedScan
        ) {
            scan.timestamp = snapshot.timestamp
            scan.capturedMediaJSON = snapshot.capturedMediaJSON
            scan.coverImagePath = snapshot.coverImagePath
            scan.gpsLatitude = snapshot.gpsLatitude
            scan.gpsLongitude = snapshot.gpsLongitude
            scan.gpsElevation = snapshot.gpsElevation
            scan.weatherCondition = snapshot.weatherCondition
            scan.weatherTemperatureF = snapshot.weatherTemperatureF
            scan.blurScore = snapshot.blurScore
            scan.subjectDistanceInMeters = snapshot.subjectDistanceInMeters
            scan.locationName = snapshot.locationName
            scan.isFlashFired = snapshot.isFlashFired
            scan.cameraPitchDegrees = snapshot.cameraPitchDegrees
            scan.compassHeading = snapshot.compassHeading
            scan.relativeHumidity = snapshot.relativeHumidity
            scan.uvIndex = snapshot.uvIndex
            scan.zoomFactor = snapshot.zoomFactor
            scan.scanStateRaw = snapshot.scanStateRaw
            scan.stagedR2Keys = snapshot.stagedR2Keys
            scan.inferenceImagePaths = snapshot.inferenceImagePaths
            scan.visualMediaItemsJSON = snapshot.visualMediaItemsJSON
            scan.fieldNotes = snapshot.fieldNotes
            scan.queueAttemptCount = snapshot.queueAttemptCount ?? 0
            scan.queueLastAttemptAt = snapshot.queueLastAttemptAt
            scan.queueNextRetryAt = snapshot.queueNextRetryAt
            scan.queueLastErrorCode = snapshot.queueLastErrorCode
            scan.queueLastErrorMessage = snapshot.queueLastErrorMessage
            scan.queueLastHTTPStatus = snapshot.queueLastHTTPStatus
            scan.queueLastServerStatus = snapshot.queueLastServerStatus
            scan.queueLastServerStage = snapshot.queueLastServerStage
            scan.queueLastServerRetryAfter = snapshot.queueLastServerRetryAfter
            scan.queueUpdatedAt = snapshot.queueUpdatedAt ?? now
            scan.queueNeedsAttention = snapshot.queueNeedsAttention ?? false
            scan.queueSchemaRepairGeneration = 1
            replaceQueuedCapturedMedia(on: scan, capturedMediaJSON: snapshot.capturedMediaJSON)
        }

        func upsertQueuedScan(from snapshot: V49QueuedScanMigrationSnapshot) {
            let scan: MerianSchemaV49.OfflineQueuedScan
            if let existingScan = existingScansById[snapshot.id] {
                scan = existingScan
            } else {
                scan = MerianSchemaV49.OfflineQueuedScan(id: snapshot.id)
                context.insert(scan)
                existingScansById[snapshot.id] = scan
            }

            apply(snapshot: snapshot, to: scan)
            insertSchedulerRows(scanId: snapshot.id, createdAt: snapshot.timestamp)
        }

        for scan in queuedScans where !snapshotIds.contains(scan.id) {
            normalizeQueueMetadata(on: scan)
            insertSchedulerRows(scanId: scan.id, createdAt: scan.timestamp)
        }

        for snapshot in snapshots {
            upsertQueuedScan(from: snapshot)
        }

        try saveMigrationContext(context, stage: stage)
        if namespacedSnapshots.isEmpty {
            _v49QueuedScanBackfill.removeAll()
        } else {
            _v49QueuedScanBackfill.removeAll(namespace: namespace)
        }
    }

    private static func snapshotLegacyQueuedScansForV49(
        in context: ModelContext,
        stage: String
    ) throws {
        let namespace = migrationNamespace(for: context)
        _v49QueuedScanBackfill.removeAll(namespace: namespace)
        let queuedScans = try context.fetch(FetchDescriptor<MerianSchemaV42.OfflineQueuedScan>())
        for scan in queuedScans {
            _v49QueuedScanBackfill[namespace: namespace, key: scan.id] = V49QueuedScanMigrationSnapshot(scan)
            context.delete(scan)
        }

        if !queuedScans.isEmpty {
            try saveMigrationContext(context, stage: "\(stage) willMigrate")
        }
    }

    private static func snapshotV47QueuedScansForV49(
        in context: ModelContext,
        stage: String
    ) throws {
        let namespace = migrationNamespace(for: context)
        _v49QueuedScanBackfill.removeAll(namespace: namespace)
        let queuedScans = try context.fetch(FetchDescriptor<MerianSchemaV47.OfflineQueuedScan>())
        for scan in queuedScans {
            _v49QueuedScanBackfill[namespace: namespace, key: scan.id] = V49QueuedScanMigrationSnapshot(scan)
            context.delete(scan)
        }

        if !queuedScans.isEmpty {
            try saveMigrationContext(context, stage: "\(stage) willMigrate")
        }
    }

    private static func snapshotV48QueuedScansForV49(in context: ModelContext) throws {
        let namespace = migrationNamespace(for: context)
        _v49QueuedScanBackfill.removeAll(namespace: namespace)
        let queuedScans = try context.fetch(FetchDescriptor<MerianSchemaV48.OfflineQueuedScan>())
        for scan in queuedScans {
            _v49QueuedScanBackfill[namespace: namespace, key: scan.id] = V49QueuedScanMigrationSnapshot(scan)
            context.delete(scan)
        }

        // Do not save here. V48 stores can materialize target rows with new
        // non-optional V49 retry fields still nil; didMigrate must repair those
        // rows before Core Data validation gets a save boundary.
    }

    private static func snapshotOptionalQueueV48QueuedScansForV49(in context: ModelContext) throws {
        let namespace = migrationNamespace(for: context)
        _v49QueuedScanBackfill.removeAll(namespace: namespace)
        let queuedScans = try context.fetch(FetchDescriptor<MerianSchemaV48OptionalQueue.OfflineQueuedScan>())
        for scan in queuedScans {
            _v49QueuedScanBackfill[namespace: namespace, key: scan.id] = V49QueuedScanMigrationSnapshot(scan)
            context.delete(scan)
        }

        // Do not save here. Optional-queue V48 rows intentionally have nil
        // retry metadata; didMigrate fills the non-optional V49 defaults before
        // the migration context is saved.
    }

    // Recent stores jump directly to V49 so iOS 26 never validates a direct-to-V48
    // custom stage whose Core Data model reference can collapse to its source.
    static let migrateV42toV49 = MigrationStage.custom(
        fromVersion: MerianSchemaV42.self,
        toVersion: MerianSchemaV49.self,
        willMigrate: { context in
            try snapshotLegacyQueuedScansForV49(in: context, stage: "V42->V49")
        },
        didMigrate: { context in
            try initializeV49OfflineQueueRecords(in: context, stage: "V42->V49 didMigrate")
        }
    )

    static let migrateV43toV49 = MigrationStage.custom(
        fromVersion: MerianSchemaV43.self,
        toVersion: MerianSchemaV49.self,
        willMigrate: { context in
            try snapshotLegacyQueuedScansForV49(in: context, stage: "V43->V49")
        },
        didMigrate: { context in
            try initializeV49OfflineQueueRecords(in: context, stage: "V43->V49 didMigrate")
        }
    )

    static let migrateV44toV49 = MigrationStage.custom(
        fromVersion: MerianSchemaV44.self,
        toVersion: MerianSchemaV49.self,
        willMigrate: { context in
            try snapshotLegacyQueuedScansForV49(in: context, stage: "V44->V49")
        },
        didMigrate: { context in
            try initializeV49OfflineQueueRecords(in: context, stage: "V44->V49 didMigrate")
        }
    )

    static let migrateV45toV49 = MigrationStage.custom(
        fromVersion: MerianSchemaV45.self,
        toVersion: MerianSchemaV49.self,
        willMigrate: { context in
            try snapshotLegacyQueuedScansForV49(in: context, stage: "V45->V49")
        },
        didMigrate: { context in
            try initializeV49OfflineQueueRecords(in: context, stage: "V45->V49 didMigrate")
        }
    )

    static let migrateV46toV49 = MigrationStage.custom(
        fromVersion: MerianSchemaV46.self,
        toVersion: MerianSchemaV49.self,
        willMigrate: { context in
            try snapshotLegacyQueuedScansForV49(in: context, stage: "V46->V49")
        },
        didMigrate: { context in
            try initializeV49OfflineQueueRecords(in: context, stage: "V46->V49 didMigrate")
        }
    )

    static let migrateV47toV49 = MigrationStage.custom(
        fromVersion: MerianSchemaV47.self,
        toVersion: MerianSchemaV49.self,
        willMigrate: { context in
            try snapshotV47QueuedScansForV49(in: context, stage: "V47->V49")
        },
        didMigrate: { context in
            try initializeV49OfflineQueueRecords(in: context, stage: "V47->V49 didMigrate")
        }
    )

    static let migrateV48toV49 = MigrationStage.custom(
        fromVersion: MerianSchemaV48.self,
        toVersion: MerianSchemaV49.self,
        willMigrate: { context in
            try snapshotV48QueuedScansForV49(in: context)
        },
        didMigrate: { context in
            try initializeV49OfflineQueueRecords(in: context, stage: "V48->V49 didMigrate")
        }
    )

    static let migrateOptionalQueueV48toV49 = MigrationStage.custom(
        fromVersion: MerianSchemaV48OptionalQueue.self,
        toVersion: MerianSchemaV49.self,
        willMigrate: { context in
            try snapshotOptionalQueueV48QueuedScansForV49(in: context)
        },
        didMigrate: { context in
            try initializeV49OfflineQueueRecords(in: context, stage: "V48 optional queue->V49 didMigrate")
        }
    )

    static let migrateV49toV50 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV49.self,
        toVersion: MerianSchemaV50.self
    )

    static let migrateV41toV42 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV41.self,
        toVersion: MerianSchemaV42.self
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
                replaceMigratedCapturedMedia(on: scan, with: items, context: context)
            }

            let offlineScans = try context.fetch(FetchDescriptor<MerianSchemaV41.OfflineQueuedScan>())
            for scan in offlineScans {
                guard scan.capturedMediaEntries?.isEmpty ?? true,
                      let jsonString = scan.capturedMediaJSON,
                      let items = MediaJSONParser.serializedItems(jsonString: jsonString) else {
                    continue
                }
                replaceMigratedCapturedMedia(on: scan, with: items, context: context)
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

/// Short recovery plans for recent stores when the full historical chain trips
/// SwiftData's duplicate-checksum or model-reference validators before reaching the actual source.
///
/// V44, V45, and V46 are close enough that pairing them in a retry plan can
/// still trigger duplicate-checksum validation. Each short plan therefore keeps
/// exactly one possible source representative and jumps directly to the next
/// V49 repair target.
enum MerianRecentV42MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MerianSchemaV42.self,
            MerianSchemaV49.self,
            MerianSchemaV50.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            MerianMigrationPlan.migrateV42toV49,
            MerianMigrationPlan.migrateV49toV50
        ]
    }
}

/// Short recovery plan for stores already stamped V43. This avoids validating
/// the older full historical custom stages on devices that can jump straight to
/// the current repair path.
enum MerianRecentV43MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MerianSchemaV43.self,
            MerianSchemaV49.self,
            MerianSchemaV50.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            MerianMigrationPlan.migrateV43toV49,
            MerianMigrationPlan.migrateV49toV50
        ]
    }
}

enum MerianRecentV44MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MerianSchemaV44.self,
            MerianSchemaV49.self,
            MerianSchemaV50.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            MerianMigrationPlan.migrateV44toV49,
            MerianMigrationPlan.migrateV49toV50
        ]
    }
}

/// Short recovery plan for stores on the V45 representative.
enum MerianRecentV45MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MerianSchemaV45.self,
            MerianSchemaV49.self,
            MerianSchemaV50.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            MerianMigrationPlan.migrateV45toV49,
            MerianMigrationPlan.migrateV49toV50
        ]
    }
}

/// Short recovery plan for stores already stamped with released no-op V46.
/// V46 is safe here because this source-isolated plan does not include its V45
/// checksum twin.
enum MerianRecentV46MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MerianSchemaV46.self,
            MerianSchemaV49.self,
            MerianSchemaV50.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            MerianMigrationPlan.migrateV46toV49,
            MerianMigrationPlan.migrateV49toV50
        ]
    }
}

/// Short recovery plan for stores that already made it to V47.
enum MerianRecentV47MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MerianSchemaV47.self,
            MerianSchemaV49.self,
            MerianSchemaV50.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            MerianMigrationPlan.migrateV47toV49,
            MerianMigrationPlan.migrateV49toV50
        ]
    }
}

/// Short recovery plan for stores already on the known-good V48 source.
enum MerianRecentV48MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MerianSchemaV48.self,
            MerianSchemaV49.self,
            MerianSchemaV50.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            MerianMigrationPlan.migrateV48toV49,
            MerianMigrationPlan.migrateV49toV50
        ]
    }
}

/// Recovery plan for the accidental optional-queue V48 TestFlight schema.
enum MerianOptionalQueueV48RecoveryPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MerianSchemaV48OptionalQueue.self,
            MerianSchemaV49.self,
            MerianSchemaV50.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            MerianMigrationPlan.migrateOptionalQueueV48toV49,
            MerianMigrationPlan.migrateV49toV50
        ]
    }
}
