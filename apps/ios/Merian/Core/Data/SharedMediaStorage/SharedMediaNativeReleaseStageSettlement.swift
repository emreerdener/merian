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

/// Initial acknowledgement or explicit audited continuation authorizes one target.
/// Saved Progress and recovery alone cannot construct this owner-local right.
@MainActor
final class SharedMediaNativeReleasePairAdmission {
    let request: SharedMediaNativeReleaseStartRequest?
    let row: SharedMediaNativeReceivingIntentGraph.Row
    let progress: SharedMediaNativeReceivingReleaseValues.Progress
    let continuation: SharedMediaNativeReleaseContinuation?
    fileprivate var attempt: SharedMediaNativeReleasePairAttempt?
    fileprivate init(_ request: SharedMediaNativeReleaseStartRequest?,
                     row: SharedMediaNativeReceivingIntentGraph.Row,
                     progress: SharedMediaNativeReceivingReleaseValues.Progress,
                     continuation: SharedMediaNativeReleaseContinuation? = nil) {
        self.request = request; self.row = row; self.progress = progress; self.continuation = continuation
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
    private struct ContinuationRecord {
        let identity: SharedMediaNativeReleaseContinuation
        var admission: SharedMediaNativeReleasePairAdmission?
    }
    private var continuations: [String: ContinuationRecord] = [:]
    private var pairMayHandBack = false
    private(set) var pendingPairDisposal: SharedMediaNativeReleasePairRemovalCapability?
    private var readPairDisposal: (() async throws -> Void)?
    private(set) var pendingOriginalDisposition: SharedMediaNativeOriginalDispositionAttempt?
    private var readOriginalDisposition: (() throws -> SharedMediaNativeReceivingReleaseValues.Progress)?
    private(set) var pendingOriginalDisposal: SharedMediaNativeOriginalRemovalCapability?
    private var readOriginalDisposal: (() async throws -> Void)?
    private(set) var pendingTerminal: SharedMediaNativeReceivingTerminalAttempt?
    private var readTerminal: (() throws -> SharedMediaNativeReceivingTerminalRecovery.Saved)?
    private var hasContinuationRight: Bool { continuations.values.contains { $0.admission != nil } }
    var hasPending: Bool { hasPendingOperation || hasContinuationRight }
    private var hasPendingOperation: Bool { pendingTerminal != nil || request != nil || pairAttempt != nil || pendingPairDisposal != nil || pendingOriginalDisposition != nil || pendingOriginalDisposal != nil }
    private(set) var pairAttempt: SharedMediaNativeReleasePairAttempt?
    private var pendingStage: SharedMediaNativeReleaseStageAdmission?
    private(set) var startProgress: SharedMediaNativeReceivingReleaseValues.Progress?
    private var closed = false
    private var readSaved: (() throws -> Saved)?
    private(set) var request: Request?

    /// Only called after an actual new receive save and exact fresh readback.
    /// Receipt replay deliberately has no callback and cannot replenish a right.
    func received(_ row: Row, profile: SharedMediaNativeAppProfile) throws {
        guard !closed, !hasPendingOperation, !hasContinuationRight, fresh[row.id] == nil else { throw SharedMediaStorageFailure.closed }
        try row.requireNoReleaseStart()
        guard case .received = try SharedMediaNativeReceivingSlot.decode(row, profile: profile) else {
            throw SharedMediaStorageFailure.closed
        }
        fresh[row.id] = .init(row: row, profile: profile)
    }
    func issue(_ value: Request, row: Row) throws -> SharedMediaNativeReleaseStageAdmission {
        guard !closed, !hasPendingOperation, !hasContinuationRight, var entitlement = fresh[value.packageID],
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
        guard !closed, !hasPendingOperation, !hasContinuationRight, let entitlement = fresh[admission.request.packageID],
              entitlement.admission === admission, entitlement.row == admission.row, row == nil || row == entitlement.row,
              entitlement.profile == admission.request.profile else { throw SharedMediaStorageFailure.closed }
    }
    func begin(_ admission: SharedMediaNativeReleaseStageAdmission, readSaved: @escaping () throws -> Saved) throws {
        try validate(admission)
        fresh.removeValue(forKey: admission.request.packageID)
        request = admission.request; pendingStage = admission; self.readSaved = readSaved
    }
    func resolved(_ value: Request) throws {
        guard startProgress == nil, pairAttempt == nil, !hasPendingOperation || request == value else { throw SharedMediaStorageFailure.closed }
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
        guard !closed, !hasPendingOperation, !hasContinuationRight, let admission = starts[value.packageID], admission.request == value else {
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
    func issueContinuation(_ identity: SharedMediaNativeReleaseContinuation) throws {
        let packageID = identity.progress.plan.package.id
        guard !closed, !hasPendingOperation, identity.index > 0,
              identity.index == (try identity.progress.selectedIndex(.readyPair)),
              identity.bytes == (try identity.progress.encoded()), identity.row.id == packageID else { throw SharedMediaStorageFailure.closed }
        if let prior = continuations[identity.key] {
            guard prior.identity == identity, let admission = prior.admission,
                  pairs[packageID] === admission else { throw SharedMediaStorageFailure.closed }
            return
        }
        guard starts.isEmpty, pairs.isEmpty, !fresh.values.contains(where: { $0.admission != nil }) else {
            throw SharedMediaStorageFailure.closed
        }
        let admission = SharedMediaNativeReleasePairAdmission(nil, row: identity.row,
            progress: identity.progress, continuation: identity)
        continuations[identity.key] = .init(identity: identity, admission: admission)
        pairs[packageID] = admission
    }
    func abandonContinuation(_ progress: SharedMediaNativeReceivingReleaseValues.Progress) {
        guard let bytes = try? progress.encoded() else { return }
        let key = SharedMediaAcquisitionEncoding.digest(bytes)
        guard var prior = continuations[key] else { return }
        if let admission = prior.admission, pairs[progress.plan.package.id] === admission {
            pairs.removeValue(forKey: progress.plan.package.id)
        }
        prior.admission = nil; continuations[key] = prior
    }
    func validatePair(_ admission: SharedMediaNativeReleasePairAdmission,
                      attempt: SharedMediaNativeReleasePairAttempt?) throws {
        if let attempt, admission.continuation != nil, pairAttempt === attempt {
            guard !closed, request == admission.request, admission.attempt === attempt else { throw SharedMediaStorageFailure.closed }
        } else {
            guard try pairAdmission(admission.progress) === admission else { throw SharedMediaStorageFailure.closed }
        }
    }
    func pairAdmission(_ progress: SharedMediaNativeReceivingReleaseValues.Progress) throws -> SharedMediaNativeReleasePairAdmission {
        guard !closed, !hasPendingOperation, let admission = pairs[progress.plan.package.id],
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
        pairMayHandBack = admission.continuation != nil
        if let continuation = admission.continuation {
            guard var record = continuations[continuation.key], record.admission === admission else { throw SharedMediaStorageFailure.closed }
            record.admission = nil; continuations[continuation.key] = record
        }
        pairs.removeValue(forKey: attempt.before.plan.package.id)
        request = admission.request; pairAttempt = attempt; self.readSaved = readSaved
    }
    func resolvedPair(_ value: SharedMediaNativeReceivingReleaseValues.Progress) throws {
        guard pairAttempt?.after == value,
              request == nil || request?.releaseID == value.plan.releaseID else {
            throw SharedMediaStorageFailure.closed
        }
        pairAttempt = nil; pairMayHandBack = false; request = nil; readSaved = nil
    }
    /// Reads only the frozen attempt's exact saved before/after state. A
    /// continuation predecessor can settle uncertainty, never renew its right.
    func recoverPair(_ expected: SharedMediaNativeReceivingReleaseValues.Progress) throws -> SharedMediaNativeReceivingReleaseValues.Progress {
        guard !closed, let attempt = pairAttempt, let readSaved,
              expected == attempt.after || (pairMayHandBack && expected == attempt.before),
              case .releasing(let saved) = try readSaved(),
              saved == attempt.after || (pairMayHandBack && saved == attempt.before) else {
            throw SharedMediaStorageFailure.closed
        }
        try resolvedPair(attempt.after)
        return saved
    }
    func beginPairDisposal(_ capability: SharedMediaNativeReleasePairRemovalCapability,
                           read: @escaping () async throws -> Void) throws {
        guard !closed, pendingTerminal == nil, request == nil, pairAttempt == nil, !hasContinuationRight, pendingOriginalDisposition == nil, pendingOriginalDisposal == nil else { throw SharedMediaStorageFailure.closed }
        if let prior = pendingPairDisposal {
            try prior.requireSame(capability)
            prior.permit.revoke()
        }
        pendingPairDisposal = capability; readPairDisposal = read
    }
    func resolvedPairDisposal(_ before: SharedMediaNativeReceivingReleaseValues.Progress) throws {
        guard pendingPairDisposal?.before == before else { throw SharedMediaStorageFailure.closed }
        pendingPairDisposal?.permit.revoke(); pendingPairDisposal = nil; readPairDisposal = nil
    }
    func beginOriginalDisposition(_ attempt: SharedMediaNativeOriginalDispositionAttempt,
                                  read: @escaping () throws -> SharedMediaNativeReceivingReleaseValues.Progress) throws {
        guard !closed, !hasPendingOperation, !hasContinuationRight else { throw SharedMediaStorageFailure.closed }
        pendingOriginalDisposition = attempt; readOriginalDisposition = read
    }
    func resolvedOriginalDisposition(_ attempt: SharedMediaNativeOriginalDispositionAttempt) throws {
        guard pendingOriginalDisposition === attempt else { throw SharedMediaStorageFailure.closed }
        pendingOriginalDisposition = nil; readOriginalDisposition = nil
    }
    func beginOriginalDisposal(_ value: SharedMediaNativeOriginalRemovalCapability,
                               read: @escaping () async throws -> Void) throws {
        guard !closed, !hasPendingOperation, !hasContinuationRight else { throw SharedMediaStorageFailure.closed }
        pendingOriginalDisposal = value; readOriginalDisposal = read
    }
    func resolvedOriginalDisposal(_ value: SharedMediaNativeOriginalRemovalCapability) throws {
        guard pendingOriginalDisposal === value else { throw SharedMediaStorageFailure.closed }
        value.permit.revoke(); pendingOriginalDisposal = nil; readOriginalDisposal = nil
    }
    func beginTerminal(_ attempt: SharedMediaNativeReceivingTerminalAttempt,
                       read: @escaping () throws -> SharedMediaNativeReceivingTerminalRecovery.Saved) throws {
        guard !closed, !hasPending else { throw SharedMediaStorageFailure.closed }
        pendingTerminal = attempt; readTerminal = read
    }
    func resolvedTerminal(_ attempt: SharedMediaNativeReceivingTerminalAttempt) throws {
        guard pendingTerminal === attempt else { throw SharedMediaStorageFailure.closed }
        pendingTerminal = nil; readTerminal = nil
    }
    func closeAdmission() {
        closed = true; pendingPairDisposal?.permit.revoke(); pendingOriginalDisposal?.permit.revoke()
        for key in Array(continuations.keys) { continuations[key]?.admission = nil }
        fresh.removeAll(); starts.removeAll(); pairs.removeAll()
    }

    /// Called only after the owner's active work has terminated. Reacquire the
    /// original canonical locks; no save, authority minting, provider call or refund.
    func reconcileAfterTermination() async throws {
        if let pending = pendingTerminal {
            guard closed, let readTerminal else { throw SharedMediaStorageFailure.closed }
            let coordinator = ScanInferencePersistenceCoordinator.shared, plan = pending.before.plan
            let held = await coordinator.acquireAll(scanIds: [plan.queueID.uuidString, plan.observationID.uuidString])
            do {
                let saved = try readTerminal()
                guard saved == .before || saved == .after(pending.after) else { throw SharedMediaStorageFailure.closed }
                try resolvedTerminal(pending)
                await coordinator.releaseAll(scanIds: held)
            } catch { await coordinator.releaseAll(scanIds: held); throw error }
        }
        if let pending = pendingOriginalDisposal {
            guard closed, let readOriginalDisposal else { throw SharedMediaStorageFailure.closed }
            let coordinator = ScanInferencePersistenceCoordinator.shared, plan = pending.before.plan
            let held = await coordinator.acquireAll(scanIds: [plan.queueID.uuidString, plan.observationID.uuidString])
            do {
                try await readOriginalDisposal()
                try resolvedOriginalDisposal(pending)
                await coordinator.releaseAll(scanIds: held)
            } catch { await coordinator.releaseAll(scanIds: held); throw error }
        }
        if let pending = pendingPairDisposal {
            guard closed, let readPairDisposal else { throw SharedMediaStorageFailure.closed }
            let coordinator = ScanInferencePersistenceCoordinator.shared, plan = pending.before.plan
            let held = await coordinator.acquireAll(scanIds: [plan.queueID.uuidString, plan.observationID.uuidString])
            do {
                try await readPairDisposal()
                try resolvedPairDisposal(pending.before)
                await coordinator.releaseAll(scanIds: held)
            } catch { await coordinator.releaseAll(scanIds: held); throw error }
        }
        if let pending = pendingOriginalDisposition {
            guard closed, let readOriginalDisposition else { throw SharedMediaStorageFailure.closed }
            let coordinator = ScanInferencePersistenceCoordinator.shared, plan = pending.before.plan
            let held = await coordinator.acquireAll(scanIds: [plan.queueID.uuidString, plan.observationID.uuidString])
            do {
                let saved = try readOriginalDisposition()
                guard saved == pending.before || saved == pending.after else { throw SharedMediaStorageFailure.closed }
                // Old work has joined. Exact durable predecessor can be admitted
                // by a new registered owner; this closed owner mints no right.
                try resolvedOriginalDisposition(pending)
                await coordinator.releaseAll(scanIds: held)
            } catch { await coordinator.releaseAll(scanIds: held); throw error }
        }
        if let attempt = pairAttempt {
            guard closed, let readSaved else { throw SharedMediaStorageFailure.closed }
            let coordinator = ScanInferencePersistenceCoordinator.shared, plan = attempt.before.plan
            let held = await coordinator.acquireAll(scanIds: [plan.queueID.uuidString, plan.observationID.uuidString])
            do {
                try Task.checkCancellation()
                let saved = try readSaved()
                guard saved == .releasing(attempt.after) || (pairMayHandBack && saved == .releasing(attempt.before)) else {
                    throw SharedMediaStorageFailure.closed
                }
                try resolvedPair(attempt.after)
                await coordinator.releaseAll(scanIds: held)
            } catch { await coordinator.releaseAll(scanIds: held); throw error }
        }
        guard let request else { return }
        guard closed, let readSaved else { throw SharedMediaStorageFailure.closed }
        let coordinator = ScanInferencePersistenceCoordinator.shared
        let held = await coordinator.acquireAll(scanIds: [request.queueID.uuidString, request.observationID.uuidString])
        do {
            try Task.checkCancellation()
            let saved = try readSaved()
            if let progress = startProgress {
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
