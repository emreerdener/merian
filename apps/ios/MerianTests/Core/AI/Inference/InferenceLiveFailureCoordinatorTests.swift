import Foundation
import Testing

@testable import Merian

@MainActor
private final class InferenceLiveFailureHarness {
    enum Event: Equatable {
        case release(String, UUID?, String)
        case retire(String, UUID, Bool, String)
        case reject(String, String, String)
        case telemetry(String)
        case circuitFailure
        case paywall
        case errorFeedback
        case failureLog(
            InferenceLiveFailurePolicy.Failure,
            InferenceLiveFailurePolicy.Mode,
            String
        )
        case queueLog
        case retainRecoverableScan(String)
        case transitionToQueue(String, UUID)
        case publishFailure(String, String)
    }

    var durableAttemptIsCurrent = true
    var onRelease: (@MainActor () -> Void)?
    var onRetire: (@MainActor () -> Void)?
    var onReject: (@MainActor () -> Void)?
    private(set) var events: [Event] = []
    private weak var attemptCoordinator: InferenceLiveAttemptCoordinator?

    var queueService: InferenceLiveQueueService {
        InferenceLiveQueueService(dependencies: .init(
            releaseDeferredUpload: { [self] scanId, generation, reason in
                onRelease?()
                events.append(.release(scanId, generation, reason))
            },
            retireForegroundInference: { [self] scanId, generation, resumeBackground, reason in
                onRetire?()
                events.append(
                    .retire(
                        scanId,
                        generation,
                        resumeBackground,
                        reason
                    )
                )
            },
            claimForegroundInferenceStart: { _, _ in true },
            isForegroundInferenceAttemptCurrent: { [self] _, _ in
                durableAttemptIsCurrent
            },
            foregroundInferenceGeneration: { _ in nil },
            deleteQueuedScan: { _, _, _ in true },
            rejectQueuedScan: { [self] scanId, reason, errorCode in
                onReject?()
                events.append(.reject(scanId, reason, errorCode))
                return true
            }
        ))
    }

    var failureDependencies: InferenceLiveFailureCoordinator.Dependencies {
        .init(
            trackError: { [self] event in
                events.append(.telemetry(event))
            },
            recordCircuitFailure: { [self] in
                events.append(.circuitFailure)
            },
            requestPaywall: { [self] in
                events.append(.paywall)
            },
            triggerErrorFeedback: { [self] in
                events.append(.errorFeedback)
            },
            logFailure: { [self] failure, _, mode, scanId in
                events.append(.failureLog(failure, mode, scanId))
            },
            logQueueHandoff: { [self] in
                events.append(.queueLog)
            }
        )
    }

    func makeSubject(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundGeneration: UUID?
    ) -> InferenceLiveFailureCoordinator {
        let attemptCoordinator = InferenceLiveAttemptCoordinator(
            queueService: queueService
        )
        self.attemptCoordinator = attemptCoordinator
        attemptCoordinator.activate(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: foregroundGeneration
        )
        return InferenceLiveFailureCoordinator(
            attemptCoordinator: attemptCoordinator,
            dependencies: failureDependencies
        )
    }

    func activateReplacement(
        scanId: String,
        attemptGeneration: UUID,
        foregroundGeneration: UUID
    ) {
        attemptCoordinator?.activate(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: foregroundGeneration
        )
    }

    func record(_ action: InferenceLiveFailureCoordinator.PresentationAction) {
        switch action {
        case .retainRecoverableScan(let scanId):
            events.append(.retainRecoverableScan(scanId))
        case .transitionToQueue(let scanId, let attemptGeneration):
            events.append(.transitionToQueue(scanId, attemptGeneration))
        case .publishFailure(let data):
            events.append(
                .publishFailure(data.commonName, data.scientificName)
            )
        }
    }
}

