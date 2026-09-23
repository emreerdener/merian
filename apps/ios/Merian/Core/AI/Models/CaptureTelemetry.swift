import Foundation

/// Sensor and environment state captured at the moment of shutter press.
/// Passed to both the live inference path and the offline queue.
struct CaptureTelemetry: Sendable {
    let subjectDistanceInMeters: Float?
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let gpsElevation: Double?
    let locationName: String?
    let weatherCondition: String?
    let weatherTemperatureF: Double?
    let timeOfDay: String?
    let timestamp: String?
    /// Active zoom factor at shutter press. Nil when 1× (adds no signal).
    /// Omitted from offline-queue retries since zoom is not persisted in the schema.
    var zoomFactor: CGFloat?
    var estimatedSizeCm: Double?
    #if DEBUG && targetEnvironment(simulator)
    /// Request-local only. Durable recovery intentionally does not persist this test profile.
    var debugReplayProfile: DebugIdentificationReplayProfile?
    #endif
}

#if DEBUG && targetEnvironment(simulator)
/// Versioned synthetic context for a single foreground audio comparison request.
/// This is not capture metadata, an account override, or a model assignment.
enum DebugIdentificationReplayProfile: Equatable, Sendable {
    case audioMinimalV1
    case audioComparison(slot: DebugAudioComparisonSlot)

    var comparison: DebugAudioComparisonAssignment? {
        guard case .audioComparison(let slot) = self else { return nil }
        return slot.assignment
    }

    func makeTelemetry() -> CaptureTelemetry {
        CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: nil,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: nil,
            zoomFactor: nil,
            estimatedSizeCm: nil,
            debugReplayProfile: self
        )
    }
}
#endif

extension CaptureTelemetry {
    @MainActor
    init(from inferenceEngine: InferenceEngine) {
        self.init(
            subjectDistanceInMeters: inferenceEngine.activeDistanceInMeters,
            gpsLatitude: inferenceEngine.activeLatitude,
            gpsLongitude: inferenceEngine.activeLongitude,
            gpsElevation: inferenceEngine.activeElevation,
            locationName: inferenceEngine.activeLocationName,
            weatherCondition: inferenceEngine.activeWeatherCondition,
            weatherTemperatureF: inferenceEngine.activeTemperatureF,
            timeOfDay: nil,
            timestamp: DateUtilities.iso8601Formatter.string(from: Date()),
            estimatedSizeCm: nil
        )
    }

    init(
        from context: EnvironmentContext,
        distance: Float?,
        zoom: CGFloat? = nil,
        estimatedSizeCm: Double? = nil,
        requiresExplicitCaptureDate: Bool = false
    ) {
        let reliableElevation: Double? = context.location.flatMap { location in
            (location.verticalAccuracy >= 0 && location.verticalAccuracy <= 25)
                ? location.altitude
                : nil
        }
        let timestampDate = requiresExplicitCaptureDate
            ? context.captureDate
            : context.captureDate ?? context.location?.timestamp ?? Date()

        var telemetry = CaptureTelemetry(
            subjectDistanceInMeters: distance,
            gpsLatitude: context.location?.coordinate.latitude,
            gpsLongitude: context.location?.coordinate.longitude,
            gpsElevation: reliableElevation,
            locationName: context.locationName,
            weatherCondition: context.weatherCondition,
            weatherTemperatureF: context.weatherTemperature,
            timeOfDay: nil,
            timestamp: timestampDate.map {
                DateUtilities.iso8601Formatter.string(from: $0)
            },
            estimatedSizeCm: estimatedSizeCm
        )
        telemetry.zoomFactor = zoom
        self = telemetry
    }
}
