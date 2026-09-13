import Foundation

@MainActor
extension InferenceLiveCompletionCoordinator.Dependencies {
    /// Fallback composition for direct engine construction. Dependencies are
    /// resolved lazily so initializing `AppDIContainer.shared` cannot recurse.
    static let live = make(
        gamificationManager: { GamificationManager.shared },
        scanRepository: { ScanRepository.shared },
        circuitBreakerManager: { CircuitBreakerManager.shared },
        revenueCatManager: { RevenueCatManager.shared },
        appSettings: { AppSettings.shared },
        pushNotificationManager: { PushNotificationManager.shared },
        eventSender: { AppDIContainer.shared.appEventPublisher },
        milestoneCoordinator: {
            AppDIContainer.shared.scanMilestoneCoordinator
        }
    )

    /// Production composition used by `AppDIContainer`. Concrete collaborators
    /// are captured once instead of being rediscovered by `InferenceEngine`.
    static func composed(
        gamificationManager: GamificationManager,
        scanRepository: ScanRepository,
        circuitBreakerManager: CircuitBreakerManager,
        revenueCatManager: RevenueCatManager,
        appSettings: AppSettings,
        pushNotificationManager: PushNotificationManager,
        eventSender: any AppEventSending,
        milestoneCoordinator: ScanMilestoneCoordinator
    ) -> Self {
        make(
            gamificationManager: { gamificationManager },
            scanRepository: { scanRepository },
            circuitBreakerManager: { circuitBreakerManager },
            revenueCatManager: { revenueCatManager },
            appSettings: { appSettings },
            pushNotificationManager: { pushNotificationManager },
            eventSender: { eventSender },
            milestoneCoordinator: { milestoneCoordinator }
        )
    }

    private static func make(
        gamificationManager: @escaping @MainActor () -> GamificationManager,
        scanRepository: @escaping @MainActor () -> ScanRepository,
        circuitBreakerManager:
            @escaping @MainActor () -> CircuitBreakerManager,
        revenueCatManager: @escaping @MainActor () -> RevenueCatManager,
        appSettings: @escaping @MainActor () -> AppSettings,
        pushNotificationManager:
            @escaping @MainActor () -> PushNotificationManager,
        eventSender: @escaping @MainActor () -> any AppEventSending,
        milestoneCoordinator:
            @escaping @MainActor () -> ScanMilestoneCoordinator
    ) -> Self {
        Self(
            recordNewSpeciesDiscovered: {
                gamificationManager().recordNewSpeciesDiscovered()
            },
            transferReplacementMetadataAndDeleteOriginal: { originalScanId, outcome, modelContext in
                guard let modelContext,
                      let originalRecord =
                          InferenceScanReplacement.transferMetadata(
                              from: originalScanId,
                              after: outcome,
                              modelContext: modelContext
                          ) else { return }
                scanRepository().eradicateScan(
                    record: originalRecord,
                    modelContext: modelContext
                )
            },
            recordCircuitSuccess: {
                circuitBreakerManager().recordSuccess()
            },
            trackCompletedScan: { inferenceTier, planUsed in
                let revenueCatManager = revenueCatManager()
                AppTelemetry.trackScan(
                    isPro: revenueCatManager.isProActive,
                    isSubscribed: revenueCatManager.isSubscribed,
                    inferenceTier: inferenceTier,
                    planUsed: planUsed
                )
            },
            sendEvent: { event in
                eventSender().send(event)
            },
            notificationsEnabled: {
                appSettings().isPushNotificationsEnabled
            },
            sendInferenceCompleteNotification: { speciesName, scanId in
                pushNotificationManager()
                    .sendInferenceCompleteNotification(
                        speciesName: speciesName,
                        scanId: scanId
                    )
            },
            scheduleMilestoneProcessing: { scanId, speciesData, modelContainer in
                let coordinator = milestoneCoordinator()
                Task { @MainActor in
                    await coordinator.processCompletedScan(
                        scanId: scanId,
                        speciesData: speciesData,
                        modelContainer: modelContainer
                    )
                }
            }
        )
    }
}
