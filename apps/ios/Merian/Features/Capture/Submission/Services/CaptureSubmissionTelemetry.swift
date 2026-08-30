import CoreLocation
import Foundation

extension CaptureTelemetry {
    static func immediateForActiveScan(
        historicalContext: EnvironmentContext?,
        isGalleryPhoto: Bool,
        cachedLocation: CLLocation?,
        distanceMeters: Float?,
        zoomFactor: CGFloat?,
        defaultZoomFactor: CGFloat = 1.0
    ) -> CaptureTelemetry {
        if isGalleryPhoto {
            guard let historicalContext else {
                return CaptureTelemetry(
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
                    estimatedSizeCm: nil
                )
            }
            return CaptureTelemetry(
                from: historicalContext,
                distance: nil,
                requiresExplicitCaptureDate: true
            )
        }

        return CaptureTelemetry(
            subjectDistanceInMeters: distanceMeters,
            gpsLatitude: cachedLocation?.coordinate.latitude,
            gpsLongitude: cachedLocation?.coordinate.longitude,
            gpsElevation: cachedLocation?.altitude,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: DateUtilities.iso8601Formatter.string(from: Date()),
            zoomFactor: nonDefaultZoomFactor(
                zoomFactor,
                defaultZoomFactor: defaultZoomFactor
            ),
            estimatedSizeCm: nil
        )
    }

    static func resolveForActiveScan(
        resolvedContext: EnvironmentContext?,
        historicalContext: EnvironmentContext?,
        isGalleryPhoto: Bool,
        firstImageData: Data?,
        distanceMeters: Float?,
        zoomFactor: CGFloat?,
        defaultZoomFactor: CGFloat = 1.0
    ) async -> CaptureTelemetry {
        let zoomToUse = nonDefaultZoomFactor(
            zoomFactor,
            defaultZoomFactor: defaultZoomFactor
        )

        if isGalleryPhoto {
            guard let historicalContext else {
                return CaptureTelemetry(
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
                    estimatedSizeCm: nil
                )
            }
            return CaptureTelemetry(
                from: historicalContext,
                distance: nil,
                requiresExplicitCaptureDate: true
            )
        } else if let resolvedContext {
            var estimatedSizeCm: Double?
            if let distanceMeters, let firstImageData {
                estimatedSizeCm = await SizeEstimator.estimateSize(
                    imageData: firstImageData,
                    distanceMeters: distanceMeters
                )
            }
            return CaptureTelemetry(
                from: resolvedContext,
                distance: distanceMeters,
                zoom: zoomToUse,
                estimatedSizeCm: estimatedSizeCm
            )
        } else if let historicalContext {
            return CaptureTelemetry(from: historicalContext, distance: nil)
        } else {
            var estimatedSizeCm: Double?
            if let distanceMeters, let firstImageData {
                estimatedSizeCm = await SizeEstimator.estimateSize(
                    imageData: firstImageData,
                    distanceMeters: distanceMeters
                )
            }
            return CaptureTelemetry(
                subjectDistanceInMeters: distanceMeters,
                gpsLatitude: nil,
                gpsLongitude: nil,
                gpsElevation: nil,
                locationName: nil,
                weatherCondition: nil,
                weatherTemperatureF: nil,
                timeOfDay: nil,
                timestamp: DateUtilities.iso8601Formatter.string(from: Date()),
                zoomFactor: zoomToUse,
                estimatedSizeCm: estimatedSizeCm
            )
        }
    }

    static func nonDefaultZoomFactor(
        _ zoomFactor: CGFloat?,
        defaultZoomFactor: CGFloat
    ) -> CGFloat? {
        guard let zoomFactor else { return nil }
        return abs(zoomFactor - defaultZoomFactor) > 0.01 ? zoomFactor : nil
    }
}
