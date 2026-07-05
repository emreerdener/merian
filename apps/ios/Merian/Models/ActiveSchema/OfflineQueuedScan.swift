import Foundation
import SwiftData

@Model
public final class OfflineQueuedScan {
    @Attribute(.unique) public var id: String
    public var timestamp: Date
    public var capturedMediaJSON: String?
    @Relationship(deleteRule: .cascade) public var capturedMediaEntries: [CapturedMediaEntry]? = []

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
