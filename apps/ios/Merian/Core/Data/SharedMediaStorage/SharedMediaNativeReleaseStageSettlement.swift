import Foundation

/// Opaque, nonserializable and bound by object identity to one registered owner's
/// acknowledged receive. A copied descriptive request carries no fresh authority.
@MainActor
final class SharedMediaNativeReleaseStageAdmission {
    let request: SharedMediaNativeReleaseStartRequest
    fileprivate let row: SharedMediaNativeReceivingIntentGraph.Row
    fileprivate init(_ request: SharedMediaNativeReleaseStartRequest, row: SharedMediaNativeReceivingIntentGraph.Row) {
        self.request = request; self.row = row
    }
}

/// Exists only in the acknowledging owner's settlement state. Saved sidecars
/// and copied request values cannot construct or replenish this right.
@MainActor
final class SharedMediaNativeReleaseStartAdmission {
    let request: SharedMediaNativeReleaseStartRequest
    let row: SharedMediaNativeReceivingIntentGraph.Row
    fileprivate init(_ request: SharedMediaNativeReleaseStartRequest, row: SharedMediaNativeReceivingIntentGraph.Row) {
        self.request = request; self.row = row
    }
}

/// One normal start acknowledgement authorizes only its first retained target.
/// Saved Progress and recovery cannot construct this owner-local right.
@MainActor
final class SharedMediaNativeReleasePairAdmission {
    let request: SharedMediaNativeReleaseStartRequest
    let row: SharedMediaNativeReceivingIntentGraph.Row
    let progress: SharedMediaNativeReceivingReleaseValues.Progress
    fileprivate var attempt: SharedMediaNativeReleasePairAttempt?
    fileprivate init(_ request: SharedMediaNativeReleaseStartRequest,
                     row: SharedMediaNativeReceivingIntentGraph.Row,
                     progress: SharedMediaNativeReceivingReleaseValues.Progress) {
        self.request = request; self.row = row; self.progress = progress
    }
}

/// The owner retains uncertainty independently of each transient operation.
/// The saved recovery closure holds repository read fences, never dispatch grants.
@MainActor
final class SharedMediaNativeReleaseStageSettlement {
    typealias Request = SharedMediaNativeReleaseStartRequest
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    typealias Saved = SharedMediaNativeAppReleaseStageOperations.Saved
    private struct Entitlement {
        let row: Row
        let profile: SharedMediaNativeAppProfile
        var admission: SharedMediaNativeReleaseStageAdmission?
    }
    private var fresh: [UUID: Entitlement] = [:]
    private var starts: [UUID: SharedMediaNativeReleaseStartAdmission] = [:]
    private var pairs: [UUID: SharedMediaNativeReleasePairAdmission] = [:]
    private(set) var pairAttempt: SharedMediaNativeReleasePairAttempt?
    private var pendingStage: SharedMediaNativeReleaseStageAdmission?
    private(set) var startProgress: SharedMediaNativeReceivingReleaseValues.Progress?
    private var closed = false
    private var readSaved: (() throws -> Saved)?
    private(set) var request: Request?

