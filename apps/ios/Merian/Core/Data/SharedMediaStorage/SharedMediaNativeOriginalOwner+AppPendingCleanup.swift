import Foundation

@MainActor
extension SharedMediaNativeOriginalOwner {
    /// Explicit user abandonment; never closes an active or unsettled writer.
    func abandonAppOriginal(_ request: SharedMediaAcquisitionIntent) async throws {
        try await appPendingWorkflow { try await $0.abandon(request) }
    }
    /// Cold recovery consumes only saved abandonment records, one fresh audited
    /// operation at a time. Raw held reservations remain available for remediation.
    func recoverAppPendingAbandonments() async throws {
        while try await appPendingWorkflow({ try await $0.recoverOne() }) { try Task.checkCancellation() }
    }
    #if DEBUG
    func setAppPendingReleaseFault(_ fault: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)?) async throws {
        try await appPendingWorkflow { try await $0.setReleaseFault(fault) }
    }
    #endif
}
