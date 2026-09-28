#if DEBUG
import Foundation
import SwiftData

extension UITestSeedCoordinator {
    static var isOpenAIPermissionSeedEnabled: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-seedOpenAIPermissionFlow")
    }

    private static var openAIPermissionOwner: UUID? {
        UUID(uuidString: "00000000-0000-4000-8000-0000000000c2")
    }

    @MainActor
    static func seedOpenAIPermissionFunding(scan: OfflineQueuedScan, context: ModelContext) throws {
        guard isOpenAIPermissionSeedEnabled, let owner = openAIPermissionOwner else { return }
        let funding = ScanFundingReservation(
            accountId: owner, scanId: scan.id, source: .complimentaryPro
        )
        guard let metadata = OfflineScanJobMetadataContract.json(generation: nil, funding: funding) else {
            throw CocoaError(.coderInvalidValue)
        }
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scan.id),
            kind: .scanIngestion, subjectId: scan.id, status: .needsAttention,
            lastErrorCode: "ai_openai_consent_required", metadataJSON: metadata
        ))
    }

    /// Synthetic local evidence only. Test-mode synchronization and realtime are disabled.
    @MainActor
    static func openAIPermissionConsentManager() -> ConsentManager? {
        let suiteName = "merian.ui-tests.openai-permission"
        guard isOpenAIPermissionSeedEnabled,
            let owner = openAIPermissionOwner,
            let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        defaults.removePersistentDomain(forName: suiteName)
        let manager = ConsentManager(
            ledgerStore: UserDefaultsConsentLedgerStore(userDefaults: defaults),
            currentSDKUserIdProvider: { owner },
            analyticsPermissionApplier: { _, _ in },
            synchronizationOperation: { _, _ in }
        )
        manager.adoptCloudSession(owner)
        return manager
    }
}
#endif
