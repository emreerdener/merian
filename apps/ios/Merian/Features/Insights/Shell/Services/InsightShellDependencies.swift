import Combine
import SwiftData

struct InsightAuthenticationSnapshot: Equatable {
    let isAuthenticated: Bool
    let accountID: String?
}

@MainActor
struct InsightShellDependencies {
    let appEvents: AnyPublisher<AppEvent, Never>
    let authenticationSnapshot: @MainActor () -> InsightAuthenticationSnapshot
    let defaultAppSettings: @MainActor () -> AppSettings
    let loadFieldTripContributions: @MainActor (
        _ scanID: String
    ) async throws -> [FieldTripScanContribution]
    let isFieldTripsAvailable: @MainActor () -> Bool
    let isProActive: @MainActor () -> Bool
    let ensureCloudScanAvailableForFieldChat: @MainActor (
        _ scan: LocalScanRecord,
        _ expectedScanID: String
    ) async throws -> Bool
    let eradicateScan: @MainActor (
        _ record: LocalScanRecord,
        _ modelContext: ModelContext
    ) -> Void
    let enqueueCollectionSync: @MainActor () -> Void
    let requestRefinement: @MainActor (
        _ scanID: String,
        _ initialDescription: String?
    ) -> Void
    let requestCommunityIdentification: @MainActor (
        _ requestID: String
    ) -> Void
    let requestNonBiologicalScans: @MainActor () -> Void
    let updateAppIconBadge: @MainActor () -> Void
    let selectionFeedback: @MainActor () -> Void
    let successFeedback: @MainActor () -> Void
    let errorFeedback: @MainActor () -> Void
    let sheetFeedback: @MainActor () -> Void
    let completionFeedback: @MainActor () -> Void
    let audioBoostEnabledFeedback: @MainActor () -> Void
    let audioBoostDisabledFeedback: @MainActor () -> Void

    init(
        appEvents: AnyPublisher<AppEvent, Never> = Empty().eraseToAnyPublisher(),
        authenticationSnapshot: @escaping @MainActor () ->
            InsightAuthenticationSnapshot = {
                InsightAuthenticationSnapshot(
                    isAuthenticated: false,
                    accountID: nil
                )
            },
        defaultAppSettings: @escaping @MainActor () -> AppSettings = {
            AppSettings.shared
        },
        loadFieldTripContributions: @escaping @MainActor (
            _ scanID: String
        ) async throws -> [FieldTripScanContribution] = { _ in [] },
        isFieldTripsAvailable: @escaping @MainActor () -> Bool = { false },
        isProActive: @escaping @MainActor () -> Bool = { false },
        ensureCloudScanAvailableForFieldChat: @escaping @MainActor (
            _ scan: LocalScanRecord,
            _ expectedScanID: String
        ) async throws -> Bool = { _, _ in false },
        eradicateScan: @escaping @MainActor (
            _ record: LocalScanRecord,
            _ modelContext: ModelContext
        ) -> Void = { _, _ in },
        enqueueCollectionSync: @escaping @MainActor () -> Void = {},
        requestRefinement: @escaping @MainActor (
            _ scanID: String,
            _ initialDescription: String?
        ) -> Void = { _, _ in },
        requestCommunityIdentification: @escaping @MainActor (
            _ requestID: String
        ) -> Void = { _ in },
        requestNonBiologicalScans: @escaping @MainActor () -> Void = {},
        updateAppIconBadge: @escaping @MainActor () -> Void = {},
        selectionFeedback: @escaping @MainActor () -> Void = {},
        successFeedback: @escaping @MainActor () -> Void = {},
        errorFeedback: @escaping @MainActor () -> Void = {},
        sheetFeedback: @escaping @MainActor () -> Void = {},
        completionFeedback: @escaping @MainActor () -> Void = {},
        audioBoostEnabledFeedback: @escaping @MainActor () -> Void = {},
        audioBoostDisabledFeedback: @escaping @MainActor () -> Void = {}
    ) {
        self.appEvents = appEvents
        self.authenticationSnapshot = authenticationSnapshot
        self.defaultAppSettings = defaultAppSettings
        self.loadFieldTripContributions = loadFieldTripContributions
        self.isFieldTripsAvailable = isFieldTripsAvailable
        self.isProActive = isProActive
        self.ensureCloudScanAvailableForFieldChat =
            ensureCloudScanAvailableForFieldChat
        self.eradicateScan = eradicateScan
        self.enqueueCollectionSync = enqueueCollectionSync
        self.requestRefinement = requestRefinement
        self.requestCommunityIdentification =
            requestCommunityIdentification
        self.requestNonBiologicalScans = requestNonBiologicalScans
        self.updateAppIconBadge = updateAppIconBadge
        self.selectionFeedback = selectionFeedback
        self.successFeedback = successFeedback
        self.errorFeedback = errorFeedback
        self.sheetFeedback = sheetFeedback
        self.completionFeedback = completionFeedback
        self.audioBoostEnabledFeedback = audioBoostEnabledFeedback
        self.audioBoostDisabledFeedback = audioBoostDisabledFeedback
    }

