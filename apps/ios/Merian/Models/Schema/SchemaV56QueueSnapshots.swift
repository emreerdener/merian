import Foundation
import SwiftData

/// Immutable outgoing V56 graph captured before adding per-analysis state.
extension MerianSchemaV56 {
    @Model
    public final class OfflineQueuedScan {
        @Attribute(.unique) public var id: String
        public var timestamp: Date
        public var capturedMediaJSON: String?
        @Relationship(deleteRule: .cascade) public var capturedMediaEntries: [MerianSchemaV56.CapturedMediaEntry]? = []

        public var gpsLatitude: Double?
        public var gpsLongitude: Double?
        public var gpsElevation: Double?
        public var weatherCondition: String?
        public var weatherTemperatureF: Double?
        public var blurScore: Double?
        public var subjectDistanceInMeters: Float?
        public var locationName: String?
        public var isFlashFired: Bool?
        public var cameraPitchDegrees: Double?
        public var compassHeading: Double?
        public var relativeHumidity: Double?
        public var uvIndex: Int?
        @Attribute public var zoomFactor: Double?

        /// Raw value of `ScanQueueState`. Stored as `Int` for `#Predicate` compatibility.
        /// Use `queueState` for typed access. Replaces the old `isUploaded` / `isDeleted` booleans.
        public var scanStateRaw: Int = ScanQueueState.pending.rawValue

        /// R2 object keys written at upload confirmation time.
        /// Eliminates auth-dependent key reconstruction at inference time.
        public var stagedR2Keys: [String]?

        /// Documents-relative image files used for inference replay. This is intentionally separate
        /// from `capturedMediaJSON`, whose images are user-visible display/share media.
        @Attribute public var inferenceImagePaths: [String]?

        /// Encoded `[IdentifyVisualMediaItem]` matching `inferenceImagePaths`.
        @Attribute public var visualMediaItemsJSON: String?

        /// Private user-authored notes captured while the scan is still in flight.
        @Attribute public var fieldNotes: String?

        /// Durable retry and diagnostics fields. These replace the older process-local retry counter
        /// so app relaunches keep the queue's real state.
        @Attribute public var queueAttemptCount: Int = 0
        @Attribute public var queueLastAttemptAt: Date?
        @Attribute public var queueNextRetryAt: Date?
        @Attribute public var queueLastErrorCode: String?
        @Attribute public var queueLastErrorMessage: String?
        @Attribute public var queueLastHTTPStatus: Int?
        @Attribute public var queueLastServerStatus: String?
        @Attribute public var queueLastServerStage: String?
        @Attribute public var queueLastServerRetryAfter: Date?
        @Attribute public var queueUpdatedAt: Date = Date()
        @Attribute public var queueNeedsAttention: Bool = false
        @Attribute public var queueSchemaRepairGeneration: Int = 1

        // MARK: - Typed accessor

        public var queueState: ScanQueueState {
            get { ScanQueueState(rawValue: scanStateRaw) ?? .pending }
            set { scanStateRaw = newValue.rawValue }
        }

        @Attribute public var coverImagePath: String?

        public init(
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
            self.queueSchemaRepairGeneration = queueSchemaRepairGeneration
        }
    }

    @Model
    public final class CapturedMediaEntry {
        @Attribute(.unique) public var id: String
        public var orderIndex: Int
        public var kindRaw: String
        public var storageRaw: String
        public var mediaPath: String
        public var observationContextJSON: String

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

        var kind: PersistedCapturedMediaKind? {
            PersistedCapturedMediaKind(rawValue: kindRaw)
        }

