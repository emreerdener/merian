import Foundation
import SwiftData

// Added in V32:
//   OfflineQueuedScan.isUploaded — Bool flag (default false) marking that all image files
//   for this scan have been confirmed received by R2 staging. Prevents re-uploading
//   already-staged files across app restarts when inference hasn't yet processed the scan.
//
// MARK: - Frozen snapshot for MerianSchemaV32
// Generated from ActiveSchema before scanStateRaw/stagedR2Keys were added in V33.
// DO NOT modify after committing. Checksums must remain stable forever.
enum MerianSchemaV32: VersionedSchema {
    static var versionIdentifier = Schema.Version(32, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV32.LocalScanRecord.self, MerianSchemaV32.OfflineQueuedScan.self,
         MerianSchemaV32.ScanCollection.self, MerianSchemaV32.PendingCloudDeletionTask.self]
    }

    typealias LocalScanRecord        = MerianSchemaV31.LocalScanRecord
    typealias ScanCollection         = MerianSchemaV31.ScanCollection
    typealias PendingCloudDeletionTask = MerianSchemaV30.PendingCloudDeletionTask

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

        var isDeleted: Bool
        var isUploaded: Bool = false

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
            isDeleted: Bool = false,
            isUploaded: Bool = false
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
            self.isDeleted = isDeleted
            self.isUploaded = isUploaded
        }
    }
}
