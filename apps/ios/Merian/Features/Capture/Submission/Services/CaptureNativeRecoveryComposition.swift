import Foundation

extension CaptureNativeRecoveryModel {
    /// Construction is presentation-only. The existing AppDI lifetime owns
    /// admission and shutdown; each explicit read uses its retained owner.
    static func app(ownerID: UUID, diContainer: AppDIContainer) -> CaptureNativeRecoveryModel? {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified,
              diContainer.supabaseManager.currentUser?.id == ownerID,
              let container = diContainer.offlineQueueManager.modelContext?.container else { return nil }
        let manager = diContainer.supabaseManager
        let generation = manager.authSessionGeneration
        let current = {
            manager.currentUser?.id == ownerID && manager.authSessionGeneration == generation
                && diContainer.offlineQueueManager.modelContext?.container === container
                && !manager.libraryAccountRecoveryRequired && !manager.librarySignOutRecoveryPending
                && (manager.libraryTransferResult == .completed || manager.isGuestUser)
        }
        let transport = MerianNetworkClient.shared.nativeReceivedStatusTransport()
        let status = CaptureNativeRecoveryStatusAccess.app(isCurrent: current,
            owner: { try await diContainer.nativeMediaOwnerForFeature() },
            send: { scan, account, validate in try await transport.perform(scanID: scan, ownerID: account, validate: validate) })
        return .init(ownerID: ownerID, isCurrent: current, statusAccess: status,
            lifetime: { diContainer.nativeMediaLifetime }, initialRead: { candidate in
                guard current() else { throw SharedMediaStorageFailure.stale }
                if let recovery = try ObservationHistoryEnrollmentService.nativeRecoveryAdmission(candidate, container: container) {
                    return .init(prepared: recovery.prepared, phase: .enrollmentHeld, baseline: nil)
                }
                let owner = try await diContainer.nativeMediaOwnerForFeature()
                guard current() else { throw SharedMediaStorageFailure.stale }
                let state = try await owner.discoverAppInitialContinuation(candidate)
                guard current() else { throw SharedMediaStorageFailure.stale }
                return state
            }, initialCompletion: { candidate, validate in
                try await completeInitialHistory(candidate, diContainer: diContainer,
                    isPresentedCurrent: { current() && (try? validate()) != nil })
            }, initialPageRead: { kind, cursor in
                guard current() else { throw SharedMediaStorageFailure.stale }
                if kind == .enrollment {
                    return try ObservationHistoryEnrollmentService.nativeRecoveryPage(ownerID: ownerID, container: container, cursor: cursor)
                }
                let owner = try await diContainer.nativeMediaOwnerForFeature()
                guard current() else { throw SharedMediaStorageFailure.stale }
                let page = try await owner.appReceivingQuery(SharedMediaNativeReceivingQuery.initialHandoffPage(cursor))
                guard current() else { throw SharedMediaStorageFailure.stale }
                return page
            }, initialOpen: { association in
                try association.validate()
                guard current(), association.ownerID == ownerID else { throw SharedMediaStorageFailure.stale }
                diContainer.appRouteCoordinator.request(.scan(scanId: association.observationID.uuidString.lowercased()), source: .internalUserAction)
            }, originalRead: { candidate, index, validate in
                try validate()
                guard current() else { throw SharedMediaStorageFailure.stale }
                let owner = try await diContainer.nativeMediaOwnerForFeature()
                try validate()
                guard current(), let saved = try await owner.discoverAppInitialContinuation(candidate),
                      saved.phase == .pending else { throw SharedMediaStorageFailure.stale }
                let preview = try await owner.previewReceivedAppOriginal(saved.prepared, index: index)
                let check: @MainActor () async throws -> Void = {
                    try validate()
                    guard current(), let fresh = try await owner.discoverAppInitialContinuation(candidate),
                          fresh.phase == .pending, try fresh.prepared.encoded() == saved.prepared.encoded() else {
                        throw SharedMediaStorageFailure.stale
                    }
                    try await preview.validate()
                    try validate()
                    guard current() else { throw SharedMediaStorageFailure.stale }
                }
                try await check()
                return .init(image: preview.image, index: preview.index, count: preview.count, validate: check)
            }, discover: {
            guard current() else { throw SharedMediaStorageFailure.stale }
            let owner = try await diContainer.nativeMediaOwnerForFeature()
            guard current() else { throw SharedMediaStorageFailure.stale }
            return try await owner.discoverAppReceivedCandidates()
        })
    }
}

