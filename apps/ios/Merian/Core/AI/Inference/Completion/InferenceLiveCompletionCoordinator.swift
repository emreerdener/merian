import Foundation
import SwiftData

/// Normalizes one accepted live result and authorizes post-commit effects only
/// while the exact presentation owner remains current.
///
/// `InferenceEngine` retains observable state publication, benchmark timing,
/// and modality-specific hydration order. This coordinator owns the shared
/// discovery, replacement, telemetry, durable-finalization, notification,
/// foreground-event, and milestone boundary for visual and nonvisual results.
@MainActor
final class InferenceLiveCompletionCoordinator {
    struct Dependencies {
        let recordNewSpeciesDiscovered: @MainActor () -> Void
        let transferReplacementMetadataAndDeleteOriginal:
            @MainActor (
                String?,
                InferenceLiveResultService.Outcome,
                ModelContext?
            ) -> Void
        let recordCircuitSuccess: @MainActor () -> Void
        let trackCompletedScan: @MainActor (String?, String?) -> Void
        let sendEvent: @MainActor (AppEvent) -> Void
        let notificationsEnabled: @MainActor () -> Bool
        let sendInferenceCompleteNotification:
            @MainActor (String, String) -> Void
        let scheduleMilestoneProcessing:
            @MainActor (String, SpeciesData, ModelContainer?) -> Void
    }

    struct PreparedCompletion {
        let speciesData: SpeciesData
        let savedImagePaths: [String]

        var mediaPathsToKeep: [String] {
            (speciesData.audioFilePaths ?? []) +
                (speciesData.videoFilePaths ?? [])
        }
    }

    /// Capability returned only after a committed result still owns the local
    /// presentation and, when required, its exact durable queue row finalized.
    struct FollowUpPermit {
        let speciesData: SpeciesData
        let modelContainer: ModelContainer?

        fileprivate init(
            speciesData: SpeciesData,
            modelContainer: ModelContainer?
        ) {
            self.speciesData = speciesData
            self.modelContainer = modelContainer
        }
    }

    private let attemptCoordinator: InferenceLiveAttemptCoordinator
    private let dependencies: Dependencies

    init(
        attemptCoordinator: InferenceLiveAttemptCoordinator,
        dependencies: Dependencies
    ) {
        self.attemptCoordinator = attemptCoordinator
        self.dependencies = dependencies
    }

    func prepare(
        outcome: InferenceLiveResultService.Outcome,
        targetEradicationScanId: String?,
        modelContext: ModelContext?
    ) -> PreparedCompletion? {
        guard let completedResult = outcome.completedResult else {
            return nil
        }

        var speciesData = completedResult.speciesData
        if completedResult.isNewDiscovery {
            speciesData.isNewDiscovery = true
            dependencies.recordNewSpeciesDiscovered()
        }
        dependencies.transferReplacementMetadataAndDeleteOriginal(
            targetEradicationScanId,
            outcome,
            modelContext
        )
        dependencies.recordCircuitSuccess()
        dependencies.trackCompletedScan(
            speciesData.inferenceTier,
            completedResult.planUsed
        )

        return PreparedCompletion(
            speciesData: speciesData,
            savedImagePaths: completedResult.savedImagePaths
        )
    }

    func publishForegroundCompletionEventIfNeeded(
        for speciesData: SpeciesData
    ) {
        guard speciesData.isBiological,
              let scanId = speciesData.scanId else { return }
        dependencies.sendEvent(
            .foregroundBiologicalScanCompleted(scanId: scanId)
        )
    }

    /// Queue-less nonvisual requests use this synchronous path so result
    /// publication and the ownership recheck retain their existing timing.
    func authorizeQueueLessFollowUps(
        scanId: String?,
        attemptGeneration: UUID,
        speciesData: SpeciesData,
        modelContainer: ModelContainer?
    ) -> FollowUpPermit? {
        guard scanId == nil else { return nil }
        return permitIfCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            speciesData: speciesData,
            modelContainer: modelContainer
        )
    }

    /// Finalizes the exact durable owner, then rechecks process-local ownership
    /// after the suspension before granting any notification or follow-up work.
    func finalizeQueueAndAuthorizeFollowUps(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundGeneration: UUID?,
        mediaPathsToKeep: [String],
        speciesData: SpeciesData,
        modelContainer: ModelContainer?
    ) async -> FollowUpPermit? {
        guard await attemptCoordinator.completeQueuedInferenceIfNeeded(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: foregroundGeneration,
            mediaPathsToKeep: mediaPathsToKeep
        ) else {
            return nil
        }

        return permitIfCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            speciesData: speciesData,
            modelContainer: modelContainer
        )
    }

    func sendNotificationIfEnabled(_ permit: FollowUpPermit) {
        guard dependencies.notificationsEnabled(),
              let scanId = permit.speciesData.scanId else { return }
        dependencies.sendInferenceCompleteNotification(
            permit.speciesData.commonName,
            scanId
        )
    }

    func scheduleMilestones(_ permit: FollowUpPermit) {
        guard let scanId = permit.speciesData.scanId else { return }
        dependencies.scheduleMilestoneProcessing(
            scanId,
            permit.speciesData,
            permit.modelContainer
        )
    }

    private func permitIfCurrent(
        scanId: String?,
        attemptGeneration: UUID,
        speciesData: SpeciesData,
        modelContainer: ModelContainer?
    ) -> FollowUpPermit? {
        guard attemptCoordinator.isAttemptCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: nil
        ) else {
            return nil
        }
        return FollowUpPermit(
            speciesData: speciesData,
            modelContainer: modelContainer
        )
    }
}
