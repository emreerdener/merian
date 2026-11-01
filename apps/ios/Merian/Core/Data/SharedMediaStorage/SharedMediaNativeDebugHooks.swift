import Foundation

enum SharedMediaNativeInspectionComponent: String, CaseIterable {
    case roots, storeBinding, photoIdentity, inboxIdentity, profileMatch, databaseHeader
    case controlReadAndSync, controlFileSync, controlParentSync
    case bootstrapEnumeration, bootstrapDirectoryIdentity, bootstrapBackupExclusion, fileOwnerIdentity
    case directoryLexicalValidation, directoryDescriptorWalk
}

/// A call-local observation handle, never a persisted durability witness.
@MainActor
struct SharedMediaNativeInspectionMeasurement {
    #if DEBUG
    private let trace: SharedMediaNativeDebugHooks.InspectionTrace?
    #endif
    init(authority: SharedMediaNativeBootstrapAuthority? = nil) {
        #if DEBUG
        trace = authority?.debug?.inspectionTrace
        #endif
    }
    func measure<T>(_ component: SharedMediaNativeInspectionComponent, _ body: () throws -> T) rethrows -> T {
        #if DEBUG
        if let trace { return try trace.measure(component, body) }
        #endif
        return try body()
    }
}

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
    var inspectionReadFault: (() throws -> Void)?
    var inspectionPageFault: (() async throws -> Void)?
    struct ComponentSummary {
        let component: SharedMediaNativeInspectionComponent
        var calls: Int64 = 0
        var elapsed: Duration = .zero
        var saturated = false
    }

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
        private var components: [SharedMediaNativeInspectionComponent: ComponentSummary] = [:]
        var componentSummaries: [ComponentSummary] {
            SharedMediaNativeInspectionComponent.allCases.compactMap { components[$0] }
        }
        func measure<T>(_ component: SharedMediaNativeInspectionComponent, _ body: () throws -> T) rethrows -> T {
            let began = ContinuousClock.now
            defer {
                var value = components[component] ?? .init(component: component)
                if value.calls < 1_000_000 { value.calls += 1 } else { value.saturated = true }
                let duration = began.duration(to: .now), limit = Duration.seconds(86_400)
                if duration >= limit - value.elapsed { value.elapsed = limit; value.saturated = true } else { value.elapsed += duration }
                components[component] = value
            }
            return try body()
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

@MainActor
extension SharedMediaNativeAppDispatchGrant {
    /// Configure test observation/faults only; all authority checks remain in the audit.
    func configureInspection(_ audit: inout SharedMediaNativeScopedAudit) {
        #if DEBUG
        audit.inspectionTrace = debug.inspectionTrace
        audit.inspectionReadFault = debug.inspectionReadFault
        audit.inspectionPageFault = debug.inspectionPageFault
        #endif
    }

    /// Test-only capacity clamp supplied through the already registered grant.
    /// Release builds return real availability without an override or extra authority.
    func limitingAllocationAvailableBytes(_ actual: Int64) -> Int64 {
        #if DEBUG
        if let limit = debug.metadataAvailableBytes { return min(actual, limit) }
        #endif
        return actual
    }
}
