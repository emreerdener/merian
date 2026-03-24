import Foundation
import SwiftData

// Added: isFlashFired, cameraPitchDegrees, compassHeading, relativeHumidity, uvIndex on OfflineQueuedScan
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
