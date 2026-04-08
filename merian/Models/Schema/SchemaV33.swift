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
// LocalScanRecord, ScanCollection, and PendingCloudDeletionTask did NOT change between V33
// and V34, so they reference the global active types. This keeps a single Swift class for
// each entity and avoids the "Failed to cast model Merian.X to X" SwiftData runtime error
// that arises when two schema versions register different Swift types for the same entity.
// The unique checksum for V33 comes from the frozen OfflineQueuedScan alone.
// DO NOT modify after committing. Checksums must remain stable forever.
enum MerianSchemaV33: VersionedSchema {
    static var versionIdentifier = Schema.Version(33, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, MerianSchemaV33.OfflineQueuedScan.self,
         ScanCollection.self, PendingCloudDeletionTask.self]
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
