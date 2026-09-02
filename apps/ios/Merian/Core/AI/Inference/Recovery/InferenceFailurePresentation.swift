import Foundation

/// Display-only failure values. Creating a placeholder never publishes it or
/// changes queue, entitlement, circuit, feedback, or telemetry state.
struct InferenceFailurePresentation: Equatable, Sendable {
    let title: String
    let subtitle: String
    let reasoning: String

    static let observationRejected = InferenceFailurePresentation(
        title: "Try another capture",
        subtitle: "Scan not processed",
        reasoning: "Naturebook couldn’t process this observation. Try a different photo or " +
            "recording with the subject clearly visible."
    )

    static func make(
        for failure: InferenceLiveFailurePolicy.Failure,
        hasQueuedScan: Bool
    ) -> InferenceFailurePresentation? {
        switch failure {
        case .recoverableConflict:
            return .init(
                title: "Restoring scan",
                subtitle: "Safely saved",
                reasoning: "Your scan reached Naturebook safely. We’re restoring its saved result now, " +
                    "and it will appear here or in Scans automatically."
            )
        case .consentRequired:
            return .init(
                title: "Approval needed",
                subtitle: "Scan saved",
                reasoning: "Naturebook saved this scan. Complete the required age, Terms, and Google Gemini " +
                    "consent step, and Naturebook will resume it automatically when eligible. " +
                    "If it stays paused, you can retry it from Scans."
            )
        case .proRequired:
            return .init(
                title: "Upgrade needed",
                subtitle: "Scan saved",
                reasoning: "Naturebook saved this scan. This capture requires Pro access. " +
                    "Upgrade, then retry it from Scans."
            )
        case .dailyQuotaExceeded:
            return nil
        case .rateLimited:
            return .init(
                title: "Retrying shortly",
                subtitle: "Scan saved",
                reasoning: "Naturebook saved this scan and will retry automatically after the server’s " +
                    "short safety pause. You can leave this screen and check Scans later."
            )
        case .observationRejected:
            return observationRejected
        case .visualDecoding:
            return .init(
                title: "Analysis Failed",
                subtitle: "Data Unreadable",
                reasoning: "The AI failed to understand the image or produced an unreadable schema."
            )
        case .connectivity:
            return .init(
                title: "Network timeout",
                subtitle: hasQueuedScan ? "Scan saved" : "Please try again",
                reasoning: "Naturebook couldn’t reach the analysis service. Check your connection and try again."
            )
        case .service:
            return .init(
                title: "Analysis delayed",
                subtitle: hasQueuedScan ? "Scan saved" : "Please try again",
                reasoning: hasQueuedScan
                    ? "Naturebook saved this scan and will retry it automatically. You can leave this " +
                        "screen and check Scans later."
                    : "Naturebook couldn’t complete this analysis because the service returned an " +
                        "unexpected response. Please try again."
            )
        }
    }

    func speciesData(telemetry: CaptureTelemetry) -> SpeciesData {
        SpeciesData(
            scanId: nil,
            presentationRole: .inferenceError,
            commonName: title,
            scientificName: subtitle,
            insightData: InsightData(aiReasoning: reasoning, hazardType: "none"),
            confidenceScore: 0,
            blurScore: nil,
            similarSpecies: nil,
            wikipediaUrl: nil,
            wikipediaOverview: nil,
            referenceImageUrl: nil,
            isBiological: false,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown",
            taxonomy: nil,
            locationName: telemetry.locationName,
            weatherCondition: telemetry.weatherCondition,
            weatherTemperatureF: telemetry.weatherTemperatureF,
            gpsElevation: telemetry.gpsElevation,
            gpsLatitude: telemetry.gpsLatitude,
            gpsLongitude: telemetry.gpsLongitude,
            colors: nil,
            groupTags: nil,
            iucnRedListStatus: nil,
            zoomFactor: telemetry.zoomFactor.map { Double($0) }
        )
    }
}