// Explicit result completion is separate from availability checking. Neither
// discovery nor checkStatus invokes this composition or creates an enrollment.
extension CaptureNativeRecoveryModel {
    static func completeInitialHistory(_ candidate: SharedMediaNativeReceivedCandidate, diContainer: AppDIContainer,
                                       isPresentedCurrent: @escaping @MainActor () -> Bool) async throws -> NativeHistoryAssociation? {
        let ownerID = candidate.profile.ownerID
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified,
              diContainer.supabaseManager.currentUser?.id == ownerID,
              let container = diContainer.offlineQueueManager.modelContext?.container else {
            throw SharedMediaStorageFailure.closed
        }
        let manager = diContainer.supabaseManager, generation = manager.authSessionGeneration
        let accountCurrent = {
            manager.currentUser?.id == ownerID && manager.authSessionGeneration == generation
                && diContainer.offlineQueueManager.modelContext?.container === container
                && !manager.libraryAccountRecoveryRequired && !manager.librarySignOutRecoveryPending
                && (manager.libraryTransferResult == .completed || manager.isGuestUser)
        }
        let current = { accountCurrent() && isPresentedCurrent() }
        try Task.checkCancellation()
        guard current() else { throw SharedMediaStorageFailure.stale }
        if let recovery = try ObservationHistoryEnrollmentService.nativeRecoveryAdmission(candidate, container: container) {
            _ = try await diContainer.offlineQueueManager.historyEnrollmentOwner.enroll(
                observation: recovery.intent.observationID, owner: ownerID, generation: generation, container: container,
                cloud: .live(manager: manager), recovery: recovery, isCurrent: accountCurrent)
            try Task.checkCancellation()
            guard current() else { throw SharedMediaStorageFailure.stale }
        }
        let owner = try await diContainer.nativeMediaOwnerForFeature()
        guard current() else { throw SharedMediaStorageFailure.stale }
        let transport = MerianNetworkClient.shared.nativeReceivedStatusTransport()
        return try await completeInitialHistory(candidate, owner: owner,
            isCurrent: current, readAdmission: { allocation, validate in
                try await transport.recoverAdmission(.saved(allocation), validate: validate)
            }, readCompletion: { admission, validate in
                try await transport.recoverCompletion(admission, validate: validate)
            }, enroll: { observation in
                _ = try await diContainer.offlineQueueManager.historyEnrollmentOwner.continueInitialHistory(
                    observation: observation, owner: ownerID, generation: generation, container: container,
                    cloud: .live(manager: manager), isCurrent: accountCurrent)
            })
    }

    /// Uses existing native/account and enrollment owners; no durable retry or
    /// alternate scheduler lives in this composition. Each call is explicit.
    static func completeInitialHistory(_ candidate: SharedMediaNativeReceivedCandidate, owner: SharedMediaNativeOriginalOwner,
                                       isCurrent: @escaping @MainActor () -> Bool,
                                       readAdmission: @escaping @MainActor (SharedMediaNativePhotoAllocation, @escaping NativeReceivedStatusTransport.Validator) async throws -> Data?,
                                       readCompletion: @escaping @MainActor (InitialCompletionDocuments.CpmAdmission, @escaping NativeReceivedStatusTransport.Validator) async throws -> InitialCompletionDocuments.CpmAcquisition?,
                                       enroll: @escaping @MainActor (UUID) async throws -> Void) async throws -> NativeHistoryAssociation? {
        let ownerID = candidate.profile.ownerID
        let check: NativeReceivedStatusTransport.Validator = {
            try Task.checkCancellation()
            guard isCurrent() else { throw SharedMediaStorageFailure.stale }
        }
        try check()
        guard var state = try await owner.discoverAppInitialContinuation(candidate) else {
            throw SharedMediaStorageFailure.closed
        }
        try check()
        let prepared = state.prepared
        guard prepared.profile.ownerID == ownerID else { throw SharedMediaStorageFailure.stale }
        let originalReader: @MainActor (InitialCompletionDocuments.CpmAdmission, @escaping NativeReceivedStatusTransport.Validator) async throws -> InitialCompletionDocuments.CpmAcquisition? = { admission, validate in
            let current: NativeReceivedStatusTransport.Validator = { try check(); try validate() }
            try current()
            let result = try await readCompletion(admission, current)
            try current(); return result
        }
        if state.phase == .pending {
            guard try await owner.recoverAppInitialAdmission(prepared, readOriginal: { allocation, validate in
                let current: NativeReceivedStatusTransport.Validator = { try check(); try validate() }
                try current()
                let result = try await readAdmission(allocation, current)
                try current(); return result
            }) != nil else { try check(); return nil }
            try check()
            guard try await owner.recoverAppInitialCompletion(prepared, readOriginal: originalReader) != nil else {
                try check(); return nil
            }
            try check()
            guard try await owner.applyAppInitialResult(prepared, readOriginal: originalReader) != nil else {
                try check(); return nil
            }
            try check()
            guard let applied = try await owner.discoverAppInitialContinuation(candidate),
                  try applied.prepared.encoded() == prepared.encoded(), applied.phase != .pending else { throw SharedMediaStorageFailure.stale }
            state = applied; try check()
        }
        if state.phase == .acknowledged {
            guard let baseline = state.baseline else { throw SharedMediaStorageFailure.conflict }
            return baseline
        }
        if state.baseline == nil {
            // Explicit continuation selects existing-association recovery for
            // enrolled parents; it never infers or recreates their baseline.
            try check(); try await enroll(prepared.observationID); try check()
        }
        guard let acknowledged = try await owner.acknowledgeAppInitialHistory(prepared, readOriginal: originalReader) else {
            try check(); return nil
        }
        try check()
        guard acknowledged.format == .history, let baseline = acknowledged.historyBaseline,
              baseline.ownerID == ownerID, baseline.observationID == prepared.observationID else {
            throw SharedMediaStorageFailure.conflict
        }
        return baseline
    }
}

