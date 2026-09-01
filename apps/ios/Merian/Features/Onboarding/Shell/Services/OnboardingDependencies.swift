import Foundation

@MainActor
struct OnboardingDependencies {
    let hasCompletedOnboarding: @MainActor () -> Bool
    let setHasCompletedOnboarding: @MainActor (_ isCompleted: Bool) -> Void
    let hasCurrentRequiredConsent: @MainActor () -> Bool
    let recordCurrentConsent: @MainActor (
        _ analyticsEnabled: Bool
    ) throws -> Void
    let currentSessionUserID: @MainActor () -> UUID?
    let trackCompletion: @MainActor () -> Void
    let resumeConsentBlockedScan: @MainActor (_ accountID: UUID) -> Void
    let isAmbientAnimationEnabled: @MainActor () -> Bool

    init(
        hasCompletedOnboarding: @escaping @MainActor () -> Bool = { false },
        setHasCompletedOnboarding: @escaping @MainActor (
            _ isCompleted: Bool
        ) -> Void = { _ in },
        hasCurrentRequiredConsent: @escaping @MainActor () -> Bool = {
            false
        },
        recordCurrentConsent: @escaping @MainActor (
            _ analyticsEnabled: Bool
        ) throws -> Void = { _ in },
        currentSessionUserID: @escaping @MainActor () -> UUID? = { nil },
        trackCompletion: @escaping @MainActor () -> Void = {},
        resumeConsentBlockedScan: @escaping @MainActor (
            _ accountID: UUID
        ) -> Void = { _ in },
        isAmbientAnimationEnabled: @escaping @MainActor () -> Bool = {
            true
        }
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.setHasCompletedOnboarding = setHasCompletedOnboarding
        self.hasCurrentRequiredConsent = hasCurrentRequiredConsent
        self.recordCurrentConsent = recordCurrentConsent
        self.currentSessionUserID = currentSessionUserID
        self.trackCompletion = trackCompletion
        self.resumeConsentBlockedScan = resumeConsentBlockedScan
        self.isAmbientAnimationEnabled = isAmbientAnimationEnabled
    }

    static func live(
        appSettings: AppSettings? = nil,
        consentManager: ConsentManager? = nil,
        offlineQueueManager: OfflineQueueManager? = nil,
        hardwareOrchestrator: HardwareOrchestrator? = nil,
        resumeConsentBlockedScan: ((UUID) -> String?)? = nil
    ) -> Self {
        let resolvedAppSettings = appSettings ?? AppSettings.shared
        let resolvedConsentManager = consentManager ?? ConsentManager.shared
        let resolvedOfflineQueueManager =
            offlineQueueManager ?? OfflineQueueManager.shared
        let resolvedHardwareOrchestrator =
            hardwareOrchestrator ?? HardwareOrchestrator.shared

        return Self(
            hasCompletedOnboarding: {
                resolvedAppSettings.hasCompletedOnboarding
            },
            setHasCompletedOnboarding: { isCompleted in
                resolvedAppSettings.hasCompletedOnboarding = isCompleted
            },
            hasCurrentRequiredConsent: {
                resolvedConsentManager.hasCurrentRequiredConsent
            },
            recordCurrentConsent: { analyticsEnabled in
                try resolvedConsentManager
                    .confirmAdultAndAcceptCurrentTermsAndGrantGemini(
                        analyticsEnabled: analyticsEnabled
                    )
            },
            currentSessionUserID: {
                resolvedConsentManager.currentSessionUserId
            },
            trackCompletion: {
                AppTelemetry.trackOnboardingCompleted()
            },
            resumeConsentBlockedScan: { accountID in
                if let resumeConsentBlockedScan {
                    _ = resumeConsentBlockedScan(accountID)
                } else {
                    _ = resolvedOfflineQueueManager
                        .resumeMostRecentConsentBlockedScan(
                            accountId: accountID
                        )
                }
            },
            isAmbientAnimationEnabled: {
                resolvedHardwareOrchestrator.isAnimationEnabled
            }
        )
    }
}
