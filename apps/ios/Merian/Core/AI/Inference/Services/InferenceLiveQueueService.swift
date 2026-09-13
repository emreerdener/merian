import Foundation

/// The narrow durable-queue boundary used by foreground inference attempts.
///
/// `InferenceEngine` retains presentation and call ordering. The live adapter
/// is the only Core AI owner that resolves `OfflineQueueManager` for attempt
/// admission, upload release, retirement, finalization, and rejection.
@MainActor
struct InferenceLiveQueueService {
    struct Dependencies: Sendable {
        let releaseDeferredUpload:
            @MainActor @Sendable (String, UUID?, String) -> Void
        let retireForegroundInference:
            @MainActor @Sendable (String, UUID, Bool, String) -> Void
        let claimForegroundInferenceStart:
            @MainActor @Sendable (String, UUID) -> Bool
        let isForegroundInferenceAttemptCurrent:
            @MainActor @Sendable (String, UUID) -> Bool
        let foregroundInferenceGeneration:
            @MainActor @Sendable (String) -> UUID?
        let deleteQueuedScan:
            @MainActor @Sendable (String, [String], UUID) async -> Bool
        let rejectQueuedScan:
            @MainActor @Sendable (String, String, String) -> Bool
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func releaseDeferredUpload(
        scanId: String,
        foregroundGeneration: UUID?,
        reason: String
    ) {
        dependencies.releaseDeferredUpload(
            scanId,
            foregroundGeneration,
            reason
        )
    }

    func retireForegroundInference(
        scanId: String,
        generation: UUID,
        resumeBackground: Bool,
        reason: String
    ) {
        dependencies.retireForegroundInference(
            scanId,
            generation,
            resumeBackground,
            reason
        )
    }

    func claimForegroundInferenceStart(
        scanId: String,
        generation: UUID
    ) -> Bool {
        dependencies.claimForegroundInferenceStart(scanId, generation)
    }

    func isForegroundInferenceAttemptCurrent(
        scanId: String,
        generation: UUID
    ) -> Bool {
        dependencies.isForegroundInferenceAttemptCurrent(scanId, generation)
    }

    func foregroundInferenceGeneration(for scanId: String) -> UUID? {
        dependencies.foregroundInferenceGeneration(scanId)
    }

    func deleteQueuedScan(
        scanId: String,
        explicitlyAdoptedMediaPaths: [String],
        foregroundGeneration: UUID
    ) async -> Bool {
        await dependencies.deleteQueuedScan(
            scanId,
            explicitlyAdoptedMediaPaths,
            foregroundGeneration
        )
    }

    @discardableResult
    func rejectQueuedScan(
        scanId: String,
        reason: String,
        errorCode: String
    ) -> Bool {
        dependencies.rejectQueuedScan(scanId, reason, errorCode)
    }
}