        var serializedItem: SerializedMediaItem? {
            switch kind {
            case .image:
                guard let storage = MediaStorageLocation(rawValue: storageRaw), !mediaPath.isEmpty else {
                    return nil
                }
                return .image(StoredMediaReference(storage: storage, path: mediaPath))
            case .audio:
                guard let storage = MediaStorageLocation(rawValue: storageRaw), !mediaPath.isEmpty else {
                    return nil
                }
                return .audio(StoredMediaReference(storage: storage, path: mediaPath))
            case .video:
                guard let storage = MediaStorageLocation(rawValue: storageRaw), !mediaPath.isEmpty else {
                    return nil
                }
                return .video(StoredVideoMediaReference(StoredMediaReference(storage: storage, path: mediaPath)))
            case .description:
                guard let contextData = observationContextJSON.data(using: .utf8),
                      let context = try? JSONDecoder().decode(ObservationContext.self, from: contextData) else {
                    return nil
                }
                return .description(context)
            case .none:
                return nil
            }
        }
    }

    @Model
    public final class PendingCloudDeletionTask {
        @Attribute(.unique) public var scanId: String
        public var timestamp: Date = Date()

        public init(scanId: String, timestamp: Date = Date()) {
            self.scanId = scanId
            self.timestamp = timestamp
        }
    }

    @Model
    public final class UserSpeciesPreference {
        @Attribute(.unique) public var id: String = UUID().uuidString
        public var ownerUserId: String = ""
        public var scientificName: String
        public var preferredCommonName: String
        public var updatedAt: Date = Date()

        public init(
            ownerUserID: UUID,
            scientificName: String,
            preferredCommonName: String,
            updatedAt: Date = Date()
        ) {
            id = Self.identifier(
                ownerUserID: ownerUserID,
                scientificName: scientificName
            )
            ownerUserId = ownerUserID.uuidString.lowercased()
            self.scientificName = scientificName
            self.preferredCommonName = preferredCommonName
            self.updatedAt = updatedAt
        }

        public static func identifier(
            ownerUserID: UUID,
            scientificName: String
        ) -> String {
            "\(ownerUserID.uuidString.lowercased())|\(scientificName)"
        }
    }

    @Model
    public final class OfflineJobRecord {
        @Attribute(.unique) public var id: String
        public var kindRaw: String
        public var subjectId: String?
        public var priority: Int
        public var statusRaw: String
        public var createdAt: Date
        public var updatedAt: Date
        public var lastAttemptAt: Date?
        public var nextRunAt: Date?
        public var attemptCount: Int
        public var lastErrorCode: String?
        public var lastErrorMessage: String?
        public var lastHTTPStatus: Int?
        public var serverStatus: String?
        public var serverStage: String?
        public var serverRetryAfter: Date?
        public var requiresUnconstrainedNetwork: Bool
        public var allowsCellular: Bool
        public var approximateBytes: Int64
        public var metadataJSON: String?

        public var kind: OfflineJobKind {
            get { OfflineJobKind(rawValue: kindRaw) ?? .future }
            set { kindRaw = newValue.rawValue }
        }

        public var status: OfflineJobStatus {
            get { OfflineJobStatus(rawValue: statusRaw) ?? .pending }
            set { statusRaw = newValue.rawValue }
        }

        public init(
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
            self.kindRaw = kind.rawValue
            self.subjectId = subjectId
            self.priority = priority
            self.statusRaw = status.rawValue
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
    public final class OfflineQueueEvent {
        @Attribute(.unique) public var id: String
        public var jobId: String?
        public var scanId: String?
        public var kindRaw: String
        public var createdAt: Date
        public var message: String?
        public var errorCode: String?
        public var httpStatus: Int?
        public var metadataJSON: String?

        public var kind: OfflineQueueEventKind {
            get { OfflineQueueEventKind(rawValue: kindRaw) ?? .diagnostics }
            set { kindRaw = newValue.rawValue }
        }

        public init(
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
            self.kindRaw = kind.rawValue
            self.createdAt = createdAt
            self.message = message
            self.errorCode = errorCode
            self.httpStatus = httpStatus
            self.metadataJSON = metadataJSON
        }
    }
}
