import XCTest

@testable import Merian

extension CaptureWorkspaceViewModelRefinementTests {
    func testCompletedInsightDismissalPresentsNotificationPromptOnce() {
        let viewModel = notificationPromptWorkspace()
        let settings = viewModel.diContainer.appSettings

        // Native Close and swipe dismiss the outer sheet; neither writes the
        // child Insight isPresented binding that formerly owned the prompt.
        viewModel.dismissActivePresentation()
        XCTAssertNil(viewModel.activeSheet)
        XCTAssertFalse(settings.hasPromptedForNotificationsPostIdent)
        viewModel.handleRootSheetDismissed()

        XCTAssertEqual(viewModel.activeSheet, .notificationPrompt)
        XCTAssertTrue(settings.hasPromptedForNotificationsPostIdent)
        XCTAssertTrue(settings.isPushNotificationsEnabled)
        XCTAssertFalse(viewModel.diContainer.pushNotificationManager.hasAuthorization)
        let promptID = viewModel.activePresentation?.id
        viewModel.handleRootSheetDismissed()
        XCTAssertEqual(viewModel.activePresentation?.id, promptID)

        viewModel.dismissActivePresentation()
        viewModel.handleRootSheetDismissed()
        viewModel.activeSheet = .insight
        viewModel.dismissActivePresentation()
        viewModel.handleRootSheetDismissed()
        XCTAssertNil(viewModel.activeSheet)
    }

    func testNotificationPromptDoesNotInterruptLocalOrExternalNavigation() {
        for externalRoute in [false, true] {
            let viewModel = notificationPromptWorkspace()
            if externalRoute {
                viewModel.diContainer.appRouteCoordinator.request(
                    .scansLibrary,
                    source: .deepLink
                )
                viewModel.consumeNextAppRoute()
            } else {
                viewModel.activeSheet = .scans
            }
            viewModel.handleRootSheetDismissed()
            if externalRoute {
                viewModel.consumeNextAppRoute()
            }

            XCTAssertEqual(viewModel.activeSheet, .scans)
            XCTAssertFalse(
                viewModel.diContainer.appSettings.hasPromptedForNotificationsPostIdent
            )
        }
    }

    func testNotificationPromptRespectsOptOutAndExistingSystemAuthorization() {
        for scenario in ["noResult", "error", "processing", "disabled", "authorized", "declined", "otherSheet"] {
            let viewModel = notificationPromptWorkspace(authorized: scenario == "authorized")
            let container = viewModel.diContainer
            switch scenario {
            case "noResult": container.inferenceEngine.speciesData = nil
            case "error":
                container.inferenceEngine.speciesData = SpeciesData(
                    presentationRole: .inferenceError,
                    commonName: "Scan saved",
                    scientificName: "",
                    insightData: InsightData(aiReasoning: "Retry later", hazardType: "none"),
                    confidenceScore: 0,
                    isBiological: false
                )
            case "processing": container.inferenceEngine.isProcessing = true
            case "disabled": container.appSettings.isPushNotificationsEnabled = false
            case "authorized": break
            case "declined": container.appSettings.hasPromptedForNotificationsPostIdent = true
            default:
                viewModel.activePresentation = .init(
                    id: UUID(), destination: .profile, style: .sheet, routeRequestID: nil
                )
            }
            viewModel.dismissActivePresentation()
            viewModel.handleRootSheetDismissed()

            XCTAssertNil(viewModel.activeSheet, scenario)
            XCTAssertEqual(
                container.appSettings.hasPromptedForNotificationsPostIdent,
                scenario == "declined",
                scenario
            )
        }
    }

    private func notificationPromptWorkspace(authorized: Bool = false) -> CaptureWorkspaceViewModel {
        let container = AppDIContainer.preview
        let preferences = PushNotificationPreferencesProbe()
        preferences.booleans[UserDefaultsKeys.hasPushNotificationAuthorization] = authorized
        container.pushNotificationManager = PushNotificationManager(
            dependencies: .init(
                notificationCenter: SystemNotificationCenterProbe().makeService(),
                preferences: preferences.makeStore(),
                registrationCoordinator: PushRegistrationCoordinator(
                    dependencies: .init(
                        service: PushRegistrationService(register: { _ in }),
                        reportFailure: { _, _ in }
                    )
                ),
                registrationContext: .init(currentAccountScopeID: { nil }),
                pushEnvironment: "test",
                makeIdentifier: { "test" }
            ),
            requestRoute: { _, _ in }
        )
        container.inferenceEngine.speciesData = SpeciesData(
            scanId: "notification-test-scan",
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "A butterfly", hazardType: "none"),
            confidenceScore: 0.98,
            isBiological: true
        )
        return CaptureWorkspaceViewModel(
            diContainer: container,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .insight
        )
    }
}
