import Foundation
import Testing

@testable import Merian

@Suite("Inference Failure Presentation")
struct InferenceFailurePresentationTests {
    private struct FailureCase {
        let failure: InferenceLiveFailurePolicy.Failure
        let title: String
        let subtitle: String
        let reasoning: String
    }

    @Test func specialFailuresPreserveTheirExactCopy() throws {
        let cases: [FailureCase] = [
            .init(
                failure: .recoverableConflict,
                title: "Restoring scan",
                subtitle: "Safely saved",
                reasoning: "Your scan reached Naturebook safely. We’re restoring its saved result now, " +
                    "and it will appear here or in Scans automatically."
            ),
            .init(
                failure: .consentRequired,
                title: "Approval needed",
                subtitle: "Scan saved",
                reasoning: "Naturebook saved this scan. Complete the required age, Terms, and Google Gemini " +
                    "consent step, and Naturebook will resume it automatically when eligible. " +
                    "If it stays paused, you can retry it from Scans."
            ),
            .init(
                failure: .proRequired,
                title: "Upgrade needed",
                subtitle: "Scan saved",
                reasoning: "Naturebook saved this scan. This capture requires Pro access. " +
                    "Upgrade, then retry it from Scans."
            ),
            .init(
                failure: .rateLimited(.user),
                title: "Retrying shortly",
                subtitle: "Scan saved",
                reasoning: "Naturebook saved this scan and will retry automatically after the server’s " +
                    "short safety pause. You can leave this screen and check Scans later."
            ),
            .init(
                failure: .rateLimited(.ip),
                title: "Retrying shortly",
                subtitle: "Scan saved",
                reasoning: "Naturebook saved this scan and will retry automatically after the server’s " +
                    "short safety pause. You can leave this screen and check Scans later."
            ),
            .init(
                failure: .observationRejected,
                title: "Try another capture",
                subtitle: "Scan not processed",
                reasoning: "Naturebook couldn’t process this observation. Try a different photo or " +
                    "recording with the subject clearly visible."
            ),
            .init(
                failure: .visualDecoding,
                title: "Analysis Failed",
                subtitle: "Data Unreadable",
                reasoning: "The AI failed to understand the image or produced an unreadable schema."
            )
        ]
        for hasQueuedScan in [true, false] {
            for testCase in cases {
                let presentation = try #require(InferenceFailurePresentation.make(
                    for: testCase.failure, hasQueuedScan: hasQueuedScan
                ))
                #expect(presentation == .init(
                    title: testCase.title,
                    subtitle: testCase.subtitle,
                    reasoning: testCase.reasoning
                ))
            }
        }
    }

    @Test(arguments: [true, false])
    func genericFailuresDistinguishSavedAndDirectRequests(hasQueuedScan: Bool) throws {
        let network = try #require(InferenceFailurePresentation.make(
            for: .connectivity, hasQueuedScan: hasQueuedScan
        ))
        let service = try #require(InferenceFailurePresentation.make(
            for: .service, hasQueuedScan: hasQueuedScan
        ))
        #expect(network.title == "Network timeout")
        #expect(service.title == "Analysis delayed")
        #expect(network.subtitle == (hasQueuedScan ? "Scan saved" : "Please try again"))
        #expect(service.subtitle == network.subtitle)
        #expect(network.reasoning == "Naturebook couldn’t reach the analysis service. Check your connection and try again.")
        #expect(service.reasoning == (hasQueuedScan
            ? "Naturebook saved this scan and will retry it automatically. You can leave this screen and check Scans later."
            : "Naturebook couldn’t complete this analysis because the service returned an unexpected response. Please try again."))
        #expect(InferenceFailurePresentation.make(for: .dailyQuotaExceeded, hasQueuedScan: hasQueuedScan) == nil)
    }

    @Test func placeholderRoleDoesNotDependOnCopyAndPreservesTelemetry() {
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil,
            gpsElevation: nil, locationName: "Synthetic habitat",
            weatherCondition: "Test weather", weatherTemperatureF: 60,
            timeOfDay: nil, timestamp: "2026-09-02T12:00:00Z",
            zoomFactor: 2.5, estimatedSizeCm: nil
        )
        let value = InferenceFailurePresentation(
            title: "Arbitrary test title", subtitle: "Arbitrary test subtitle", reasoning: "Test reason"
        ).speciesData(telemetry: telemetry)
        #expect(value.isInferenceErrorPlaceholder)
        #expect(value.scanId == nil)
        #expect(value.commonName == "Arbitrary test title")
        #expect(value.scientificName == "Arbitrary test subtitle")
        #expect(value.insightData.aiReasoning == "Test reason")
        #expect(value.insightData.hazardType == "none")
        #expect(value.confidenceScore == 0)
        #expect(!value.isBiological)
        #expect(value.isLiveCapture)
        #expect(!value.isInvasive)
        #expect(value.ecologyType == "unknown")
        #expect(value.taxonomy == nil)
        #expect(value.similarSpecies == nil)
        #expect(value.referenceImageUrl == nil)
        #expect(value.wikipediaUrl == nil)
        #expect(value.wikipediaOverview == nil)
        #expect(value.locationName == telemetry.locationName)
        #expect(value.weatherCondition == telemetry.weatherCondition)
        #expect(value.weatherTemperatureF == telemetry.weatherTemperatureF)
        #expect(value.gpsLatitude == nil)
        #expect(value.gpsLongitude == nil)
        #expect(value.gpsElevation == nil)
        #expect(value.zoomFactor == 2.5)
        #expect(value.colors == nil)
        #expect(value.groupTags == nil)
        #expect(value.iucnRedListStatus == nil)
    }
}
