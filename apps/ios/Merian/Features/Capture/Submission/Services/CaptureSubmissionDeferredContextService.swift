import Foundation

struct CaptureSubmissionDeferredContextEndpoint: Sendable {
    let update: @MainActor @Sendable (
        _ scanId: String,
        _ telemetry: CaptureTelemetry
    ) async throws -> Void

    @MainActor
    static func live(client: MerianNetworkClient = .shared) -> Self {
        Self(update: { scanId, telemetry in
            try await client.updateDeferredScanContext(
                scanId: scanId,
                telemetry: telemetry
            )
        })
    }
}

struct CaptureSubmissionDeferredContextService: Sendable {
    static let retryDelay = Duration.milliseconds(500)

    let persistLocally: @MainActor @Sendable (
        _ scanId: String,
        _ telemetry: CaptureTelemetry
    ) -> Void
    let endpoint: CaptureSubmissionDeferredContextEndpoint
    let waitBeforeRetry: @MainActor @Sendable () async throws -> Void

    @MainActor
    static func live(
        offlineQueueManager: OfflineQueueManager,
        client: MerianNetworkClient = .shared
    ) -> Self {
        Self(
            persistLocally: { scanId, telemetry in
                offlineQueueManager.updateDeferredContext(
                    scanId: scanId,
                    telemetry: telemetry
                )
            },
            endpoint: .live(client: client),
            waitBeforeRetry: {
                try await Task.sleep(for: retryDelay)
            }
        )
    }

    @MainActor
    func apply(scanId: String, telemetry: CaptureTelemetry) async {
        persistLocally(scanId, telemetry)
        do {
            try await endpoint.update(scanId, telemetry)
        } catch {
            guard !Task.isCancelled,
                  !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled else {
                return
            }
            // Context can beat the atomic ingestion claim by a few milliseconds.
            // Retry once; the durable local queue remains the fallback.
            do {
                try await waitBeforeRetry()
                try Task.checkCancellation()
            } catch {
                return
            }
            try? await endpoint.update(scanId, telemetry)
        }
    }
}
