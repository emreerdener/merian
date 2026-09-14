import Foundation

@MainActor
extension InferenceLiveFailureCoordinator.Dependencies {
    /// Fallback composition for direct engine construction. Manager references
    /// resolve lazily so initializing `AppDIContainer.shared` cannot recurse.
    static func live(
        requestPaywall: (@MainActor () -> Void)? = nil
    ) -> Self {
        let resolvedRequestPaywall: @MainActor () -> Void =
            requestPaywall ?? {
                UsageManager.shared.showPaywall = true
            }
        return make(
            circuitBreakerManager: { CircuitBreakerManager.shared },
            hapticManager: { HapticManager.shared },
            requestPaywall: resolvedRequestPaywall
        )
    }

    /// Production composition used by `AppDIContainer`.
    static func composed(
        circuitBreakerManager: CircuitBreakerManager,
        hapticManager: HapticManager,
        usageManager: UsageManager
    ) -> Self {
        make(
            circuitBreakerManager: { circuitBreakerManager },
            hapticManager: { hapticManager },
            requestPaywall: { usageManager.showPaywall = true }
        )
    }

    private static func make(
        circuitBreakerManager:
            @escaping @MainActor () -> CircuitBreakerManager,
        hapticManager: @escaping @MainActor () -> HapticManager,
        requestPaywall: @escaping @MainActor () -> Void
    ) -> Self {
        Self(
            trackError: { AppTelemetry.trackError($0) },
            recordCircuitFailure: {
                circuitBreakerManager().recordFailure()
            },
            requestPaywall: requestPaywall,
            triggerErrorFeedback: {
                hapticManager().triggerErrorThump()
            },
            logFailure: logFailure,
            logQueueHandoff: {
                MerianLog.general.debug(
                    "Live inference handed presentation to durable queue state."
                )
            }
        )
    }

    private static func logFailure(
        _ failure: InferenceLiveFailurePolicy.Failure,
        _ error: Error,
        _ mode: InferenceLiveFailurePolicy.Mode,
        _ scanId: String
    ) {
        switch failure {
        case .recoverableConflict:
            MerianLog.general.debug(
                "Inference response was ambiguous after server acceptance; restoring scanId=\(scanId, privacy: .public)"
            )
        case .consentRequired:
            MerianLog.general.debug(
                "Inference paused until required consent is authoritative; the queued scan remains saved."
            )
        case .proRequired, .rateLimited:
            let code: String
            if case .rateLimited(let limit) = failure {
                code = limit.rawValue
            } else {
                code = "pro_required"
            }
            MerianLog.general.debug(
                "Inference paused by provider admission policy code=\(code, privacy: .public); the queued scan remains saved."
            )
        case .dailyQuotaExceeded:
            MerianLog.general.debug(
                "Inference daily quota exhausted; requesting the paywall while the queued scan remains saved."
            )
        case .observationRejected:
            MerianLog.general.debug(
                "Inference observation was rejected by policy; a different capture is required."
            )
        case .visualDecoding:
            break
        case .connectivity, .service:
            if mode == .visual {
                MerianLog.general.debug(
                    "Inference failure: \(error.localizedDescription, privacy: .private)"
                )
            } else {
                MerianLog.general.debug(
                    "Non-visual inference failure: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }
}