    static var live: Self {
        let container = AppDIContainer.shared
        let hapticManager = container.hapticManager
        return Self(
            appEvents: container.appEventPublisher.publisher,
            authenticationSnapshot: {
                let manager = SupabaseManager.shared
                return InsightAuthenticationSnapshot(
                    isAuthenticated: manager.isAuthenticated,
                    accountID: manager.currentUser?.id.uuidString
                )
            },
            defaultAppSettings: { AppSettings.shared },
            loadFieldTripContributions: { scanID in
                try await MerianNetworkClient.shared
                    .getFieldTripScanContributions(scanId: scanID)
            },
            isFieldTripsAvailable: {
                FeatureFlags.isEnabled(.fieldTrips)
            },
            isProActive: { RevenueCatManager.shared.isProActive },
            ensureCloudScanAvailableForFieldChat: { scan, expectedScanID in
                try await MerianNetworkClient.shared
                    .ensureCloudScanAvailableForFieldChat(
                        scan: scan,
                        expectedScanId: expectedScanID
                    )
            },
            eradicateScan: { record, modelContext in
                ScanRepository.shared.eradicateScan(
                    record: record,
                    modelContext: modelContext
                )
            },
            enqueueCollectionSync: {
                OfflineQueueManager.shared.enqueueCollectionSync()
            },
            requestRefinement: { scanID, initialDescription in
                container.appRouteCoordinator.request(
                    .refinement(
                        scanId: scanID,
                        initialDescription: initialDescription,
                        entryPoint: .standard
                    ),
                    source: .internalUserAction
                )
            },
            requestCommunityIdentification: { requestID in
                container.appRouteCoordinator.request(
                    .communityIdentification(requestId: requestID),
                    source: .internalUserAction
                )
            },
            requestNonBiologicalScans: {
                container.appRouteCoordinator.request(
                    .nonBiologicalScans,
                    source: .internalUserAction
                )
            },
            updateAppIconBadge: {
                AppIconBadgeCoordinator.updateAppIconBadge()
            },
            selectionFeedback: {
                hapticManager.triggerSelectionPulse()
            },
            successFeedback: {
                hapticManager.triggerSuccessPulse()
            },
            errorFeedback: {
                hapticManager.triggerErrorThump()
            },
            sheetFeedback: {
                hapticManager.triggerSheetSpring()
            },
            completionFeedback: {
                hapticManager.triggerHeavyImpact(
                    source: "insight.analysis.completed"
                )
            },
            audioBoostEnabledFeedback: {
                hapticManager.triggerMediumPulse(
                    source: "media.insight.audioBoost.enabled"
                )
            },
            audioBoostDisabledFeedback: {
                hapticManager.triggerLightImpact(
                    intensity: 0.5,
                    source: "media.insight.audioBoost.disabled"
                )
            }
        )
    }
}
