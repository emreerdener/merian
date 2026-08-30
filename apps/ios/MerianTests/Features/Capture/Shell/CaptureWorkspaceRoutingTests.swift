import CoreData
import MapKit
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Merian

extension CaptureWorkspaceViewModelRefinementTests {
    func testExploreDeepLinkSurvivesImmediateSessionTimeoutReset() async throws {
        let postId = "widget-post-123"
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .explore
        )

        deliverRoute(
            .explorePost(
                postId: postId,
                targetCommentId: nil,
                targetReplyParentCommentId: nil
            ),
            source: .deepLink,
            to: viewModel
        )
        try await waitUntil {
            viewModel.activeSheet == .explore && viewModel.pendingExplorePostId == postId
        }

        diContainer.appEventPublisher.send(.appDidResumeAfterTimeout)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.activeSheet, .explore)
        XCTAssertEqual(viewModel.pendingExplorePostId, postId)
    }

    func testSpeciesDictionaryDeepLinkOverridesConflictsAndSurvivesTimeoutReset() async throws {
        let speciesId = "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .explore
        )
        viewModel.pendingExplorePostId = "stale-post"
        viewModel.pendingCommunityIdentificationRequestId = "stale-request"
        viewModel.pendingExploreShowsFieldTrips = true

        deliverRoute(
            .speciesDictionary(speciesId: speciesId),
            source: .deepLink,
            to: viewModel
        )
        try await waitUntil {
            viewModel.activeSheet == .explore &&
                viewModel.pendingSpeciesDictionaryRoute?.speciesId == speciesId
        }

        XCTAssertEqual(viewModel.pendingSpeciesDictionaryRoute?.entryPoint, .deepLink)
        XCTAssertNil(viewModel.pendingExplorePostId)
        XCTAssertNil(viewModel.pendingCommunityIdentificationRequestId)
        XCTAssertFalse(viewModel.pendingExploreShowsFieldTrips)

        diContainer.appEventPublisher.send(.appDidResumeAfterTimeout)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.activeSheet, .explore)
        XCTAssertEqual(viewModel.pendingSpeciesDictionaryRoute?.speciesId, speciesId)
    }

    func testCommunityAndLibraryRoutesOverrideGenericLaunchExplore() async throws {
        let requestId = "community-request-123"
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .explore
        )

        deliverRoute(
            .communityIdentification(requestId: requestId),
            source: .internalUserAction,
            to: viewModel
        )
        try await waitUntil {
            viewModel.activeSheet == .explore &&
                viewModel.pendingCommunityIdentificationRequestId == requestId
        }

        diContainer.appRouteCoordinator.request(.scansLibrary, source: .appIntent)
        XCTAssertEqual(viewModel.activeSheet, .explore)
        viewModel.dismissActivePresentation()
        viewModel.handleRootSheetDismissed()
        viewModel.consumeNextAppRoute()
        try await waitUntil { viewModel.activeSheet == .scans }

        XCTAssertNil(viewModel.pendingCommunityIdentificationRequestId)
        XCTAssertNil(viewModel.pendingExplorePostId)
        XCTAssertNil(viewModel.pendingScansRecoveryContext)
    }

    func testRapidLocalSheetHandoffWaitsForDismissalAndKeepsLatestDestination() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .insight
        )
        let insightPresentationID = viewModel.activePresentation?.id

        viewModel.activeSheet = .profile
        XCTAssertNil(viewModel.activePresentation)

        viewModel.activeSheet = .scans
        XCTAssertNil(viewModel.activePresentation)

        viewModel.handleRootSheetDismissed()

        XCTAssertEqual(viewModel.activeSheet, .scans)
        XCTAssertNotEqual(viewModel.activePresentation?.id, insightPresentationID)
    }

    func testRouteArrivingDuringRootSheetTeardownDefersUntilExactDismissal() {
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .insight
        )

        viewModel.dismissActivePresentation()
        let requestID = diContainer.appRouteCoordinator.request(
            .scansLibrary,
            source: .deepLink
        )
        viewModel.consumeNextAppRoute()

        XCTAssertEqual(diContainer.appRouteCoordinator.inFlightRequest?.id, requestID)
        XCTAssertEqual(
            diContainer.appRouteCoordinator.inFlightOutcome,
            .deferred(reason: .presentationOccupied)
        )
        XCTAssertNil(viewModel.activePresentation)

        viewModel.handleRootSheetDismissed()
        viewModel.consumeNextAppRoute()

        XCTAssertEqual(viewModel.activeSheet, .scans)
        XCTAssertEqual(viewModel.activePresentation?.routeRequestID, requestID)
    }

    func testRouteDefersAcrossFeatureLocalPresentationUntilOnDismiss() {
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        let requestID = diContainer.appRouteCoordinator.request(
            .scansLibrary,
            source: .deepLink
        )

        viewModel.consumeNextAppRoute(isFeaturePresentationOccupied: true)
        XCTAssertEqual(
            diContainer.appRouteCoordinator.inFlightOutcome,
            .deferred(reason: .presentationOccupied)
        )
        XCTAssertNil(viewModel.activePresentation)

        viewModel.handleFeaturePresentationDismissed()
        viewModel.consumeNextAppRoute()

        XCTAssertEqual(viewModel.activeSheet, .scans)
        XCTAssertEqual(viewModel.activePresentation?.routeRequestID, requestID)
    }

    func testNonBiologicalLibraryRoutePreservesCollectionDestination() async throws {
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .insight
        )

        deliverRoute(
            .nonBiologicalScans,
            source: .internalUserAction,
            to: viewModel
        )
        try await waitUntil {
            viewModel.activeSheet == .scans &&
                viewModel.pendingScansShowsNonBiologicalCollection
        }

        XCTAssertNil(viewModel.pendingScansRecoveryContext)
    }

    func testProfileRecoveryRouteRejectsMismatchedOwnerWithoutStalling() async throws {
        let context = ExploreMediaRecoveryRouteContext(
            ownerUserId: "5d8372cc-1078-49a4-af27-e32d10290bad"
        )
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .profile
        )

        deliverRoute(
            .scansLibraryRecovery(context),
            source: .internalUserAction,
            to: viewModel
        )

        XCTAssertNil(viewModel.activeSheet)
        XCTAssertNil(viewModel.pendingScansRecoveryContext)
        XCTAssertEqual(
            diContainer.appRouteCoordinator.recentOutcomes.last?.outcome,
            .rejected(reason: .staleAccount)
        )
    }

    func testProfileFieldTripsRouteOpensExistingExploreFieldTripsRoot() async throws {
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .profile
        )
        viewModel.pendingExplorePostId = "stale-post"

        deliverRoute(.fieldTrips, source: .internalUserAction, to: viewModel)
        try await waitUntil {
            viewModel.activeSheet == .explore && viewModel.pendingExploreShowsFieldTrips
        }

        XCTAssertNil(viewModel.pendingExplorePostId)
        XCTAssertNil(viewModel.pendingCommunityIdentificationRequestId)
        XCTAssertNil(viewModel.pendingCaptureGoalDestination)
    }

    func testScanRouteOverridesGenericLaunchExplore() async throws {
        let modelContext = try makeModelContext()
        let previousModelContext = OfflineQueueManager.shared.modelContext
        OfflineQueueManager.shared.modelContext = modelContext
        defer { OfflineQueueManager.shared.modelContext = previousModelContext }

        let record = LocalScanRecord(
            speciesId: "launch-route-species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly"
        )
        modelContext.insert(record)
        try modelContext.save()

        let viewModel = CaptureWorkspaceViewModel(
            diContainer: AppDIContainer.preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .explore
        )

        deliverRoute(
            .scan(scanId: record.id),
            source: .deepLink,
            to: viewModel
        )
        try await waitUntil { viewModel.activeSheet == .insight }

        XCTAssertNil(viewModel.pendingExplorePostId)
        XCTAssertNil(viewModel.pendingCommunityIdentificationRequestId)
    }

    func testSessionTimeoutResetClearsStaleExploreRoute() async throws {
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        viewModel.pendingExplorePostId = "stale-post"
        viewModel.activeSheet = .explore

        diContainer.appEventPublisher.send(.appDidResumeAfterTimeout)

        try await waitUntil {
            viewModel.activeSheet == nil && viewModel.pendingExplorePostId == nil
        }
    }

}
