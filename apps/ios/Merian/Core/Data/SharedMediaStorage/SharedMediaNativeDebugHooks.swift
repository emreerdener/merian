import Foundation

/// Typed test controls only; never account, file or mutation authority. The
/// registered owner supplies the instance through its sealed grants.
#if DEBUG
@MainActor
final class SharedMediaNativeDebugHooks {
    init() {}
    var lifecycleAvailableBytes: Int64?
    var lifecycleFault: ((SharedMediaNativeLifecycleBoundary) throws -> Void)?
    var preparationAvailableBytes: Int64?
    var preparationFileEpochObserved: ((UUID) -> Void)?
    var preparationFocusFactory = ImageFocusWorkFactory()
    var preparationFault: ((SharedMediaNativePreparationBoundary) throws -> Void)?
    var metadataFault: ((SharedMediaNativeMetadataBoundary) throws -> Void)?
    var metadataAvailableBytes: Int64?
    var inspectionAuditCount = 0
    var acquisitionFault: ((SharedMediaNativeAcquisitionBoundary) throws -> Void)?
    var shutdownFailure: (any Error)?
    private(set) var settlementTrace: [String] = []
    func recordSettlement(_ phase: String) { if settlementTrace.count < 64 { settlementTrace.append(phase) } }
    var bootstrapFault: ((SharedMediaNativeBootstrapBoundary) throws -> Void)?
    var bootstrapAvailableBytes: Int64?
    var scopedPagePause: (@Sendable () async -> Void)?
    var inspectionTrace: InspectionTrace?

    /// Opt-in test measurements only. Fixed counters and a bounded number of
    /// value-only phase reports; no identifiers, persistence or authority.
    @MainActor
    final class InspectionTrace {
        enum Phase: String {
            case identity, repository, inspect, pending, receipts, receivingRoots
            case receivingLeaves, receivingIdentities, receivingBoundary
            case consumers, pairs, allocations, references, inbox, finalHeader
        }
        struct Summary {
            let phase: Phase
            let completed: Bool
            let elapsed: Duration
            let checkpointCount: Int64
            let checkpointTime: Duration
            let saturated: Bool
        }
        private let report: (Summary) -> Void
        private var phase: Phase?
        private var started = ContinuousClock.now
        private var lastReport = ContinuousClock.now
        private var initialCount: Int64 = 0
        private var initialTime: Duration = .zero
        private var count: Int64 = 0
        private var time: Duration = .zero
        private var reports = 0
        private var saturated = false

        init(report: @escaping (Summary) -> Void) { self.report = report }
        func checkpoint(_ duration: Duration) {
            if count < 1_000_000 { count += 1 } else { saturated = true }
            let limit = Duration.seconds(86_400)
            if duration >= limit - time { time = limit; saturated = true }
            else { time += duration }
            // A timed-out phase still leaves bounded partial measurements.
            if lastReport.duration(to: .now) >= .seconds(30) { emit(completed: false) }
        }
        func enter(_ next: Phase) {
            finish()
            phase = next; started = .now; initialCount = count; initialTime = time
            emit(completed: false)
        }
        func finish() {
            if phase != nil { emit(completed: true); phase = nil }
        }
        private func emit(completed: Bool) {
            guard let phase else { return }
            guard reports < 64 else { saturated = true; return }
            reports += 1
            if reports == 64 { saturated = true }
            lastReport = .now
            report(.init(phase: phase, completed: completed,
                elapsed: started.duration(to: .now), checkpointCount: count - initialCount,
                checkpointTime: time - initialTime, saturated: saturated))
        }
    }
}
#endif

enum SharedMediaNativeInitializationBoundary: Sendable {
    case afterPhotoBinding, afterInboxBinding, afterAuthorityBinding, beforeSave, afterSave
}
