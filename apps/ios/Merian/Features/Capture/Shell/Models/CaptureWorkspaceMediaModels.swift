import CoreLocation
import Foundation

struct HistoricalEnvironmentContextSnapshot: Sendable, Equatable {
    let latitude: CLLocationDegrees?
    let longitude: CLLocationDegrees?
    let locationName: String?
    let weatherCondition: String?
    let weatherTemperature: Double?
    let captureDate: Date?

    init(context: EnvironmentContext) {
        latitude = context.location?.coordinate.latitude
        longitude = context.location?.coordinate.longitude
        locationName = context.locationName
        weatherCondition = context.weatherCondition
        weatherTemperature = context.weatherTemperature
        captureDate = context.captureDate
    }

    init(captureDate: Date) {
        latitude = nil
        longitude = nil
        locationName = nil
        weatherCondition = nil
        weatherTemperature = nil
        self.captureDate = captureDate
    }

    init(
        latitude: CLLocationDegrees?,
        longitude: CLLocationDegrees?,
        captureDate: Date?
    ) {
        self.latitude = latitude
        self.longitude = longitude
        locationName = nil
        weatherCondition = nil
        weatherTemperature = nil
        self.captureDate = captureDate
    }

    func makeEnvironmentContext() -> EnvironmentContext {
        let location: CLLocation?
        if let latitude, let longitude {
            location = CLLocation(latitude: latitude, longitude: longitude)
        } else {
            location = nil
        }

        return EnvironmentContext(
            location: location,
            locationName: locationName,
            weatherCondition: weatherCondition,
            weatherTemperature: weatherTemperature,
            captureDate: captureDate
        )
    }
}

struct PreparedStagedImage: Sendable {
    let compressedData: Data
    let displayData: Data
    let historicalContext: HistoricalEnvironmentContextSnapshot?
    let previewCGImage: SendableCGImage
    let metrics: MediaPreparationMetrics?
    let focusRegion: NormalizedImageFocusRegion?

    init(
        compressedData: Data,
        displayData: Data,
        historicalContext: HistoricalEnvironmentContextSnapshot?,
        previewCGImage: SendableCGImage,
        metrics: MediaPreparationMetrics? = nil,
        focusRegion: NormalizedImageFocusRegion? = nil
    ) {
        self.compressedData = compressedData
        self.displayData = displayData
        self.historicalContext = historicalContext
        self.previewCGImage = previewCGImage
        self.metrics = metrics
        self.focusRegion = focusRegion
    }
}

enum ExternalImageImportAttemptResult: Equatable {
    case staged
    case temporarilyBlocked
    case terminalFailure
    case noPendingImport
}

struct RefinementScanContext: Equatable {
    let scanId: String
    let subjectId: String?
    let capturedMediaSnapshot: CapturedMediaSnapshot
    let coverImagePath: String?
    let entryPoint: RefinementEntryPoint

    init(record: LocalScanRecord, entryPoint: RefinementEntryPoint = .standard) {
        scanId = record.id
        subjectId = DescribeSubjectResolver.subjectId(for: record)
        capturedMediaSnapshot = record.capturedMediaSnapshot
        coverImagePath = record.coverImagePath
        self.entryPoint = entryPoint
    }
}

struct PreparedStagedImageRequest: Sendable, Equatable {
    let fileURL: URL
    let isPro: Bool
    let historicalContext: HistoricalEnvironmentContextSnapshot?
}

typealias PreparedStagedImageLoader = @Sendable (
    PreparedStagedImageRequest
) async throws -> PreparedStagedImage?

typealias PreparedHistoricalAudioLoader = @Sendable (
    StoredMediaReference
) async throws -> URL?
