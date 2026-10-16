import CoreLocation

struct CaptureSubmissionContextDependencies {
    let lastKnownLocation: @MainActor @Sendable () -> CLLocation?
    let fetchDeferredContext: @MainActor @Sendable (
        _ lockedLocation: CLLocation?
    ) async -> EnvironmentContext
}

struct CaptureSubmissionAdmissionDependencies {
    let isOnline: @MainActor @Sendable () -> Bool
    let canStartLocally: @MainActor @Sendable (
        _ flashFallbackEligible: Bool
    ) -> Bool
    let preview: @MainActor @Sendable (
        _ flashFallbackEligible: Bool
    ) async -> ScanAdmissionPreviewResult
    var accountID: @MainActor @Sendable () -> UUID? = { nil }
    var isLibraryAccessBlocked: @MainActor @Sendable () -> Bool = { false }
}

struct CaptureSubmissionDependencies {
    let context: CaptureSubmissionContextDependencies
    let admission: CaptureSubmissionAdmissionDependencies
    let deferredContext: CaptureSubmissionDeferredContextService

    @MainActor
    static func live(diContainer: AppDIContainer) -> Self {
        Self(
            context: CaptureSubmissionContextDependencies(
                lastKnownLocation: {
                    diContainer.environmentContextManager.lastKnownLocation
                },
                fetchDeferredContext: { lockedLocation in
                    await diContainer.environmentContextManager
                        .fetchDeferredContext(
                            preLockedLocation: lockedLocation
                        )
                }
            ),
            admission: CaptureSubmissionAdmissionDependencies(
                isOnline: {
                    diContainer.offlineQueueManager.isOnline
                },
                canStartLocally: { flashFallbackEligible in
                    if flashFallbackEligible {
                        return diContainer.usageManager.canPerformScan(
                            isProActive:
                                diContainer.revenueCatManager.canStartProScan
                        )
                    }
                    return diContainer.revenueCatManager.canStartProScan
                },
                preview: { flashFallbackEligible in
                    await diContainer.scanAdmissionManager.preview(
                        flashFallbackEligible: flashFallbackEligible
                    )
                },
                accountID: {
                    let manager = diContainer.supabaseManager
                    _ = manager.authSessionGeneration
                    // Retain a draft through transient refresh of the same cached
                    // identity. This is local ownership, never request authority.
                    return manager.currentUser?.id ?? manager.client.auth.currentSession?.user.id
                },
                isLibraryAccessBlocked: {
                    let manager = diContainer.supabaseManager
                    return manager.libraryAccountRecoveryRequired
                        || manager.librarySignOutRecoveryPending
                        || (manager.libraryTransferResult != .completed && !manager.isGuestUser)
                }
            ),
            deferredContext: .live(
                offlineQueueManager: diContainer.offlineQueueManager
            )
        )
    }
}
