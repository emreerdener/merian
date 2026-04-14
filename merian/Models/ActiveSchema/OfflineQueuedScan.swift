import Foundation
import SwiftData

@Model
public final class OfflineQueuedScan {
    @Attribute(.unique) public var id: String
    public var timestamp: Date
    public var localImagePaths: [String]

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

    /// JSON-encoded `ObservationContext` serialized at enqueue time.
    /// Preserved so the offline-retry path can reconstruct the full combined
    /// image + description payload without requiring the user to re-enter details.
    public var observationContextJSON: String?

    /// Reserved for a companion audio recording.
    /// Populated when `AudioRecordingView` ships its recording pipeline.
    public var audioFilePath: String?

    // MARK: - Typed accessor

    public var queueState: ScanQueueState {
        get { ScanQueueState(rawValue: scanStateRaw) ?? .pending }
        set { scanStateRaw = newValue.rawValue }
    }

    public init(
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
        scanState: ScanQueueState = .pending,
        stagedR2Keys: [String]? = nil,
        observationContextJSON: String? = nil,
        audioFilePath: String? = nil
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
        self.scanStateRaw = scanState.rawValue
        self.stagedR2Keys = stagedR2Keys
        self.observationContextJSON = observationContextJSON
        self.audioFilePath = audioFilePath
    }
}