    /// Only called after an actual new receive save and exact fresh readback.
    /// Receipt replay deliberately has no callback and cannot replenish a right.
    func received(_ row: Row, profile: SharedMediaNativeAppProfile) throws {
        guard !closed, request == nil, fresh[row.id] == nil else { throw SharedMediaStorageFailure.closed }
        try row.requireNoReleaseStart()
        guard case .received = try SharedMediaNativeReceivingSlot.decode(row, profile: profile) else {
            throw SharedMediaStorageFailure.closed
        }
        fresh[row.id] = .init(row: row, profile: profile)
    }
    func issue(_ value: Request, row: Row) throws -> SharedMediaNativeReleaseStageAdmission {
        guard !closed, request == nil, var entitlement = fresh[value.packageID],
              entitlement.row == row, entitlement.profile == value.profile else { throw SharedMediaStorageFailure.closed }
        if let admission = entitlement.admission {
            guard admission.request == value else { throw SharedMediaStorageFailure.closed }
            return admission
        }
        let admission = SharedMediaNativeReleaseStageAdmission(value, row: row)
        entitlement.admission = admission; fresh[value.packageID] = entitlement
        return admission
    }
    func validate(_ admission: SharedMediaNativeReleaseStageAdmission, row: Row? = nil) throws {
        guard !closed, request == nil, let entitlement = fresh[admission.request.packageID],
              entitlement.admission === admission, entitlement.row == admission.row, row == nil || row == entitlement.row,
              entitlement.profile == admission.request.profile else { throw SharedMediaStorageFailure.closed }
    }
    func begin(_ admission: SharedMediaNativeReleaseStageAdmission, readSaved: @escaping () throws -> Saved) throws {
        try validate(admission)
        fresh.removeValue(forKey: admission.request.packageID)
        request = admission.request; pendingStage = admission; self.readSaved = readSaved
    }
    func resolved(_ value: Request) throws {
        guard startProgress == nil, pairAttempt == nil, request == nil || request == value else { throw SharedMediaStorageFailure.closed }
        request = nil; pendingStage = nil; readSaved = nil
    }
    /// Only the uninterrupted normal stage success path calls this. No await
    /// separates exact readback/fences from this atomic ownership transition.
    func acknowledgedStage(_ admission: SharedMediaNativeReleaseStageAdmission, row: Row) throws {
        guard !closed, pendingStage === admission, request == admission.request,
              startProgress == nil, starts[row.id] == nil, row.id == admission.request.packageID,
              row.releaseStartData == (try admission.request.encoded()),
              row.releaseStartSHA256 == SharedMediaAcquisitionEncoding.digest(try admission.request.encoded()) else {
            throw SharedMediaStorageFailure.closed
        }
        starts[row.id] = .init(admission.request, row: row)
        request = nil; pendingStage = nil; readSaved = nil
    }
    func startAdmission(_ value: Request) throws -> SharedMediaNativeReleaseStartAdmission {
        guard !closed, request == nil, let admission = starts[value.packageID], admission.request == value else {
            throw SharedMediaStorageFailure.closed
        }
        return admission
    }
    func validateStart(_ admission: SharedMediaNativeReleaseStartAdmission, row: Row) throws {
        guard try startAdmission(admission.request) === admission, admission.row == row else {
            throw SharedMediaStorageFailure.closed
        }
    }
    func beginStart(_ admission: SharedMediaNativeReleaseStartAdmission,
                    progress: SharedMediaNativeReceivingReleaseValues.Progress, readSaved: @escaping () throws -> Saved) throws {
        try validateStart(admission, row: admission.row)
        guard progress.plan.releaseID == admission.request.releaseID,
              progress.plan.package.id == admission.request.packageID else { throw SharedMediaStorageFailure.closed }
        starts.removeValue(forKey: admission.request.packageID)
        request = admission.request; startProgress = progress; self.readSaved = readSaved
    }
    func resolvedStart(_ progress: SharedMediaNativeReceivingReleaseValues.Progress) throws {
        guard startProgress == progress, request?.releaseID == progress.plan.releaseID else {
            throw SharedMediaStorageFailure.closed
        }
        startProgress = nil; request = nil; readSaved = nil
    }
    /// Atomic pending-start -> unused pair right transition. Fault recovery never calls this.
    func acknowledgedStart(_ progress: SharedMediaNativeReceivingReleaseValues.Progress, row: Row) throws {
        guard !closed, let request, startProgress == progress, pairAttempt == nil,
              pairs[row.id] == nil, row.id == request.packageID,
              progress == (try .init(plan: progress.plan)), row.phase == "releasing",
              row.revision == (try progress.plan.releasingRevision), row.preparedData == nil,
              row.releaseStartData == nil, row.releaseStartSHA256 == nil,
              row.resultData == (try progress.encoded()),
              row.resultSHA256 == SharedMediaAcquisitionEncoding.digest(try progress.encoded()) else {
            throw SharedMediaStorageFailure.closed
        }
        pairs[row.id] = .init(request, row: row, progress: progress)
        startProgress = nil; self.request = nil; readSaved = nil
    }
    func pairAdmission(_ progress: SharedMediaNativeReceivingReleaseValues.Progress) throws -> SharedMediaNativeReleasePairAdmission {
        guard !closed, request == nil, let admission = pairs[progress.plan.package.id],
              admission.progress == progress else { throw SharedMediaStorageFailure.closed }
        return admission
    }
    func freezePair(_ value: SharedMediaNativeReleasePairAttempt,
                    admission: SharedMediaNativeReleasePairAdmission) throws -> SharedMediaNativeReleasePairAttempt {
        guard try pairAdmission(value.before) === admission, value.row == admission.row else {
            throw SharedMediaStorageFailure.closed
        }
        if let prior = admission.attempt {
            guard prior === value else { throw SharedMediaStorageFailure.closed }
            return prior
        }
        admission.attempt = value; return value
    }
    func frozenPair(_ admission: SharedMediaNativeReleasePairAdmission) throws -> SharedMediaNativeReleasePairAttempt? {
        guard try pairAdmission(admission.progress) === admission else { throw SharedMediaStorageFailure.closed }
        return admission.attempt
    }
    func beginPair(_ attempt: SharedMediaNativeReleasePairAttempt, readSaved: @escaping () throws -> Saved) throws {
        let admission = try pairAdmission(attempt.before)
        guard admission.attempt === attempt else { throw SharedMediaStorageFailure.closed }
        pairs.removeValue(forKey: attempt.before.plan.package.id)
        request = admission.request; pairAttempt = attempt; self.readSaved = readSaved
    }
    func resolvedPair(_ value: SharedMediaNativeReceivingReleaseValues.Progress) throws {
        guard pairAttempt?.after == value, request?.releaseID == value.plan.releaseID else {
            throw SharedMediaStorageFailure.closed
        }
        pairAttempt = nil; request = nil; readSaved = nil
    }
    func closeAdmission() { closed = true; fresh.removeAll(); starts.removeAll(); pairs.removeAll() }

    /// Called only after the owner's active work has terminated. Reacquire the
    /// original canonical locks; no save, authority minting, provider call or refund.
    func reconcileAfterTermination() async throws {
        guard let request else { return }
        guard closed, let readSaved else { throw SharedMediaStorageFailure.closed }
        let coordinator = ScanInferencePersistenceCoordinator.shared
        let held = await coordinator.acquireAll(scanIds: [request.queueID.uuidString, request.observationID.uuidString])
        do {
            try Task.checkCancellation()
            let saved = try readSaved()
            if let attempt = pairAttempt {
                guard saved == .releasing(attempt.after) else { throw SharedMediaStorageFailure.closed }
                try resolvedPair(attempt.after)
            } else if let progress = startProgress {
                guard saved == .releasing(progress) else { throw SharedMediaStorageFailure.closed }
                try resolvedStart(progress)
            } else {
                try resolved(request)
            }
            await coordinator.releaseAll(scanIds: held)
        } catch {
            await coordinator.releaseAll(scanIds: held)
            throw error
        }
    }
}
