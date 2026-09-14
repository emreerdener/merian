import Foundation

/// Owns synchronous live-failure and durable queue-handoff orchestration.
///
/// The coordinator performs no suspension or task creation. It snapshots exact
/// attempt ownership, applies durable release/retirement through the attempt
/// coordinator, sequences non-presentation effects, and emits only narrow
/// presentation actions for its state-owning caller to apply synchronously.
@MainActor
final class InferenceLiveFailureCoordinator {
    struct Dependencies {
        let trackError: @MainActor (String) -> Void
        let recordCircuitFailure: @MainActor () -> Void
        let requestPaywall: @MainActor () -> Void
        let triggerErrorFeedback: @MainActor () -> Void
        let logFailure:
            @MainActor (
                InferenceLiveFailurePolicy.Failure,
                Error,
                InferenceLiveFailurePolicy.Mode,
                String
            ) -> Void
        let logQueueHandoff: @MainActor () -> Void
    }

    enum PresentationAction {
        case retainRecoverableScan(String)
        case transitionToQueue(scanId: String, attemptGeneration: UUID)
        case publishFailure(SpeciesData)
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

    /// Handles one failed visual or nonvisual attempt without introducing a
    /// suspension between its ownership snapshot, durable retirement, and
    /// terminal presentation/effects.
    func handle(
        _ error: Error,
        mode: InferenceLiveFailurePolicy.Mode,
        scanId: String?,
        resolvedClientScanId: String,
        attemptGeneration: UUID,
        foregroundGeneration: UUID?,
        telemetry: CaptureTelemetry,
        isTaskCancelled: Bool,
        applyPresentation: (PresentationAction) -> Void
    ) {
        let stillOwnsAttempt = attemptCoordinator.isAttemptCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: foregroundGeneration
        )

        switch InferenceLiveFailurePolicy.interruption(
            for: error,
            isTaskCancelled: isTaskCancelled
        ) {
        case .taskCancellation:
            if stillOwnsAttempt {
                releaseForRecovery(
                    scanId: scanId,
                    attemptGeneration: attemptGeneration,
                    foregroundGeneration: foregroundGeneration,
                    reason: mode.cancellationReason
                )
            }
            return
        case .ownershipCancellation:
            if publishRetiredOwnershipHandoffIfNeeded(
                scanId: scanId,
                attemptGeneration: attemptGeneration,
                foregroundGeneration: foregroundGeneration,
                applyPresentation: applyPresentation
            ) {
                return
            }
            if stillOwnsAttempt {
                releaseForRecovery(
                    scanId: scanId,
                    attemptGeneration: attemptGeneration,
                    foregroundGeneration: foregroundGeneration,
                    reason: mode.cancellationReason
                )
            }
            return
        case .transportCancellation:
            _ = publishQueueHandoffIfNeeded(
                scanId: scanId,
                attemptGeneration: attemptGeneration,
                foregroundGeneration: foregroundGeneration,
                telemetryEvent: "InferenceQueuedForTransportCancellation",
                reason: mode.transportCancellationReason,
                applyPresentation: applyPresentation
            )
            return
        case nil:
            break
        }

        // Connectivity monitoring can retire durable ownership before the
        // transport returns. The still-current local presentation may hand off
        // to that queue owner, but it cannot publish a generic failure.
        if InferenceLiveFailurePolicy.isConnectivityFailure(error),
           publishQueueHandoffIfNeeded(
               scanId: scanId,
               attemptGeneration: attemptGeneration,
               foregroundGeneration: foregroundGeneration,
               telemetryEvent: "InferenceQueuedForConnectivity",
               reason: "live_connectivity_handoff",
               applyPresentation: applyPresentation
           ) {
            return
        }

        guard stillOwnsAttempt else { return }
        releaseForRecovery(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: foregroundGeneration,
            reason: mode.failureReason
        )
        // Queue effects are synchronous and may re-enter with a replacement
        // attempt. Do not let the displaced failure publish over that owner.
        guard attemptCoordinator.isLocalAttemptCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration
        ) else {
            return
        }
        if scanId != nil {
            applyPresentation(.retainRecoverableScan(resolvedClientScanId))
        }

