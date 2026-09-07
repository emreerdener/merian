import Foundation

// MARK: - Describe Capture Admission

extension OfflineQueueManager {
    /// Enqueues a description-only describe scan for offline retry.
    ///
    /// Describes carry no image files, so they enter the queue at `.staged` directly,
    /// bypassing the R2 upload phase entirely. `replayInferenceStagedScans` picks them
    /// up and dispatches a `/identify-multimodal` background download task when connectivity
    /// restores — routed by `dispatchInferenceDownloadTask` which detects the empty
    /// `localImagePaths` and non-nil `observationContextsJSON`.
    ///
    /// Quota is consumed at enqueue time, mirroring `enqueueCapture`, so the scan slot
    /// is allocated before any async boundary is crossed.
    @MainActor
    func enqueueDescribe(
        observationContext: ObservationContext,
        telemetry: CaptureTelemetry,
        scanId: String? = nil
    ) {
        guard !observationContext.isEmpty else { return }
        _ = enqueueNonVisualCapture(
            audioFileNames: [],
            observationContexts: [observationContext],
            mediaTimeline: [.description(observationContext)],
            telemetry: telemetry,
            scanId: scanId
        )
    }
}
