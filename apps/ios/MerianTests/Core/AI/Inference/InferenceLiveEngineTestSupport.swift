import Foundation
import SwiftData
import Testing

@testable import Merian

/// Injected result/recovery fixtures. Callers claim networkClientOverrides
/// before shared engine setup and also offlineQueueManager for queue-backed
/// cases; this helper never replaces the global queue context itself.
@MainActor
enum InferenceLiveEngineTestSupport {
    static func withState(_ operation: @MainActor () async throws -> Void) async throws {
        let key = UserDefaultsKeys.localLookalikesCacheResetVersion
        let previousResetVersion = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(MerianConfig.localLookalikesCacheResetVersion, forKey: key)
        CircuitBreakerManager.shared.recordSuccess()
        defer {
            UserDefaults.standard.set(previousResetVersion, forKey: key)
            CircuitBreakerManager.shared.recordSuccess()
        }
        try await operation()
    }

    static func makeEngine(
        resultService: InferenceLiveResultService,
        requestPaywall: @escaping @MainActor () -> Void = {
            Issue.record("This fixture must not request the paywall")
        }
    ) -> InferenceEngine {
        InferenceEngine(
            liveRequestService: InferenceLiveRequestService(dependencies: .init(
                encodeVisualImages: { images in images.map { _ in "encoded-image" } },
                uploadStagedVideoFiles: { _, _ in
                    Issue.record("These fixtures must not upload staged video")
                    return []
                },
                identify: { _, onRequestBodySent in
                    onRequestBodySent?()
                    return Data("injected-response".utf8)
                }
            )),
            liveResultService: resultService,
            requestPaywall: requestPaywall
        )
    }

    static func start(
        _ engine: InferenceEngine,
        mode: InferenceLiveFailurePolicy.Mode,
        mediaTimeline: [CaptureSubmissionMediaItem]? = nil,
        modelContext: ModelContext? = nil,
        scanId: String? = nil,
        foregroundInferenceGeneration: UUID? = nil,
        targetEradicationScanId: String? = nil
    ) {
        engine.prepareForNewScan()
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil,
            gpsElevation: nil, locationName: nil, weatherCondition: nil,
            weatherTemperatureF: nil, timeOfDay: nil,
            timestamp: "2026-09-02T12:00:00Z", zoomFactor: nil, estimatedSizeCm: nil
        )
        switch mode {
        case .visual:
            engine.analyze(
                scanId: scanId,
                foregroundInferenceGeneration: foregroundInferenceGeneration,
                imageDatas: [Data([0x01])], displayDatas: [Data([0x11])],
                telemetry: telemetry, mediaTimeline: mediaTimeline,
                modelContext: modelContext,
                targetEradicationScanId: targetEradicationScanId
            )
        case .nonVisual(let hasAudio):
            engine.analyzeNonVisual(
                scanId: scanId,
                foregroundInferenceGeneration: foregroundInferenceGeneration,
                // The injected Identify closure never reads or uploads bytes.
                audioFilePaths: hasAudio ? ["fixture-audio.wav"] : nil,
                observationContexts: [ObservationContext(freeText: "striped wings")],
                mediaTimeline: mediaTimeline, telemetry: telemetry, modelContext: modelContext,
                targetEradicationScanId: targetEradicationScanId
            )
        }
    }
}

/// A single-operation, cancellation-ignoring suspension for deterministic races.
actor InferenceOperationGate {
    private var hasStarted = false
    private var isReleased = false
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        hasStarted = true
        startWaiter?.resume()
        startWaiter = nil
        guard !isReleased else { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        isReleased = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