        publishTerminalFailure(
            InferenceLiveFailurePolicy.failure(for: error, mode: mode),
            error: error,
            mode: mode,
            scanId: resolvedClientScanId,
            ownerScanId: scanId,
            attemptGeneration: attemptGeneration,
            hasQueuedScan: scanId != nil,
            telemetry: telemetry,
            applyPresentation: applyPresentation
        )
    }

    private func publishTerminalFailure(
        _ failure: InferenceLiveFailurePolicy.Failure,
        error: Error,
        mode: InferenceLiveFailurePolicy.Mode,
        scanId: String,
        ownerScanId: String?,
        attemptGeneration: UUID,
        hasQueuedScan: Bool,
        telemetry: CaptureTelemetry,
        applyPresentation: (PresentationAction) -> Void
    ) {
        dependencies.trackError(failure.telemetryEvent(for: mode))
        if failure.recordsCircuitFailure {
            dependencies.recordCircuitFailure()
        }
        dependencies.logFailure(failure, error, mode, scanId)

        switch failure {
        case .dailyQuotaExceeded:
            // Quota exhaustion requests the root paywall without publishing an
            // Insight placeholder, error haptic, or circuit failure.
            dependencies.requestPaywall()
            return
        case .observationRejected:
            // Preserve release-before-disposition ordering. If this durable
            // transition fails, background recovery can apply the rejection.
            _ = attemptCoordinator.rejectQueuedScan(
                scanId: scanId,
                reason: InferenceFailurePresentation.observationRejected.reasoning,
                errorCode: "observation_rejected"
            )
            // Rejection is another synchronous queue boundary. A replacement
            // installed by that callback owns all subsequent presentation.
            guard attemptCoordinator.isLocalAttemptCurrent(
                scanId: ownerScanId,
                attemptGeneration: attemptGeneration
            ) else {
                return
            }
        default:
            break
        }

        if failure.triggersErrorFeedback {
            dependencies.triggerErrorFeedback()
        }
        if let presentation = InferenceFailurePresentation.make(
            for: failure,
            hasQueuedScan: hasQueuedScan
        ) {
            applyPresentation(
                .publishFailure(presentation.speciesData(telemetry: telemetry))
            )
        }
    }

    private func publishRetiredOwnershipHandoffIfNeeded(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundGeneration: UUID?,
        applyPresentation: (PresentationAction) -> Void
    ) -> Bool {
        guard let scanId, let foregroundGeneration,
              !attemptCoordinator.isDurableAttemptCurrent(
                  scanId: scanId,
                  generation: foregroundGeneration
              ) else {
            return false
        }
        return publishQueueHandoffIfNeeded(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: foregroundGeneration,
            telemetryEvent: "InferenceQueuedAfterOwnershipRetirement",
            reason: "live_ownership_retired",
            applyPresentation: applyPresentation
        )
    }

    private func publishQueueHandoffIfNeeded(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundGeneration: UUID?,
        telemetryEvent: String,
        reason: String,
        applyPresentation: (PresentationAction) -> Void
    ) -> Bool {
        guard let scanId,
              foregroundGeneration != nil,
              attemptCoordinator.isLocalAttemptCurrent(
                  scanId: scanId,
                  attemptGeneration: attemptGeneration
              ) else {
            return false
        }

        releaseForRecovery(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: foregroundGeneration,
            reason: reason
        )
        // A synchronous release or retirement callback may install the next
        // owner. Treat that as a handled supersession without stale effects.
        guard attemptCoordinator.isLocalAttemptCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration
        ) else {
            return true
        }
        dependencies.trackError(telemetryEvent)
        dependencies.logQueueHandoff()
        applyPresentation(
            .transitionToQueue(
                scanId: scanId,
                attemptGeneration: attemptGeneration
            )
        )
        return true
    }

    private func releaseForRecovery(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundGeneration: UUID?,
        reason: String
    ) {
        guard let scanId, let foregroundGeneration else { return }
        attemptCoordinator.releaseDeferredUpload(
            scanId: scanId,
            foregroundGeneration: foregroundGeneration,
            reason: reason
        )
        attemptCoordinator.retireForegroundInferenceIfCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: foregroundGeneration,
            resumeBackground: true,
            reason: reason
        )
    }
}
