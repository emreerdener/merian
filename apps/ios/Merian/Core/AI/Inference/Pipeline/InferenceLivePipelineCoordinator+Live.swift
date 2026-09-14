import Foundation

extension InferenceLivePipelineCoordinator.Dependencies {
    static var live: Self {
        make(
            circuitBreakerManager: { CircuitBreakerManager.shared },
            usageManager: { UsageManager.shared }
        )
    }

    static func composed(
        circuitBreakerManager: CircuitBreakerManager,
        usageManager: UsageManager
    ) -> Self {
        make(
            circuitBreakerManager: { circuitBreakerManager },
            usageManager: { usageManager }
        )
    }

    private static func make(
        circuitBreakerManager:
            @escaping @MainActor () -> CircuitBreakerManager,
        usageManager: @escaping @MainActor () -> UsageManager
    ) -> Self {
        Self(
            isCircuitTripped: {
                circuitBreakerManager().isCircuitTripped
            },
            refundScan: { scanId in
                usageManager().refundScan(scanId: scanId)
            },
            logAdmission: logAdmission,
            logEmptyVisualEncoding: {
                MerianLog.general.error(
                    "All base64 payloads are empty — corrupted capture data. Refunding scan."
                )
            },
            logBenchmark: logBenchmark
        )
    }

    private static func logAdmission(
        _ issue: InferenceLivePipelineCoordinator.AdmissionIssue,
        _ modality: InferenceLivePipelineCoordinator.Modality
    ) {
        let entryPoint = modality == .visual
            ? "analyze"
            : "analyzeNonVisual"
        switch issue {
        case .missingForegroundOwner(let scanId):
            MerianLog.general.debug(
                "\(entryPoint, privacy: .public): rejected missing foreground owner scanId=\(scanId, privacy: .public)"
            )
        case .duplicateForegroundOwner(let scanId):
            MerianLog.general.debug(
                "\(entryPoint, privacy: .public): ignored duplicate foreground generation scanId=\(scanId, privacy: .public)"
            )
        case .unavailableForegroundOwner(let scanId):
            let reason = modality == .visual
                ? "missing, stale, used, or retiring"
                : "stale, used, or retiring"
            MerianLog.general.debug(
                "\(entryPoint, privacy: .public): rejected \(reason, privacy: .public) foreground owner scanId=\(scanId, privacy: .public)"
            )
        case .foregroundOwnerWithoutScan:
            MerianLog.general.debug(
                "\(entryPoint, privacy: .public): rejected foreground owner without scanId"
            )
        }
    }

    private static func logBenchmark(
        _ benchmark: InferenceLivePipelineCoordinator.Benchmark
    ) {
        switch benchmark {
        case .tapToFirstRenderedFrame(let duration):
            MerianLog.general.debug(
                "[⏱ BENCH] Analyze tap to first rendered frame: \(String(format: "%.3f", duration), privacy: .public)s"
            )
        case .responseToFirstResult(let duration):
            MerianLog.general.debug(
                "[⏱ BENCH] Response to first-result state: \(String(format: "%.3f", duration), privacy: .public)s"
            )
        case .postFlight(let duration):
            MerianLog.general.debug(
                "[⏱ BENCH] Post-flight (parse+save+state): \(String(format: "%.3f", duration), privacy: .public)s"
            )
        case .total(let duration):
            MerianLog.general.debug(
                "[⏱ BENCH] Total pipeline: \(String(format: "%.3f", duration), privacy: .public)s"
            )
        }
    }
}
