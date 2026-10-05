import Foundation

extension OfflineQueueManager {
    func requestReanalysisStartupRecovery() {
        requestReanalysisErasureRecovery()
        requestReanalysisAdmissionRecovery()
    }

    func makeReanalysisAdmissionRuntime() -> ObservationReanalysisAdmissionRuntime {
        let preparation = reanalysisPreparationOwner
        return .init(preparation: preparation, dependencies: .init(scope: { [weak self] in
            guard let self, let context = self.modelContext, let owner = CloudDeletionAccountWork.currentAccountID else { return nil }
            return .init(ownerID: owner, container: context.container)
        }, consentGranted: {
            guard let owner = CloudDeletionAccountWork.currentAccountID else { return false }
            return AppSettings.shared.hasCompletedOnboarding && ConsentManager.shared.currentSessionUserId == owner &&
                ConsentManager.shared.hasCurrentRequiredConsent
        }, networkAllowed: { [weak self] in self?.allowsAutomaticNetworkWorkOnCurrentPath == true }, execute: {
            let executor = ObservationReanalysisAdmissionExecutor(files: .init(documents: .documentsDirectory), ownership: preparation)
            return try await executor.execute($0, container: $1, consentGranted: $2, canPreflight: $3, isCurrent: $4)
        }, didAdmit: { [weak self] in self?.requestReanalysisExecutionRecovery() }))
    }

    func requestReanalysisAdmissionRecovery(_ opportunity: ObservationReanalysisAdmissionRuntime.Opportunity = .automatic) {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        reanalysisAdmissionRuntime.request(opportunity)
    }
}