/// The model owns visibility; this access retains the original native save
/// attempts. The existing native owner alone publishes one-way live intervals.
@MainActor
final class CaptureNativeRecoveryStatusAccess {
    struct Interval {
        let allowance: Duration
        let settle: (Duration) async throws -> Bool
    }
    let reserve: (SharedMediaNativeReceivedCandidate) async throws -> Interval?
    let check: (SharedMediaNativeReceivedCandidate) async throws -> Bool
    private init(reserve: @escaping (SharedMediaNativeReceivedCandidate) async throws -> Interval?,
                 check: @escaping (SharedMediaNativeReceivedCandidate) async throws -> Bool) {
        self.reserve = reserve; self.check = check
    }

    static func app(isCurrent: @escaping @MainActor () -> Bool,
                    owner: @escaping @MainActor () async throws -> SharedMediaNativeOriginalOwner,
                    send: @escaping NativeReceivedStatusTransport.Send) -> CaptureNativeRecoveryStatusAccess {
        var retainedOwner: SharedMediaNativeOriginalOwner?
        return .init(reserve: { candidate in
            guard isCurrent() else { throw SharedMediaStorageFailure.stale }
            let currentOwner = try await owner()
            guard isCurrent() else { throw SharedMediaStorageFailure.stale }
            retainedOwner = currentOwner
            guard let interval = try await currentOwner.prepareAppRecoveryInterval(candidate) else { return nil }
            // Always deliver a late interval to the model's retained cleanup.
            // Throwing on a presentation fence here would strand its live lease.
            return Interval(allowance: interval.allowance, settle: { elapsed in
                let result = try await interval.settle(elapsed: elapsed)
                return result.acknowledged
            })
        }, check: { candidate in
            guard isCurrent(), let retainedOwner else { throw SharedMediaStorageFailure.stale }
            return try await retainedOwner.checkAppReceivedStatus(candidate) { scan, account, validate in
                let current: NativeReceivedStatusTransport.Validator = {
                    try validate()
                    guard isCurrent() else { throw SharedMediaStorageFailure.stale }
                }
                try current()
                let result = try await send(scan, account, current)
                try current(); return result
            }
        })
    }

    #if DEBUG
    /// Actual native transactions still require a disposable XCTest store.
    /// Failed/uncertain attempts remain retained; reconciliation never upgrades
    /// their original acknowledgement or creates another continuation.
    static func fixture(owner: SharedMediaNativeOriginalOwner,
                        didAcknowledge: @escaping () async -> Void = {},
                        send: @escaping NativeReceivedStatusTransport.Send) -> CaptureNativeRecoveryStatusAccess {
        var candidate: SharedMediaNativeReceivedCandidate?
        var attempt: SharedMediaNativeRecoveryPresentationAttempt?
        var blocked = false
        return .init(reserve: { selected in
            guard candidate == nil || candidate == selected else { throw SharedMediaStorageFailure.stale }
            candidate = selected
            guard !blocked else { return nil }
            blocked = true
            let reserved: SharedMediaNativeRecoveryPresentationAttempt
            if let previous = attempt {
                reserved = try await owner.reserveAgainAppRecoveryPresentationForTesting(previous)
            } else {
                reserved = try await owner.reserveAppRecoveryPresentationForTesting(selected)
            }
            attempt = reserved
            guard let allowance = reserved.visibleAllowance else { return nil }
            // Test-only scheduling boundary after actual durable acknowledgement.
            // Suspension grants no authority and does not bypass native settlement.
            await didAcknowledge()
            return Interval(allowance: allowance, settle: { elapsed in
                let settled = try await owner.settleAppRecoveryPresentationForTesting(reserved, elapsed: elapsed)
                attempt = settled
                blocked = !settled.acknowledged || settled.presentation.needsAttention
                return settled.acknowledged
            })
        }, check: { try await owner.checkAppReceivedStatus($0, send: send) })
    }
    #endif
}
