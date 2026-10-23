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
        request = admission.request; self.readSaved = readSaved
    }
    func resolved(_ value: Request) throws {
        guard request == nil || request == value else { throw SharedMediaStorageFailure.closed }
        request = nil; readSaved = nil
    }
    func closeAdmission() { closed = true; fresh.removeAll() }

    /// Called only after the owner's active work has terminated. Reacquire the
    /// original canonical locks; no save, authority minting, provider call or refund.
    func reconcileAfterTermination() async throws {
        guard let request else { return }
        guard closed, let readSaved else { throw SharedMediaStorageFailure.closed }
        let coordinator = ScanInferencePersistenceCoordinator.shared
        let held = await coordinator.acquireAll(scanIds: [request.queueID.uuidString, request.observationID.uuidString])
        do {
            try Task.checkCancellation()
            _ = try readSaved()
            try resolved(request)
            await coordinator.releaseAll(scanIds: held)
        } catch {
            await coordinator.releaseAll(scanIds: held)
            throw error
        }
    }
}
