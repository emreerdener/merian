import Foundation
import SwiftData

// Added in V33:
//   OfflineQueuedScan.scanStateRaw  — Int (raw ScanQueueState) replacing isUploaded + isDeleted booleans.
//   OfflineQueuedScan.stagedR2Keys  — [String]? storing confirmed R2 object keys, eliminating
//                                     auth-dependent key reconstruction at inference time.
//
// Removed from OfflineQueuedScan in V33:
//   isUploaded (Bool) — superseded by scanStateRaw >= ScanQueueState.staged.rawValue
//   isDeleted  (Bool) — superseded by scanStateRaw == ScanQueueState.failed.rawValue
//
// MARK: - Frozen snapshot for MerianSchemaV33
// Only OfflineQueuedScan changed in V33 — it is frozen here as a namespaced inner class.
// LocalScanRecord, ScanCollection, and PendingCloudDeletionTask did NOT change in V33;
// they are anchored to V31/V30 frozen snapshots so the V33 checksum stays fixed even when
// later versions add new fields to the global active types (e.g. alternativeCommonNames in V34).
// DO NOT modify after committing. Checksums must remain stable forever.
enum MerianSchemaV33: VersionedSchema {
    static var versionIdentifier = Schema.Version(33, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV33.LocalScanRecord.self, MerianSchemaV33.OfflineQueuedScan.self,
         MerianSchemaV33.ScanCollection.self, MerianSchemaV33.PendingCloudDeletionTask.self]
    }

    typealias LocalScanRecord           = MerianSchemaV31.LocalScanRecord
    typealias ScanCollection            = MerianSchemaV31.ScanCollection
    typealias PendingCloudDeletionTask  = MerianSchemaV30.PendingCloudDeletionTask

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

        /// Raw ScanQueueState value. 0 = pending, 1 = uploading, 2 = staged, 3 = inferencing, 4 = failed.
        var scanStateRaw: Int = 0
        var stagedR2Keys: [String]?

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
            scanStateRaw: Int = 0,
            stagedR2Keys: [String]? = nil
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
            self.scanStateRaw = scanStateRaw
            self.stagedR2Keys = stagedR2Keys
        }
    }
}