@MainActor
@Suite("Inference Live Failure Coordinator")
struct InferenceLiveFailureCoordinatorTests {
    @Test func terminalFailurePreservesRetirementAndEffectOrder() {
        let harness = InferenceLiveFailureHarness()
        let attempt = UUID()
        let foreground = UUID()
        let subject = harness.makeSubject(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )

        subject.handle(
            MerianError.invalidResponse,
            mode: .visual,
            scanId: "scan-a",
            resolvedClientScanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground,
            telemetry: telemetry,
            isTaskCancelled: false,
            applyPresentation: harness.record
        )

        #expect(harness.events == [
            .release("scan-a", foreground, "live_request_failed"),
            .retire("scan-a", foreground, true, "live_request_failed"),
            .retainRecoverableScan("scan-a"),
            .telemetry("InferenceServiceFailure"),
            .circuitFailure,
            .failureLog(.service, .visual, "scan-a"),
            .errorFeedback,
            .publishFailure("Analysis delayed", "Scan saved")
        ])
    }

    @Test func queueLessFailureUsesRetryPresentationWithoutQueueEffects() {
        let harness = InferenceLiveFailureHarness()
        let attempt = UUID()
        let mode = InferenceLiveFailurePolicy.Mode.nonVisual(hasAudio: false)
        let subject = harness.makeSubject(
            scanId: nil,
            attemptGeneration: attempt,
            foregroundGeneration: nil
        )

        subject.handle(
            MerianError.invalidResponse,
            mode: mode,
            scanId: nil,
            resolvedClientScanId: "client-scan",
            attemptGeneration: attempt,
            foregroundGeneration: nil,
            telemetry: telemetry,
            isTaskCancelled: false,
            applyPresentation: harness.record
        )

        #expect(harness.events == [
            .telemetry("DescribeInferenceFailure"),
            .circuitFailure,
            .failureLog(.service, mode, "client-scan"),
            .errorFeedback,
            .publishFailure("Analysis delayed", "Please try again")
        ])
    }

    @Test func taskCancellationReleasesOnlyTheCurrentAttempt() {
        let harness = InferenceLiveFailureHarness()
        let attempt = UUID()
        let foreground = UUID()
        let subject = harness.makeSubject(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )

        subject.handle(
            MerianError.invalidResponse,
            mode: .nonVisual(hasAudio: true),
            scanId: "scan-a",
            resolvedClientScanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground,
            telemetry: telemetry,
            isTaskCancelled: true,
            applyPresentation: harness.record
        )

        #expect(harness.events == [
            .release("scan-a", foreground, "live_nonvisual_cancelled"),
            .retire(
                "scan-a",
                foreground,
                true,
                "live_nonvisual_cancelled"
            )
        ])
    }

    @Test func retiredDurableOwnerHandsTheLocalPresentationToQueue() {
        let harness = InferenceLiveFailureHarness()
        harness.durableAttemptIsCurrent = false
        let attempt = UUID()
        let foreground = UUID()
        let subject = harness.makeSubject(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )

        subject.handle(
            CancellationError(),
            mode: .visual,
            scanId: "scan-a",
            resolvedClientScanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground,
            telemetry: telemetry,
            isTaskCancelled: false,
            applyPresentation: harness.record
        )

        #expect(harness.events == [
            .release("scan-a", foreground, "live_ownership_retired"),
            .retire("scan-a", foreground, true, "live_ownership_retired"),
            .telemetry("InferenceQueuedAfterOwnershipRetirement"),
            .queueLog,
            .transitionToQueue("scan-a", attempt)
        ])
    }

    @Test func transportCancellationHandsCurrentPresentationToQueue() {
        let harness = InferenceLiveFailureHarness()
        let attempt = UUID()
        let foreground = UUID()
        let subject = harness.makeSubject(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )

        subject.handle(
            URLError(.cancelled),
            mode: .visual,
            scanId: "scan-a",
            resolvedClientScanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground,
            telemetry: telemetry,
            isTaskCancelled: false,
            applyPresentation: harness.record
        )

        #expect(harness.events == [
            .release("scan-a", foreground, "live_transport_cancelled"),
            .retire("scan-a", foreground, true, "live_transport_cancelled"),
            .telemetry("InferenceQueuedForTransportCancellation"),
            .queueLog,
            .transitionToQueue("scan-a", attempt)
        ])
    }

    @Test func connectivityFailureHandsCurrentPresentationToQueue() {
        let harness = InferenceLiveFailureHarness()
        let attempt = UUID()
        let foreground = UUID()
        let subject = harness.makeSubject(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )

        subject.handle(
            URLError(.notConnectedToInternet),
            mode: .visual,
            scanId: "scan-a",
            resolvedClientScanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground,
            telemetry: telemetry,
            isTaskCancelled: false,
            applyPresentation: harness.record
        )

        #expect(harness.events == [
            .release("scan-a", foreground, "live_connectivity_handoff"),
            .retire("scan-a", foreground, true, "live_connectivity_handoff"),
            .telemetry("InferenceQueuedForConnectivity"),
            .queueLog,
            .transitionToQueue("scan-a", attempt)
        ])
    }

    @Test func staleFailureCannotRetirePublishOrRequestPaywall() {
        let harness = InferenceLiveFailureHarness()
        let currentAttempt = UUID()
        let foreground = UUID()
        let subject = harness.makeSubject(
            scanId: "scan-a",
            attemptGeneration: currentAttempt,
            foregroundGeneration: foreground
        )

        subject.handle(
            quotaError,
            mode: .visual,
            scanId: "scan-a",
            resolvedClientScanId: "scan-a",
            attemptGeneration: UUID(),
            foregroundGeneration: foreground,
            telemetry: telemetry,
            isTaskCancelled: false,
            applyPresentation: harness.record
        )

        #expect(harness.events.isEmpty)
    }

    @Test func releaseReentrancyCannotPublishOverReplacement() {
        let harness = InferenceLiveFailureHarness()
        let originalAttemptGeneration = UUID()
        let originalForegroundGeneration = UUID()
        let replacementAttemptGeneration = UUID()
        let replacementForegroundGeneration = UUID()
        let subject = harness.makeSubject(
            scanId: "scan-a",
            attemptGeneration: originalAttemptGeneration,
            foregroundGeneration: originalForegroundGeneration
        )
        harness.onRelease = { [weak harness] in
            harness?.activateReplacement(
                scanId: "scan-b",
                attemptGeneration: replacementAttemptGeneration,
                foregroundGeneration: replacementForegroundGeneration
            )
        }

        subject.handle(
            MerianError.invalidResponse,
            mode: .visual,
            scanId: "scan-a",
            resolvedClientScanId: "scan-a",
            attemptGeneration: originalAttemptGeneration,
            foregroundGeneration: originalForegroundGeneration,
            telemetry: telemetry,
            isTaskCancelled: false,
            applyPresentation: harness.record
        )

        #expect(harness.events == [
            .release(
                "scan-a",
                originalForegroundGeneration,
                "live_request_failed"
            )
        ])
    }

    @Test func retirementReentrancyCannotPublishQueueHandoffOverReplacement() {
        let harness = InferenceLiveFailureHarness()
        let originalAttemptGeneration = UUID()
        let originalForegroundGeneration = UUID()
        let replacementAttemptGeneration = UUID()
        let replacementForegroundGeneration = UUID()
        let subject = harness.makeSubject(
            scanId: "scan-a",
            attemptGeneration: originalAttemptGeneration,
            foregroundGeneration: originalForegroundGeneration
        )
        harness.onRetire = { [weak harness] in
            harness?.activateReplacement(
                scanId: "scan-b",
                attemptGeneration: replacementAttemptGeneration,
                foregroundGeneration: replacementForegroundGeneration
            )
        }

        subject.handle(
            URLError(.cancelled),
            mode: .visual,
            scanId: "scan-a",
            resolvedClientScanId: "scan-a",
            attemptGeneration: originalAttemptGeneration,
            foregroundGeneration: originalForegroundGeneration,
            telemetry: telemetry,
            isTaskCancelled: false,
            applyPresentation: harness.record
        )

        #expect(harness.events == [
            .release(
                "scan-a",
                originalForegroundGeneration,
                "live_transport_cancelled"
            ),
            .retire(
                "scan-a",
                originalForegroundGeneration,
                true,
                "live_transport_cancelled"
            )
        ])
    }

    @Test func dailyQuotaRequestsOnlyPaywallAfterRetirementAndLogging() {
        let harness = InferenceLiveFailureHarness()
        let attempt = UUID()
        let foreground = UUID()
        let subject = harness.makeSubject(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )

        subject.handle(
            quotaError,
            mode: .visual,
            scanId: "scan-a",
            resolvedClientScanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground,
            telemetry: telemetry,
            isTaskCancelled: false,
            applyPresentation: harness.record
        )

        #expect(harness.events == [
            .release("scan-a", foreground, "live_request_failed"),
            .retire("scan-a", foreground, true, "live_request_failed"),
            .retainRecoverableScan("scan-a"),
            .telemetry("InferenceDailyQuotaExceeded"),
            .failureLog(.dailyQuotaExceeded, .visual, "scan-a"),
            .paywall
        ])
    }

    @Test func observationRejectionDisposesQueueBeforeFeedbackAndCopy() {
        let harness = InferenceLiveFailureHarness()
        let attempt = UUID()
        let foreground = UUID()
        let subject = harness.makeSubject(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )

        subject.handle(
            rejectionError,
            mode: .visual,
            scanId: "scan-a",
            resolvedClientScanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground,
            telemetry: telemetry,
            isTaskCancelled: false,
            applyPresentation: harness.record
        )

        #expect(harness.events == [
            .release("scan-a", foreground, "live_request_failed"),
            .retire("scan-a", foreground, true, "live_request_failed"),
            .retainRecoverableScan("scan-a"),
            .telemetry("InferenceObservationRejected"),
            .failureLog(.observationRejected, .visual, "scan-a"),
            .reject(
                "scan-a",
                InferenceFailurePresentation.observationRejected.reasoning,
                "observation_rejected"
            ),
            .errorFeedback,
            .publishFailure("Try another capture", "Scan not processed")
        ])
    }

    @Test func rejectionReentrancyCannotPublishOverReplacement() {
        let harness = InferenceLiveFailureHarness()
        let originalAttemptGeneration = UUID()
        let originalForegroundGeneration = UUID()
        let subject = harness.makeSubject(
            scanId: "scan-a",
            attemptGeneration: originalAttemptGeneration,
            foregroundGeneration: originalForegroundGeneration
        )
        harness.onReject = { [weak harness] in
            harness?.activateReplacement(
                scanId: "scan-b",
                attemptGeneration: UUID(),
                foregroundGeneration: UUID()
            )
        }

        subject.handle(
            rejectionError,
            mode: .visual,
            scanId: "scan-a",
            resolvedClientScanId: "scan-a",
            attemptGeneration: originalAttemptGeneration,
            foregroundGeneration: originalForegroundGeneration,
            telemetry: telemetry,
            isTaskCancelled: false,
            applyPresentation: harness.record
        )

        #expect(harness.events == [
            .release(
                "scan-a",
                originalForegroundGeneration,
                "live_request_failed"
            ),
            .retire(
                "scan-a",
                originalForegroundGeneration,
                true,
                "live_request_failed"
            ),
            .retainRecoverableScan("scan-a"),
            .telemetry("InferenceObservationRejected"),
            .failureLog(.observationRejected, .visual, "scan-a"),
            .reject(
                "scan-a",
                InferenceFailurePresentation.observationRejected.reasoning,
                "observation_rejected"
            )
        ])
    }

    private var telemetry: CaptureTelemetry {
        CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: nil,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: "2026-09-12T12:00:00Z",
            zoomFactor: nil,
            estimatedSizeCm: nil
        )
    }

    private var quotaError: MerianError {
        .httpError(
            statusCode: 429,
            message: #"{"code":"ai_quota_daily_exceeded"}"#
        )
    }

    private var rejectionError: MerianError {
        .httpError(
            statusCode: 400,
            message: #"{"code":"observation_rejected"}"#
        )
    }
}
