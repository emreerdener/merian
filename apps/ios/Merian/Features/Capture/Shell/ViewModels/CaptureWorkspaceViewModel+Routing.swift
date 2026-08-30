import Foundation
import SwiftData

extension CaptureWorkspaceViewModel {
    // MARK: - External Route Timeout Protection

    private func protectExternalRouteFromImmediateSessionTimeoutReset() {
        operationState.protectExternalRoute(
            fromTimeoutUntil: Date().addingTimeInterval(5)
        )
    }

    // MARK: - Delivery-Critical Route Consumption

    func consumeNextAppRoute(
        now: Date = Date(),
        isFeaturePresentationOccupied: Bool = false
    ) {
        let coordinator = diContainer.appRouteCoordinator
        guard let request = coordinator.claimNext(now: now) else { return }

        if activePresentation != nil
            || operationState.isDismissingPresentation
            || isFeaturePresentationOccupied {
            operationState.deferRoute(requestID: request.id)
            coordinator.resolve(
                request.id,
                outcome: .deferred(reason: .presentationOccupied),
                now: now
            )
            dismissActivePresentation()
            return
        }

        operationState.beginApplyingRoute(requestID: request.id)
        let outcome = apply(request.route)
        operationState.finishApplyingRoute()
        coordinator.resolve(request.id, outcome: outcome, now: now)
    }

