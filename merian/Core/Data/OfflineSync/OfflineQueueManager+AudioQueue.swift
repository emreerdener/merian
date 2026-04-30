import Foundation
import SwiftData

// MARK: - Audio Enqueue

extension OfflineQueueManager {

    /// Convenience wrapper for queueing a single audio capture through the shared
    /// non-visual pipeline.
    @MainActor
    @discardableResult
    func enqueueAudio(audioFileName: String, telemetry: CaptureTelemetry, scanId: String? = nil) -> Bool {
        guard !audioFileName.isEmpty else { return false }

        return enqueueNonVisualCapture(
            audioFileNames: [audioFileName],
            observationContexts: [],
            mediaTimeline: [.audio(audioFileName)],
            telemetry: telemetry,
            scanId: scanId
        )
    }
}
