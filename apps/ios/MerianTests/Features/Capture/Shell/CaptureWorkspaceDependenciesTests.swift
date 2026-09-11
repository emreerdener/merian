import Photos
import XCTest

@testable import Merian

@MainActor
final class CaptureWorkspaceDependenciesTests: XCTestCase {
    func testViewModelUsesInjectedFeedbackWithoutRunningDisabledPrewarm() {
        let spy = CaptureWorkspaceDependencySpy()
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dependencies = CaptureWorkspaceDependencies(
            scan: .live(diContainer: AppDIContainer.shared),
            submission: .live(diContainer: AppDIContainer.shared),
            controls: CaptureControlDependencies(
                isVisualCaptureAllowed: { true },
                isProVideoAvailable: { false },
                dismissKeyboard: { spy.keyboardDismissalCount += 1 },
                trackProVideoPaywallImpression: {
                    spy.paywallImpressionCount += 1
                },
                performHapticFeedback: {
                    spy.captureControlFeedback.append($0)
                }
            ),
            navigation: CaptureNavigationDependencies(
                loadBadgeSnapshot: { _ in
                    CaptureNavigationBadgeSnapshot(
                        hasUnseenExternalPost: false,
                        unreadNotificationCount: nil
                    )
                },
                setHasUnseenExplorePost: { _ in },
                performRouteFeedback: {}
            ),
            stagingToolbar: CaptureStagingToolbarDependencies(
                photoLibrary: PHPhotoLibrary.shared(),
                dismissKeyboard: {},
                performCancelFeedback: {},
                hasShownTooltip: { true },
                markTooltipShown: {}
            ),
            prepareImage: { _ in nil },
            prepareHistoricalAudio: { _ in nil },
            externalImageImports: ExternalImageImportStore(rootURL: rootURL),
            downloadRefinementImage: { _ in nil },
            prewarmConnections: {
                spy.prewarmCount += 1
            },
            sharedExplorePostId: { _ in "post-id" },
            captureGoalAccountId: { $0?.uuidString.lowercased() },
            requestNotificationAuthorization: { completion in
                spy.authorizationRequestCount += 1
                completion(true)
            },
            feedback: CaptureWorkspaceFeedback(
                selection: { spy.selectionSources.append($0) },
                sheet: { spy.sheetSources.append($0) },
                medium: { spy.mediumCount += 1 },
                error: { spy.errorCount += 1 }
            )
        )
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: AppDIContainer.shared,
            dependencies: dependencies,
            prewarmHeadersOnInit: false
        )

        viewModel.triggerSelectionFeedback(source: "capture.test.selection")
        viewModel.triggerSheetFeedback(source: "capture.test.sheet")
        viewModel.triggerSheetFeedback()
        viewModel.triggerMediumFeedback()
        viewModel.triggerErrorFeedback()
        XCTAssertTrue(viewModel.isCaptureControlVisualCaptureAllowed)
        XCTAssertFalse(viewModel.isCaptureControlProVideoAvailable)
        viewModel.dismissCaptureControlKeyboard()
        viewModel.performCaptureControlHapticFeedback(
            .mediumPulse(.audioResume)
        )
        viewModel.presentCaptureControlPaywall()
        var notificationAuthorization: Bool?
        viewModel.requestNotificationAuthorization {
            notificationAuthorization = $0
        }

        XCTAssertEqual(spy.prewarmCount, 0)
        XCTAssertEqual(spy.selectionSources, ["capture.test.selection"])
        XCTAssertEqual(
            spy.sheetSources,
            ["capture.test.sheet", nil]
        )
        XCTAssertEqual(spy.mediumCount, 1)
        XCTAssertEqual(spy.errorCount, 1)
        XCTAssertEqual(spy.keyboardDismissalCount, 1)
        XCTAssertEqual(spy.paywallImpressionCount, 1)
        XCTAssertEqual(spy.authorizationRequestCount, 1)
        XCTAssertEqual(notificationAuthorization, true)
        XCTAssertEqual(
            spy.captureControlFeedback,
            [.mediumPulse(.audioResume)]
        )
        XCTAssertEqual(viewModel.activeSheet, .paywall)

        let userId = UUID(
            uuidString: "00000000-0000-4000-8000-000000000779"
        )!
        XCTAssertEqual(
            viewModel.captureGoalAccountId(for: userId),
            userId.uuidString.lowercased()
        )
    }
}

@MainActor
private final class CaptureWorkspaceDependencySpy {
    var prewarmCount = 0
    var selectionSources: [String] = []
    var sheetSources: [String?] = []
    var mediumCount = 0
    var errorCount = 0
    var keyboardDismissalCount = 0
    var paywallImpressionCount = 0
    var authorizationRequestCount = 0
    var captureControlFeedback: [CaptureButtonHapticFeedback] = []
}
