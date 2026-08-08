import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("App Route Coordinator")
struct AppRouteCoordinatorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func routesAreClaimedByPriorityThenFIFO() throws {
        let coordinator = AppRouteCoordinator()
        let genericID = UUID()
        let internalID = UUID()
        let explicitID = UUID()
        let durableID = UUID()

        coordinator.request(.fieldTrips, source: .genericLaunch, id: genericID, now: now)
        coordinator.request(.nonBiologicalScans, source: .internalUserAction, id: internalID, now: now)
        coordinator.request(.scan(scanId: "scan-1"), source: .pushNotification, id: explicitID, now: now)
        coordinator.request(
            .processExternalImageImports,
            source: .durableExternalImport,
            id: durableID,
            now: now
        )

        let expectedOrder = [durableID, explicitID, internalID, genericID]
        var claimedOrder: [UUID] = []
        for _ in expectedOrder {
            let request = try #require(coordinator.claimNext(now: now))
            claimedOrder.append(request.id)
            coordinator.resolve(request.id, outcome: .applied(presentationID: nil), now: now)
        }

        #expect(claimedOrder == expectedOrder)
        #expect(coordinator.claimNext(now: now) == nil)
    }

    @Test func equalPriorityAndTimestampPreserveInsertionOrder() throws {
        let coordinator = AppRouteCoordinator()
        let firstID = UUID()
        let secondID = UUID()

        coordinator.request(.fieldTrips, source: .internalUserAction, id: firstID, now: now)
        coordinator.request(.scansLibrary, source: .internalUserAction, id: secondID, now: now)

        let first = try #require(coordinator.claimNext(now: now))
        #expect(first.id == firstID)
        coordinator.resolve(first.id, outcome: .applied(presentationID: nil), now: now)
        #expect(coordinator.claimNext(now: now)?.id == secondID)
    }

    @Test func semanticDuplicatesCoalesceIntoExistingRequest() {
        let coordinator = AppRouteCoordinator()
        let existingID = UUID()
        let duplicateID = UUID()

        coordinator.request(.identifyNature, source: .appIntent, id: existingID, now: now)
        coordinator.request(.openScanner, source: .internalUserAction, id: duplicateID, now: now)

        #expect(coordinator.pendingRequests.map(\.id) == [existingID])
        #expect(
            coordinator.recentOutcomes.last?.outcome
                == .rejected(reason: .coalesced(into: existingID))
        )
        #expect(coordinator.recentOutcomes.last?.requestID == duplicateID)
    }

    @Test func strongerDuplicatePromotesExistingRequestWithoutChangingItsIdentity() throws {
        let coordinator = AppRouteCoordinator()
        let genericID = UUID()
        let pushID = UUID()

        coordinator.request(.scansLibrary, source: .genericLaunch, id: genericID, now: now)
        coordinator.request(
            .scansLibrary,
            source: .pushNotification,
            id: pushID,
            now: now.addingTimeInterval(1)
        )

        let request = try #require(coordinator.claimNext(now: now.addingTimeInterval(1)))
        #expect(request.id == genericID)
        #expect(request.source == .pushNotification)
        #expect(request.priority == .explicitExternal)
        #expect(request.expiresAt == now.addingTimeInterval(301))
        #expect(
            coordinator.recentOutcomes.last?.outcome
                == .rejected(reason: .coalesced(into: genericID))
        )
        #expect(coordinator.recentOutcomes.last?.requestID == pushID)
    }

    @Test func pendingDuplicateKeepsStableIdentityAndLatestLightweightPayload() throws {
        let coordinator = AppRouteCoordinator()
        let existingID = UUID()
        let duplicateID = UUID()
        coordinator.request(
            .refinement(
                scanId: "scan-1",
                initialDescription: "first draft",
                entryPoint: .standard
            ),
            source: .internalUserAction,
            id: existingID,
            now: now
        )
        coordinator.request(
            .refinement(
                scanId: "SCAN-1",
                initialDescription: "latest draft",
                entryPoint: .standard
            ),
            source: .internalUserAction,
            id: duplicateID,
            now: now.addingTimeInterval(1)
        )

        let request = try #require(coordinator.claimNext(now: now.addingTimeInterval(1)))
        #expect(request.id == existingID)
        guard case .refinement(_, let initialDescription, .standard) = request.route else {
            Issue.record("Expected the coalesced refinement route")
            return
        }
        #expect(initialDescription == "latest draft")
        #expect(coordinator.recentOutcomes.last?.requestID == duplicateID)
        #expect(
            coordinator.recentOutcomes.last?.outcome
                == .rejected(reason: .coalesced(into: existingID))
        )
    }

    @Test func strongerDuplicatePromotesInFlightPresentationAndPreservesTimeoutSuppression() throws {
        let coordinator = AppRouteCoordinator()
        let requestID = UUID()
        let presentationID = UUID()
        coordinator.request(.scansLibrary, source: .genericLaunch, id: requestID, now: now)
        let request = try #require(coordinator.claimNext(now: now))
        coordinator.resolve(
            request.id,
            outcome: .applied(presentationID: presentationID),
            now: now
        )

        coordinator.request(
            .scansLibrary,
            source: .deepLink,
            id: UUID(),
            now: now.addingTimeInterval(1)
        )

        #expect(coordinator.inFlightRequest?.id == requestID)
        #expect(coordinator.inFlightRequest?.source == .deepLink)
        #expect(coordinator.shouldSuppressTimeoutReset(now: now.addingTimeInterval(1)))
    }

    @Test func boundedQueueEvictsOldestEligibleLowerPriorityRequest() {
        let coordinator = AppRouteCoordinator(maximumPendingCount: 2)
        let lowID = UUID()
        let mediumID = UUID()
        let highID = UUID()
        let rejectedLowID = UUID()

        coordinator.request(.fieldTrips, source: .genericLaunch, id: lowID, now: now)
        coordinator.request(.nonBiologicalScans, source: .internalUserAction, id: mediumID, now: now)
        coordinator.request(
            .processExternalImageImports,
            source: .durableExternalImport,
            id: highID,
            now: now
        )

        #expect(coordinator.pendingRequests.map(\.id) == [highID, mediumID])
        #expect(coordinator.recentOutcomes.contains {
            $0.requestID == lowID && $0.outcome == .rejected(reason: .overflow)
        })

        coordinator.request(.scansLibrary, source: .genericLaunch, id: rejectedLowID, now: now)
        #expect(coordinator.pendingRequests.map(\.id) == [highID, mediumID])
        #expect(coordinator.recentOutcomes.last?.requestID == rejectedLowID)
        #expect(coordinator.recentOutcomes.last?.outcome == .rejected(reason: .overflow))
    }

    @Test func expiredRoutesAreRejectedBeforeClaim() {
        let coordinator = AppRouteCoordinator()
        let requestID = UUID()
        coordinator.request(.fieldTrips, source: .internalUserAction, id: requestID, now: now)

        #expect(coordinator.claimNext(now: now.addingTimeInterval(31)) == nil)
        #expect(coordinator.recentOutcomes.last?.requestID == requestID)
        #expect(coordinator.recentOutcomes.last?.outcome == .rejected(reason: .expired))
    }

    @Test func expiryDoesNotInvalidateAnAlreadyAppliedPresentation() throws {
        let coordinator = AppRouteCoordinator()
        let activeID = UUID()
        let presentationID = UUID()
        let queuedID = UUID()
        coordinator.request(.fieldTrips, source: .internalUserAction, id: activeID, now: now)
        let active = try #require(coordinator.claimNext(now: now))
        coordinator.resolve(
            active.id,
            outcome: .applied(presentationID: presentationID),
            now: now
        )

        coordinator.request(
            .scansLibrary,
            source: .internalUserAction,
            id: queuedID,
            now: now.addingTimeInterval(31)
        )

        #expect(coordinator.inFlightRequest?.id == activeID)
        #expect(coordinator.inFlightOutcome == .applied(presentationID: presentationID))
        #expect(coordinator.pendingRequests.map(\.id) == [queuedID])
        #expect(!coordinator.recentOutcomes.contains {
            $0.requestID == activeID && $0.outcome == .rejected(reason: .expired)
        })
    }

    @Test func accountChangesFenceSensitiveRoutesButKeepPublicRoutes() throws {
        let coordinator = AppRouteCoordinator()
        coordinator.beginAccountSession(accountID: "user-a", now: now)
        let sensitiveID = UUID()
        let publicID = UUID()
        coordinator.request(.scan(scanId: "owned-scan"), source: .deepLink, id: sensitiveID, now: now)
        coordinator.request(
            .explorePost(postId: "public-post", targetCommentId: nil, targetReplyParentCommentId: nil),
            source: .deepLink,
            id: publicID,
            now: now
        )

        coordinator.beginAccountSession(accountID: "user-b", now: now)

        #expect(coordinator.recentOutcomes.contains {
            $0.requestID == sensitiveID && $0.outcome == .rejected(reason: .staleAccount)
        })
        let publicRequest = try #require(coordinator.claimNext(now: now))
        #expect(publicRequest.id == publicID)
    }

    @Test func initialAccountRestorationPreservesColdLaunchRoute() throws {
        let coordinator = AppRouteCoordinator()
        let requestID = UUID()
        coordinator.request(.scan(scanId: "restored-scan"), source: .deepLink, id: requestID, now: now)

        coordinator.beginAccountSession(
            accountID: "restored-user",
            origin: .initialRestoration,
            now: now
        )

        #expect(coordinator.accountGeneration == 0)
        let request = try #require(coordinator.claimNext(now: now))
        #expect(request.id == requestID)
    }

    @Test func runtimeSignInFencesPrivateRoutesQueuedWithoutAnAccount() {
        let coordinator = AppRouteCoordinator()
        let requestID = UUID()
        coordinator.request(.scan(scanId: "prior-owner-scan"), source: .deepLink, id: requestID, now: now)

        coordinator.beginAccountSession(
            accountID: "interactive-user",
            origin: .runtimeTransition,
            now: now
        )

        #expect(coordinator.accountGeneration == 1)
        #expect(coordinator.claimNext(now: now) == nil)
        #expect(coordinator.recentOutcomes.last?.requestID == requestID)
        #expect(coordinator.recentOutcomes.last?.outcome == .rejected(reason: .staleAccount))
    }

    @Test func sessionAdvanceRejectsInternalRoutesButPreservesExternalIntent() throws {
        let coordinator = AppRouteCoordinator()
        let internalID = UUID()
        let externalID = UUID()
        coordinator.request(.fieldTrips, source: .internalUserAction, id: internalID, now: now)
        coordinator.request(
            .explorePost(postId: "post", targetCommentId: nil, targetReplyParentCommentId: nil),
            source: .deepLink,
            id: externalID,
            now: now
        )

        coordinator.advanceSession(now: now)

        #expect(coordinator.recentOutcomes.contains {
            $0.requestID == internalID && $0.outcome == .rejected(reason: .staleSession)
        })
        let externalRequest = try #require(coordinator.claimNext(now: now))
        #expect(externalRequest.id == externalID)
    }

    @Test func deferredPresentationResumesOnceAndFinishesOnDismissal() throws {
        let coordinator = AppRouteCoordinator()
        let requestID = UUID()
        let presentationID = UUID()
        coordinator.request(.scansLibrary, source: .internalUserAction, id: requestID, now: now)
        let request = try #require(coordinator.claimNext(now: now))

        coordinator.resolve(
            request.id,
            outcome: .deferred(reason: .presentationOccupied),
            now: now
        )
        #expect(coordinator.claimNext(now: now) == nil)

        coordinator.resumeDeferredRequest(requestID)
        coordinator.resumeDeferredRequest(requestID)
        #expect(coordinator.pendingRequests.map(\.id) == [requestID])

        let resumed = try #require(coordinator.claimNext(now: now))
        coordinator.resolve(
            resumed.id,
            outcome: .applied(presentationID: presentationID),
            now: now
        )
        #expect(coordinator.inFlightRequest?.id == requestID)
        #expect(coordinator.nextRequestID == nil)

        let stalePresentationID = UUID()
        let outcomeCountBeforeStaleDismissal = coordinator.recentOutcomes.count
        coordinator.resolve(
            resumed.id,
            outcome: .dismissed(presentationID: stalePresentationID),
            now: now
        )
        #expect(coordinator.inFlightRequest?.id == requestID)
        #expect(coordinator.recentOutcomes.count == outcomeCountBeforeStaleDismissal)

        coordinator.resolve(
            resumed.id,
            outcome: .dismissed(presentationID: presentationID),
            now: now
        )
        let outcomeCount = coordinator.recentOutcomes.count
        coordinator.resolve(
            resumed.id,
            outcome: .dismissed(presentationID: presentationID),
            now: now
        )

        #expect(coordinator.inFlightRequest == nil)
        #expect(coordinator.recentOutcomes.count == outcomeCount)
        #expect(coordinator.recentOutcomes.last?.outcome == .dismissed(presentationID: presentationID))
    }

    @Test func deferredResumeCannotExceedThePendingQueueBound() throws {
        let coordinator = AppRouteCoordinator(maximumPendingCount: 2)
        let deferredID = UUID()
        coordinator.request(.fieldTrips, source: .genericLaunch, id: deferredID, now: now)
        let deferred = try #require(coordinator.claimNext(now: now))
        coordinator.resolve(
            deferred.id,
            outcome: .deferred(reason: .presentationOccupied),
            now: now
        )

        coordinator.request(.scansLibrary, source: .internalUserAction, id: UUID(), now: now)
        coordinator.request(
            .processExternalImageImports,
            source: .durableExternalImport,
            id: UUID(),
            now: now
        )
        coordinator.resumeDeferredRequest(deferredID)

        #expect(coordinator.pendingRequests.count == 2)
        #expect(!coordinator.pendingRequests.contains { $0.id == deferredID })
        #expect(coordinator.recentOutcomes.contains {
            $0.requestID == deferredID && $0.outcome == .rejected(reason: .overflow)
        })
    }

    @Test func strongerDeferredResumeEvictsOneEligiblePendingRoute() throws {
        let coordinator = AppRouteCoordinator(maximumPendingCount: 2)
        let deferredID = UUID()
        let oldestLowID = UUID()
        coordinator.request(
            .processExternalImageImports,
            source: .durableExternalImport,
            id: deferredID,
            now: now
        )
        let deferred = try #require(coordinator.claimNext(now: now))
        coordinator.resolve(
            deferred.id,
            outcome: .deferred(reason: .dependenciesUnavailable),
            now: now
        )

        coordinator.request(.fieldTrips, source: .genericLaunch, id: oldestLowID, now: now)
        coordinator.request(
            .nonBiologicalScans,
            source: .internalUserAction,
            id: UUID(),
            now: now.addingTimeInterval(1)
        )
        coordinator.resumeDeferredRequest(deferredID)

        #expect(coordinator.pendingRequests.count == 2)
        #expect(coordinator.pendingRequests.first?.id == deferredID)
        #expect(coordinator.recentOutcomes.contains {
            $0.requestID == oldestLowID && $0.outcome == .rejected(reason: .overflow)
        })
    }

    @Test func expiredDeferredResumeDoesNotEvictAValidPendingRoute() throws {
        let coordinator = AppRouteCoordinator(maximumPendingCount: 1)
        let expiredID = UUID()
        let durableID = UUID()
        let expiredCreationDate = Date().addingTimeInterval(-60)
        coordinator.request(
            .fieldTrips,
            source: .internalUserAction,
            id: expiredID,
            now: expiredCreationDate
        )
        let deferred = try #require(coordinator.claimNext(now: expiredCreationDate))
        coordinator.resolve(
            deferred.id,
            outcome: .deferred(reason: .presentationOccupied),
            now: expiredCreationDate
        )
        coordinator.request(
            .processExternalImageImports,
            source: .durableExternalImport,
            id: durableID,
            now: Date()
        )

        coordinator.resumeDeferredRequest(expiredID)

        #expect(coordinator.pendingRequests.map(\.id) == [durableID])
        #expect(coordinator.recentOutcomes.contains {
            $0.requestID == expiredID && $0.outcome == .rejected(reason: .expired)
        })
    }

    @Test func duplicateAppliedCallbackCannotReplacePresentationIdentity() throws {
        let coordinator = AppRouteCoordinator()
        let requestID = UUID()
        let presentationID = UUID()
        coordinator.request(.scansLibrary, source: .internalUserAction, id: requestID, now: now)
        let request = try #require(coordinator.claimNext(now: now))

        coordinator.resolve(
            request.id,
            outcome: .applied(presentationID: presentationID),
            now: now
        )
        coordinator.resolve(
            request.id,
            outcome: .applied(presentationID: UUID()),
            now: now
        )

        #expect(coordinator.inFlightOutcome == .applied(presentationID: presentationID))
        coordinator.resolve(
            request.id,
            outcome: .dismissed(presentationID: presentationID),
            now: now
        )
        #expect(coordinator.inFlightRequest == nil)
    }

    @Test func explicitRoutesSuppressImmediateTimeoutResetOnlyWithinWindow() throws {
        let coordinator = AppRouteCoordinator()
        let requestID = coordinator.request(
            .explorePost(postId: "post", targetCommentId: nil, targetReplyParentCommentId: nil),
            source: .deepLink,
            now: now
        )
        #expect(coordinator.shouldSuppressTimeoutReset(now: now))

        _ = try #require(coordinator.claimNext(now: now))
        coordinator.resolve(requestID, outcome: .applied(presentationID: nil), now: now)

        #expect(coordinator.shouldSuppressTimeoutReset(now: now.addingTimeInterval(5)))
        #expect(!coordinator.shouldSuppressTimeoutReset(now: now.addingTimeInterval(5.001)))
    }

    @Test func missingScanIsRejectedAndDoesNotStallTheQueue() {
        let container = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: container,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        let requestID = container.appRouteCoordinator.request(
            .scan(scanId: "definitely-missing-scan"),
            source: .deepLink,
            now: now
        )

        viewModel.consumeNextAppRoute(now: now)

        #expect(container.appRouteCoordinator.inFlightRequest == nil)
        #expect(container.appRouteCoordinator.nextRequestID == nil)
        #expect(container.appRouteCoordinator.recentOutcomes.last?.requestID == requestID)
        #expect(
            container.appRouteCoordinator.recentOutcomes.last?.outcome
                == .rejected(reason: .targetUnavailable)
        )
    }
}