    private func apply(_ route: AppRoute) -> AppRouteOutcome {
        switch route {
        case .proAccessRequired:
            activeSheet = .paywall
        case .scan(let scanId):
            guard handleDeepLinkRoute(scanId: scanId) else {
                return .rejected(reason: .targetUnavailable)
            }
        case .explorePost(let postId, let targetCommentId, let targetReplyParentCommentId):
            guard !postId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .rejected(reason: .invalidPayload)
            }
            handleExploreDeepLinkRoute(
                postId: postId,
                targetCommentId: targetCommentId,
                targetReplyParentCommentId: targetReplyParentCommentId
            )
        case .speciesDictionary(let speciesId):
            guard handleSpeciesDictionaryDeepLinkRoute(speciesId: speciesId) else {
                return .rejected(reason: .invalidPayload)
            }
        case .communityIdentification(let requestId):
            guard !requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .rejected(reason: .invalidPayload)
            }
            handleCommunityIdentificationRoute(requestId: requestId)
        case .identifyNature, .openScanner:
            activeSheet = nil
            requestedCaptureMode = .visual
            if FeatureFlags.isEnabled(.fieldTrips) {
                let accountID = diContainer.supabaseManager.currentUser?.id.uuidString.lowercased()
                Task { [activeCaptureGoalStore = diContainer.activeCaptureGoalStore] in
                    await activeCaptureGoalStore.refresh(accountId: accountID, force: true)
                }
            }
        case .achievement(let award):
            pendingAchievementAward = award
            activeSheet = .achievement
        case .captureGoal(let destination):
            openCaptureGoal(destination)
        case .fieldTrips:
            openFieldTrips()
        case .recallLastFind:
            guard diContainer.inferenceEngine.historicHydrationTask != nil
                    || diContainer.inferenceEngine.speciesData != nil else {
                return .rejected(reason: .targetUnavailable)
            }
            activeSheet = .insight
        case .refinement(let scanId, let initialDescription, let entryPoint):
            guard startRefinementScan(
                scanId: scanId,
                initialDescription: initialDescription,
                entryPoint: entryPoint
            ) else {
                return .rejected(reason: .targetUnavailable)
            }
        case .nonBiologicalScans:
            handleScansLibraryRoute(showsNonBiologicalCollection: true)
        case .scansLibrary:
            handleScansLibraryRoute()
        case .scansLibraryRecovery(let context):
            let currentOwner = diContainer.supabaseManager.currentUser?.id.uuidString.lowercased()
            guard currentOwner == context.ownerUserId.lowercased() else {
                return .rejected(reason: .staleAccount)
            }
            handleScansLibraryRoute(recoveryContext: context)
        case .processExternalImageImports:
            protectExternalRouteFromImmediateSessionTimeoutReset()
            importPendingExternalImageIfPossible()
        case .externalImageImportFailed:
            prepareForExternalImageImportPresentation()
            presentExternalImageImportFailure()
        #if DEBUG
        case .debugPreviewAnalyzing:
            activeSheet = .insight
        #endif
        }

        let presentationID = activePresentation?.routeRequestID
            == operationState.applyingRouteRequestID
            ? activePresentation?.id
            : nil
        return .applied(presentationID: presentationID)
    }

    func handleRouteAccountGenerationChanged() {
        operationState.clearPendingRoutes()
        clearExplorePresentationRoute()
        pendingScansRecoveryContext = nil
        pendingScansShowsNonBiologicalCollection = false
        pendingAchievementAward = nil
        if activePresentation?.routeRequestID != nil {
            dismissActivePresentation()
        }
    }

    // MARK: - App Linking

    @discardableResult
    private func handleDeepLinkRoute(scanId: String) -> Bool {
        clearExplorePresentationRoute()

        // SwiftData Context Access boundary seamlessly leveraging the shared queue context
        guard let context = diContainer.offlineQueueManager.modelContext else { return false }

        do {
            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
            if let record = (try context.fetch(descriptor)).first {
                diContainer.inferenceEngine.load(from: record)
                protectExternalRouteFromImmediateSessionTimeoutReset()
                self.activeSheet = .insight
                return true
            }
        } catch {
            MerianLog.general.error("Failed to route to scanId \(scanId, privacy: .private): \(error, privacy: .private)")
        }
        return false
    }

    func fetchLocalScan(scanId: String) -> LocalScanRecord? {
        guard let context = diContainer.offlineQueueManager.modelContext else { return nil }
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func handleExploreDeepLinkRoute(
        postId: String,
        targetCommentId: String?,
        targetReplyParentCommentId: String?
    ) {
        protectExternalRouteFromImmediateSessionTimeoutReset()
        pendingExplorePostId = postId
        pendingSpeciesDictionaryRoute = nil
        pendingCommunityIdentificationRequestId = nil
        pendingExploreTargetCommentId = targetCommentId
        pendingExploreTargetReplyParentCommentId = targetReplyParentCommentId
        pendingCaptureGoalDestination = nil
        pendingExploreShowsFieldTrips = false
        explorePresentationIdentity = UUID()
        activeSheet = .explore
    }

    @discardableResult
    private func handleSpeciesDictionaryDeepLinkRoute(speciesId: String) -> Bool {
        guard let uuid = UUID(
            uuidString: speciesId.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            return false
        }
        let canonicalSpeciesId = uuid.uuidString.lowercased()

        protectExternalRouteFromImmediateSessionTimeoutReset()
        pendingExplorePostId = nil
        pendingSpeciesDictionaryRoute = SpeciesDictionaryRoute(
            scientificName: "",
            speciesId: canonicalSpeciesId,
            entryPoint: .deepLink
        )
        pendingCommunityIdentificationRequestId = nil
        pendingExploreTargetCommentId = nil
        pendingExploreTargetReplyParentCommentId = nil
        pendingCaptureGoalDestination = nil
        pendingExploreShowsFieldTrips = false
        explorePresentationIdentity = UUID()
        activeSheet = .explore
        return true
    }

    private func handleCommunityIdentificationRoute(requestId: String) {
        protectExternalRouteFromImmediateSessionTimeoutReset()
        pendingExplorePostId = nil
        pendingSpeciesDictionaryRoute = nil
        pendingCommunityIdentificationRequestId = requestId
        pendingExploreTargetCommentId = nil
        pendingExploreTargetReplyParentCommentId = nil
        pendingCaptureGoalDestination = nil
        pendingExploreShowsFieldTrips = false
        explorePresentationIdentity = UUID()
        activeSheet = .explore
    }

    private func handleScansLibraryRoute(
        recoveryContext: ExploreMediaRecoveryRouteContext? = nil,
        showsNonBiologicalCollection: Bool = false
    ) {
        protectExternalRouteFromImmediateSessionTimeoutReset()
        clearExplorePresentationRoute()
        pendingScansRecoveryContext = recoveryContext
        pendingScansShowsNonBiologicalCollection = showsNonBiologicalCollection
        activeSheet = .scans
    }

    func openCaptureGoal(_ goal: CaptureGoal) {
        openCaptureGoal(goal.destination)
    }

    func openCaptureGoal(_ destination: CaptureGoalDestination) {
        protectExternalRouteFromImmediateSessionTimeoutReset()
        pendingExplorePostId = nil
        pendingSpeciesDictionaryRoute = nil
        pendingCommunityIdentificationRequestId = nil
        pendingExploreTargetCommentId = nil
        pendingExploreTargetReplyParentCommentId = nil
        pendingCaptureGoalDestination = destination
        pendingExploreShowsFieldTrips = false
        explorePresentationIdentity = UUID()
        activeSheet = .explore
    }

    private func openFieldTrips() {
        protectExternalRouteFromImmediateSessionTimeoutReset()
        clearExplorePresentationRoute()
        pendingExploreShowsFieldTrips = true
        explorePresentationIdentity = UUID()
        activeSheet = .explore
    }

    func dismissActivePresentation() {
        guard let activePresentation else { return }
        operationState.beginDismissing(activePresentation)
        self.activePresentation = nil
    }

    func queueNotificationPromptAfterInsightDismissal() {
        operationState.queueLocalSheet(.notificationPrompt)
    }

    func handleRootSheetDismissed(now: Date = Date()) {
        if let dismissed = operationState.takeDismissedPresentation() {
            if dismissed.destination == .achievement {
                pendingAchievementAward = nil
            }
            if let requestID = dismissed.routeRequestID {
                diContainer.appRouteCoordinator.resolve(
                    requestID,
                    outcome: .dismissed(presentationID: dismissed.id),
                    now: now
                )
            }
        }

        if let deferredRouteRequestID = operationState
            .takeDeferredRouteRequestID() {
            diContainer.appRouteCoordinator.resumeDeferredRequest(deferredRouteRequestID)
        }

        if operationState.takeExternalImageImportResumeRequest() {
            importPendingExternalImageIfPossible()
        }

        if diContainer.appRouteCoordinator.nextRequestID == nil,
           activePresentation == nil,
           let pendingLocalSheet = operationState.takePendingLocalSheet() {
            activeSheet = pendingLocalSheet
        }
    }

    /// Called only by a feature-local sheet/cover's exact `onDismiss` callback.
    /// A deferred global route is requeued here, after UIKit has released the
    /// presentation slot, rather than after a guessed teardown delay.
    func handleFeaturePresentationDismissed() {
        guard let deferredRouteRequestID = operationState
            .takeDeferredRouteRequestID() else { return }
        diContainer.appRouteCoordinator.resumeDeferredRequest(deferredRouteRequestID)
    }

    @discardableResult
    func prepareForExternalImageImportPresentation() -> Bool {
        protectExternalRouteFromImmediateSessionTimeoutReset()
        clearExplorePresentationRoute()
        let didDismissSheet = activePresentation != nil
            || operationState.isDismissingPresentation
        activeSheet = nil
        return didDismissSheet
    }

    private func clearExplorePresentationRoute() {
        pendingExplorePostId = nil
        pendingSpeciesDictionaryRoute = nil
        pendingCommunityIdentificationRequestId = nil
        pendingExploreTargetCommentId = nil
        pendingExploreTargetReplyParentCommentId = nil
        pendingCaptureGoalDestination = nil
        pendingExploreShowsFieldTrips = false
    }

    private func presentExternalImageImportFailure() {
        offlineToastMessage = .error("Naturebook couldn’t import that photo.")
        Task { [importStore = dependencies.externalImageImports] in
            _ = await importStore.consumeTerminalFailure()
        }
    }

}
