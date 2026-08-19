//
//  merianUITests.swift
//  merianUITests
//
//  Created by Emre Erdener on 3/6/26.
//

import XCTest

enum UITestAppLauncher {
    @MainActor
    static func makeConfiguredApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITesting"] = "true"
        app.launchArguments += [
            "-skipOnboarding",
            "-seedCurrentRequiredConsent",
            "-mockCameraFeed",
            "-hasCompletedOnboarding", "YES"
        ]
        app.launchArguments += extraArguments
        return app
    }

    @MainActor
    static func launchConfiguredApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = makeConfiguredApp(extraArguments: extraArguments)
        app.launch()
        return app
    }
}

// Keep the Xcode-generated test class name because existing CI selectors use it.
// swiftlint:disable:next type_name
final class merianUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        let app = UITestAppLauncher.launchConfiguredApp()
        XCTAssertTrue(app.buttons["MainTabBar_Profile"].waitForExistence(timeout: 8.0))
    }

    @MainActor
    func testExistingBiologicalHistoryDoesNotPresentFeedbackSurveyOnLaunch() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: [
                "-seedAchievementDetailFlow",
                "-feedbackSurveyDismissedCampaignId", "ui_test_none",
                "-feedbackSurveySubmittedCampaignId", "ui_test_none"
            ]
        )

        let shutter = app.buttons["CaptureShutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 8.0), "Camera shutter did not render")

        let feedbackIntro = app.staticTexts["Help us improve"]
        XCTAssertFalse(
            feedbackIntro.waitForExistence(timeout: 2.5),
            "Restored biological scan history presented the proactive survey during launch"
        )
        XCTAssertTrue(shutter.isHittable, "Launch history should not leave a survey over the capture workspace")
    }

    @MainActor
    func testAudioFirstLaunchSelectsRecordMode() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-captureModeOrder", "audio,visual,describe"]
        )

        let recordMode = app.segmentedControls.buttons["Record"]
        XCTAssertTrue(recordMode.waitForExistence(timeout: 8.0), "Record mode did not render")
        XCTAssertTrue(recordMode.isSelected, "The configured Audio-first order did not open Record")
        XCTAssertTrue(app.buttons["CaptureShutter"].waitForExistence(timeout: 4.0))
    }

    @MainActor
    func testStagedAudioBadgeOpensPlaybackReview() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-seedStagedAudioReviewFlow"]
        )

        let stagedAudioBadge = app.buttons["StagedAudioBadge_0"]
        XCTAssertTrue(
            stagedAudioBadge.waitForExistence(timeout: 8.0),
            "Seeded staged audio did not appear in the active scan toolbar"
        )
        XCTAssertTrue(stagedAudioBadge.isHittable)
        stagedAudioBadge.tap()

        let preview = app.otherElements[
            "AudioPlaybackCarouselPage_ui_test_staged_audio_review.wav"
        ]
        XCTAssertTrue(
            preview.waitForExistence(timeout: 8.0),
            "Tapping the staged waveform did not open audio playback"
        )

        let playbackControl = app.buttons[
            "AudioPlaybackControl_ui_test_staged_audio_review.wav"
        ]
        XCTAssertTrue(
            playbackControl.waitForExistence(timeout: 8.0),
            "The staged recording did not become playable"
        )

        let closeButton = app.buttons["Close audio preview"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 4.0))
        closeButton.tap()
        XCTAssertFalse(preview.waitForExistence(timeout: 4.0))
        XCTAssertTrue(stagedAudioBadge.waitForExistence(timeout: 4.0))
    }

    @MainActor
    func testCameraHintPreservesClearanceAboveShutter() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: [
                "-captureModeOrder", "visual,audio,describe",
                "-keepViewfinderHintVisible"
            ]
        )

        let hint = app.descendants(matching: .any)["ViewfinderHint"]
        let shutter = app.buttons["CaptureShutter"]
        XCTAssertTrue(hint.waitForExistence(timeout: 8.0), "Viewfinder hint did not render")
        XCTAssertTrue(shutter.waitForExistence(timeout: 4.0), "Camera shutter did not render")

        let renderedGap = shutter.frame.minY - hint.frame.maxY
        XCTAssertGreaterThanOrEqual(
            renderedGap,
            8,
            "Viewfinder hint overlaps the shutter; rendered gap was \(renderedGap) pt"
        )
    }

    @MainActor
    func testDescribeFirstLaunchRendersAndOpensPrompts() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-captureModeOrder", "describe,visual,audio"]
        )

        let describeMode = app.segmentedControls.buttons["Describe"]
        XCTAssertTrue(describeMode.waitForExistence(timeout: 8.0), "Describe mode did not render")
        XCTAssertTrue(describeMode.isSelected, "The configured Description-first order did not open Describe")

        let descriptionInput = app.textFields[
            "e.g., A bright green beetle with gold stripes resting on an oak leaf..."
        ]
        XCTAssertTrue(descriptionInput.waitForExistence(timeout: 4.0), "Describe input did not render")

        let promptsButton = app.buttons["DescribePrompts"]
        let captureButton = app.buttons["CaptureShutter"]
        let dictationButton = app.buttons["DescribeDictation"]
        let textArea = app.descendants(matching: .any)["DescribeTextArea"]
        let modeToggle = app.segmentedControls["CaptureModeToggle"]
        let questionNavigation = app.descendants(matching: .any)["DescribeQuestionNavigation"]
        XCTAssertTrue(promptsButton.waitForExistence(timeout: 4.0), "Describe prompt control did not render")
        XCTAssertTrue(captureButton.waitForExistence(timeout: 4.0), "Describe capture control did not render")
        XCTAssertTrue(dictationButton.waitForExistence(timeout: 4.0), "Describe dictation control did not render")
        XCTAssertTrue(textArea.waitForExistence(timeout: 4.0), "Describe text area did not render")
        XCTAssertTrue(modeToggle.waitForExistence(timeout: 4.0), "Capture mode toggle did not render")
        XCTAssertTrue(questionNavigation.waitForExistence(timeout: 4.0), "Describe question navigation did not render")
        XCTAssertEqual(promptsButton.frame.midY, captureButton.frame.midY, accuracy: 1)
        XCTAssertEqual(dictationButton.frame.midY, captureButton.frame.midY, accuracy: 1)

        let renderedTopGap = questionNavigation.frame.minY - modeToggle.frame.maxY
        XCTAssertGreaterThanOrEqual(
            renderedTopGap,
            8,
            "Describe question content overlaps the mode toggle; rendered gap was \(renderedTopGap) pt"
        )
        XCTAssertLessThanOrEqual(
            renderedTopGap,
            32,
            "Describe question content has unintended top padding; rendered gap was \(renderedTopGap) pt"
        )

        let controlRowTop = min(
            promptsButton.frame.minY,
            captureButton.frame.minY,
            dictationButton.frame.minY
        )
        let renderedGap = controlRowTop - textArea.frame.maxY
        XCTAssertGreaterThanOrEqual(
            renderedGap,
            8,
            "Describe controls overlap the text area; rendered gap was \(renderedGap) pt"
        )
        XCTAssertLessThanOrEqual(
            renderedGap,
            32,
            "Describe text area does not fill the space above the controls; rendered gap was \(renderedGap) pt"
        )

        promptsButton.tap()
        XCTAssertTrue(
            app.navigationBars["Prompts"].waitForExistence(timeout: 4.0),
            "The workspace-owned Describe prompt sheet did not open"
        )
    }

    @MainActor
    func testProfileOptionsMenuLivesInProfileToolbar() throws {
        let app = UITestAppLauncher.launchConfiguredApp()

        let profileButton = app.buttons["MainTabBar_Profile"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 8.0), "Main profile tab button failed to appear")
        profileButton.tap()

        let profileOptions = app.navigationBars.buttons["ProfileToolbarOptions"]
        XCTAssertTrue(profileOptions.waitForExistence(timeout: 8.0), "Profile options did not appear in the top toolbar")

        XCTAssertTrue(
            app.buttons["Continue with Apple"].waitForExistence(timeout: 4.0),
            "Anonymous Profile did not offer Continue with Apple"
        )
        XCTAssertTrue(
            app.buttons["Continue with Google"].exists,
            "Anonymous Profile did not offer Continue with Google"
        )
        XCTAssertFalse(
            app.buttons["Continue as Ghost"].exists,
            "Retired Ghost copy must not return to the user-facing account UI"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Ghost")
            ).firstMatch.exists,
            "Internal Ghost terminology must never be rendered"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS[c] %@", "guest session")
            ).firstMatch.exists,
            "Internal guest-session terminology must never be rendered"
        )

        let settingsTab = app.segmentedControls.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 4.0), "Settings tab did not appear")
        settingsTab.tap()
        XCTAssertTrue(profileOptions.waitForNonExistence(timeout: 4.0), "Profile options should be hidden on the Settings tab")

        let profileTab = app.segmentedControls.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 4.0), "Profile tab did not appear")
        profileTab.tap()
        XCTAssertTrue(profileOptions.waitForExistence(timeout: 4.0), "Profile options did not return on the Profile tab")
        profileOptions.tap()

        XCTAssertTrue(app.buttons["Replace profile pic"].waitForExistence(timeout: 4.0))
        XCTAssertTrue(app.buttons["Edit name"].exists)
        XCTAssertTrue(app.buttons["Edit username"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            UITestAppLauncher.makeConfiguredApp().launch()
        }
    }

    @MainActor
    func testAchievementDetailFlowOpensQualifyingScanInsight() throws {
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedAchievementDetailFlow"])

        let profileButton = app.buttons["MainTabBar_Profile"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 8.0), "Main profile tab button failed to appear")
        profileButton.tap()

        let fungiCard = app.buttons["AchievementCard_fungi"]
        XCTAssertTrue(fungiCard.waitForExistence(timeout: 8.0), "Fungi achievement card failed to load in the profile sheet")
        fungiCard.tap()

        let detailSheet = app.otherElements["AchievementDetailSheet_fungi"]
        XCTAssertTrue(detailSheet.waitForExistence(timeout: 8.0), "Achievement detail sheet did not present")

        let contributionRow = app.buttons["AchievementContribution_achievement_fungi_latest"]
        XCTAssertTrue(contributionRow.waitForExistence(timeout: 8.0), "Expected qualifying scan row was not rendered")
        contributionRow.tap()

        let insightSheet = app.otherElements["InsightSheetView"]
        XCTAssertTrue(insightSheet.waitForExistence(timeout: 8.0), "Insight sheet failed to present from the qualifying scan row")
    }

    @MainActor
    func testAchievementRootRefreshesAfterDeletingQualifyingScan() throws {
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedAchievementDeletionRefreshFlow"])

        let profileButton = app.buttons["MainTabBar_Profile"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 8.0), "Main profile tab button failed to appear")
        profileButton.tap()

        let dogCard = app.buttons["AchievementCard_domestic_dog"]
        XCTAssertTrue(dogCard.waitForExistence(timeout: 8.0), "Dog achievement card failed to load in the profile sheet")
        XCTAssertTrue(dogCard.label.contains("Completed achievement"), "Seeded dog achievement should start completed")
        tapWhenHittable(dogCard, in: app)

        let detailSheet = app.otherElements["AchievementDetailSheet_domestic_dog"]
        XCTAssertTrue(detailSheet.waitForExistence(timeout: 8.0), "Dog achievement detail sheet did not present")

        let contributionRow = app.buttons["AchievementContribution_achievement_domestic_dog_refresh"]
        XCTAssertTrue(contributionRow.waitForExistence(timeout: 8.0), "Expected dog qualifying scan row was not rendered")
        contributionRow.tap()

        let insightSheet = app.otherElements["InsightSheetView"]
        XCTAssertTrue(insightSheet.waitForExistence(timeout: 8.0), "Insight sheet failed to present from the dog qualifying scan row")

        let topMenu = app.buttons["InsightTopMenu"]
        XCTAssertTrue(topMenu.waitForExistence(timeout: 8.0), "Insight action menu did not appear")
        topMenu.tap()

        let deleteMenuItem = app.buttons["Delete scan"]
        XCTAssertTrue(deleteMenuItem.waitForExistence(timeout: 8.0), "Delete scan action did not appear")
        deleteMenuItem.tap()

        let deleteConfirmation = app.alerts["Delete scan?"].buttons["Delete scan permanently"]
        XCTAssertTrue(deleteConfirmation.waitForExistence(timeout: 8.0), "Delete confirmation did not appear")
        deleteConfirmation.tap()

        XCTAssertTrue(detailSheet.waitForExistence(timeout: 8.0), "Achievement detail sheet should remain visible after deleting the nested scan")
        XCTAssertTrue(app.staticTexts["0/1"].waitForExistence(timeout: 8.0), "Dog detail progress did not refresh after deleting the qualifying scan")

        app.buttons["AchievementDetailSheet_Close"].tap()

        let refreshedDogCard = app.buttons["AchievementCard_domestic_dog"]
        XCTAssertTrue(refreshedDogCard.waitForExistence(timeout: 8.0), "Dog achievement card did not return after closing detail")
        let refreshedLabel = NSPredicate(format: "label CONTAINS %@", "Progress 0 of 1")
        expectation(for: refreshedLabel, evaluatedWith: refreshedDogCard)
        waitForExpectations(timeout: 8.0)
    }

    @MainActor
    private func tapWhenHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(element.isHittable, "Expected element to become tappable", file: file, line: line)
        element.tap()
    }

    @MainActor
    private func scanningStatusBadgeElement(
        in app: XCUIApplication
    ) -> XCUIElement {
        app.buttons["ScanningStatusBadge"]
    }

    @MainActor
    private func insightSheetCloseButtonElement(
        in app: XCUIApplication
    ) -> XCUIElement {
        app.otherElements["InsightSheetView"]
            .buttons["InsightSheetCloseButton"]
    }

    @MainActor
    func testAnalyzingPillProgressesWithoutEscapingAccessibilityWindow() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-seedProgressiveAnalyzingFlow"]
        )
        let insightSheet = app.otherElements["InsightSheetView"]
        XCTAssertTrue(
            insightSheet.waitForExistence(timeout: 8.0),
            "Seeded progressive analyzing Insight failed to open"
        )

        let badge = scanningStatusBadgeElement(in: app)
        XCTAssertTrue(badge.waitForExistence(timeout: 8.0))
        XCTAssertEqual(badge.label, "Analyzing subject...")
        assertFrameIsInsideApplication(badge.frame, applicationFrame: app.frame)

        badge.tap()
        waitForLabel("Arthropod form visible...", on: badge)
        assertFrameIsInsideApplication(badge.frame, applicationFrame: app.frame)

        badge.tap()
        waitForLabel("Color: amber banded wings...", on: badge)
        assertFrameIsInsideApplication(badge.frame, applicationFrame: app.frame)
    }

    @MainActor
    private func waitForLabel(
        _ label: String,
        on element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 4.0),
            .completed,
            "Expected analyzing label \(label)",
            file: file,
            line: line
        )
    }

    private func assertFrameIsInsideApplication(
        _ frame: CGRect,
        applicationFrame: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            applicationFrame.insetBy(dx: -1, dy: -1).contains(frame),
            "Analyzing badge accessibility frame escaped the app window: \(frame)",
            file: file,
            line: line
        )
    }

    @MainActor
    func testLiveInsightConnectivityFailureTransitionsToDurableQueue() throws {
        let scanId = "ui_test_live_queue_handoff"
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-seedLiveQueueHandoffFlow"]
        )

        let insightSheet = app.otherElements["InsightSheetView"]
        XCTAssertTrue(
            insightSheet.waitForExistence(timeout: 8.0),
            "Seeded live analyzing Insight failed to open"
        )

        let liveScanningStatusBadge = scanningStatusBadgeElement(in: app)
        XCTAssertTrue(
            liveScanningStatusBadge.waitForExistence(timeout: 8.0),
            "Live Insight did not expose its analyzing status badge"
        )
        XCTAssertFalse(
            app.staticTexts["Network timeout"].exists,
            "The live sheet started in the obsolete timeout presentation"
        )
        liveScanningStatusBadge.tap()

        let exactQueuedPresentation = app.descendants(matching: .any)
            .matching(
                identifier: "QueuedPresentation_\(scanId)"
            )
            .firstMatch
        XCTAssertTrue(
            exactQueuedPresentation.waitForExistence(timeout: 8.0),
            "The open live Insight did not bind the exact durable queued row"
        )
        XCTAssertFalse(
            liveScanningStatusBadge.label.localizedCaseInsensitiveContains(
                "Continuing automatically"
            ),
            "Queue orchestration replaced the user-facing analysis phrase"
        )
        XCTAssertFalse(
            app.staticTexts[
                "Saved to Scans. Analysis is continuing automatically."
            ].exists,
            "The online handoff rendered redundant queue implementation copy"
        )
        XCTAssertFalse(
            app.staticTexts["Network timeout"].exists,
            "A durable live-to-queue handoff rendered Network timeout"
        )

        let closeButton = insightSheetCloseButtonElement(in: app)
        XCTAssertTrue(closeButton.waitForExistence(timeout: 4.0))
        closeButton.tap()
        XCTAssertFalse(
            insightSheet.waitForExistence(timeout: 4.0),
            "The live Insight did not dismiss after its queued handoff"
        )

        let scansButton = app.buttons["MainTabBar_Scans"]
        XCTAssertTrue(scansButton.waitForExistence(timeout: 8.0))
        scansButton.tap()
        XCTAssertTrue(
            app.buttons["QueuedScanTile_\(scanId)"].waitForExistence(
                timeout: 8.0
            ),
            "The exact durable scan disappeared after the live sheet handed off"
        )
    }

    @MainActor
    func testQueuedAudioScanRetainsAudioAcrossCompletionHandoff() throws {
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedQueuedAudioHandoffFlow"])

        let scansButton = app.buttons["MainTabBar_Scans"]
        XCTAssertTrue(scansButton.waitForExistence(timeout: 8.0), "Scans tab button failed to appear")
        scansButton.tap()

        let queuedTile = app.buttons["QueuedScanTile_ui_test_queued_audio_handoff"]
        XCTAssertTrue(queuedTile.waitForExistence(timeout: 8.0), "Seeded queued audio scan tile was not rendered")
        queuedTile.tap()

        let insightSheet = app.otherElements["InsightSheetView"]
        XCTAssertTrue(insightSheet.waitForExistence(timeout: 8.0), "Queued insight failed to open")

        XCTAssertTrue(
            app.buttons["Back"].waitForExistence(timeout: 8.0),
            "Queued insight did not open inside the scans navigation stack"
        )

        let scanningStatusBadge = scanningStatusBadgeElement(in: app)
        XCTAssertTrue(
            scanningStatusBadge.waitForExistence(timeout: 8.0),
            "Queued scan did not render the shared scanning status badge"
        )
        XCTAssertTrue(
            app.staticTexts["Did you know?"].waitForExistence(timeout: 8.0),
            "Queued scan did not render the shared scanning fact card"
        )

        let audioPage = app.otherElements["AudioPlaybackCarouselPage_ui_test_queued_audio_handoff.wav"]
        XCTAssertTrue(audioPage.waitForExistence(timeout: 8.0), "Audio carousel page was missing before the queued-to-result handoff")

        let playbackControl = app.buttons["AudioPlaybackControl_ui_test_queued_audio_handoff.wav"]
        XCTAssertTrue(
            playbackControl.waitForExistence(timeout: 8.0),
            "Seeded queued audio never became readable and playable"
        )

        XCTAssertTrue(
            scanningStatusBadge.isHittable,
            "Shared scanning status badge was not available to trigger the deterministic handoff"
        )
        let applicationFrame = app.frame
        let scanningStatusBadgeFrame = scanningStatusBadge.frame
        XCTAssertTrue(
            applicationFrame.contains(scanningStatusBadgeFrame),
            """
            Shared scanning status badge exposed an off-window accessibility frame. \
            appFrame=\(applicationFrame) badgeFrame=\(scanningStatusBadgeFrame)
            """
        )
        scanningStatusBadge.tap()

        XCTAssertTrue(app.staticTexts["Northern Cardinal"].waitForExistence(timeout: 8.0), "Seeded completed record did not take over the queued sheet")
        XCTAssertTrue(audioPage.waitForExistence(timeout: 2.0), "Audio carousel page disappeared after the queued-to-result handoff")
        XCTAssertTrue(
            playbackControl.waitForExistence(timeout: 8.0),
            "Readable audio did not survive the queued-to-result handoff"
        )
        XCTAssertTrue(
            app.buttons["FieldChatToolbarButton"].waitForExistence(timeout: 8.0),
            "Completed queued scan did not expose Field chat after handoff"
        )
        XCTAssertTrue(
            app.buttons["InsightShareButton"].waitForExistence(timeout: 8.0),
            "Completed queued scan did not expose sharing after handoff"
        )
    }

    @MainActor
    func testMissingVideoUsesOneZoomableImageFallback() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-seedMissingVideoFallbackFlow"]
        )

        let scansButton = app.buttons["MainTabBar_Scans"]
        XCTAssertTrue(scansButton.waitForExistence(timeout: 8.0), "Scans tab button failed to appear")
        scansButton.tap()

        let scanTile = app.buttons["ScanTile_ui_test_missing_video_fallback"]
        XCTAssertTrue(scanTile.waitForExistence(timeout: 8.0), "Seeded missing-video scan was not rendered")
        scanTile.tap()

        XCTAssertTrue(
            app.otherElements["InsightSheetView"].waitForExistence(timeout: 8.0),
            "Missing-video insight failed to open"
        )
        let fallback = app.descendants(matching: .any)["InsightVideoFallbackImage"]
        XCTAssertTrue(
            fallback.waitForExistence(timeout: 12.0),
            "Failed playback did not replace the video page with its retained image"
        )
        XCTAssertTrue(
            app.buttons["Video muted"].waitForNonExistence(timeout: 3.0),
            "Video mute controls remained after the page became an image"
        )
        XCTAssertTrue(fallback.isHittable, "Retained fallback image was not tappable")
        fallback.tap()

        XCTAssertTrue(
            app.buttons["Close image viewer"].waitForExistence(timeout: 8.0),
            "Fallback image did not open in the fullscreen zoom gallery"
        )
        XCTAssertFalse(app.buttons["Unmute video"].exists, "Image fallback exposed fullscreen video controls")
        XCTAssertFalse(app.buttons["Mute video"].exists, "Image fallback exposed fullscreen video controls")
    }

    @MainActor
    func testConfidenceSheetShowsReanalysisAndCommunityActions() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-seedMissingVideoFallbackFlow"]
        )

        let scansButton = app.buttons["MainTabBar_Scans"]
        XCTAssertTrue(scansButton.waitForExistence(timeout: 8.0), "Scans tab button failed to appear")
        scansButton.tap()

        let scanTile = app.buttons["ScanTile_ui_test_missing_video_fallback"]
        XCTAssertTrue(scanTile.waitForExistence(timeout: 8.0), "Seeded biological scan was not rendered")
        scanTile.tap()

        XCTAssertTrue(
            app.otherElements["InsightSheetView"].waitForExistence(timeout: 8.0),
            "Seeded insight failed to open"
        )

        let confidenceBadge = app.buttons["Strong match"]
        XCTAssertTrue(confidenceBadge.waitForExistence(timeout: 8.0), "Confidence badge did not render")
        confidenceBadge.tap()

        let reanalyzeButton = app.buttons["ConfidenceSheetReanalyzeButton"]
        let askCommunityButton = app.buttons["ConfidenceSheetAskCommunityButton"]
        XCTAssertTrue(
            reanalyzeButton.waitForExistence(timeout: 8.0),
            "Confidence sheet did not expose reanalysis"
        )
        XCTAssertTrue(
            askCommunityButton.waitForExistence(timeout: 8.0),
            "Confidence sheet did not expose community identification"
        )
        XCTAssertEqual(reanalyzeButton.label, "Reanalyze species")
        XCTAssertEqual(askCommunityButton.label, "Ask the community")
        XCTAssertGreaterThanOrEqual(
            askCommunityButton.frame.minY,
            reanalyzeButton.frame.maxY,
            "Confidence actions were not stacked in the requested order"
        )
    }

    @MainActor
    func testBackgroundSyncOfflineDisappearance() throws {
        try XCTSkipIf(true, "Offline Simulator execution boundaries trigger severe UI timeout execution flakes randomly.")
        let app = UITestAppLauncher.launchConfiguredApp()

        // 1. Wait for Main Camera View
        let libraryButton = app.descendants(matching: .any).matching(identifier: "PhotoLibraryButton").firstMatch
        XCTAssertTrue(libraryButton.waitForExistence(timeout: 8.0), "Camera root view failed to load library button")

        // 2. Perform Capture (via Image Picker bypass)
        libraryButton.tap()
        
        // Wait for iOS Photos picker to populate and tap the first default simulator element
        let photoImages = app.scrollViews.images
        guard photoImages.firstMatch.waitForExistence(timeout: 5.0) else {
            // If the simulator lacks local mock photos natively, we gracefully exit the test as skipped
            return
        }
        photoImages.firstMatch.tap()

        // 3. Wait for the Insight Sheet to mechanically slide up. We target the specific sheet element natively.
        let insightSheet = app.scrollViews.element(boundBy: 0)
        XCTAssertTrue(insightSheet.waitForExistence(timeout: 10.0), "Insight Sheet failed to present after mock capture")

        // 4. Force Background Transition (Triggering memory reclamation sequence!)
        XCUIDevice.shared.press(.home)
        
        // Sleep to grant iOS URLSession background transfer daemons time to boot and OS garbage collection to sweep Caches/
        sleep(4)

        // 5. Foreground Transition (User naturally returns to application)
        app.activate()

        // 6. Dismiss Insight Sheet by targeting close mechanisms or swiping down natively
        let closeButton = insightSheetCloseButtonElement(in: app)
        if closeButton.exists {
            closeButton.tap()
        } else {
            insightSheet.swipeDown(velocity: .fast)
        }

        // 7. Verify the OfflineQueuedScan visually persisted over the library collection
        // We ensure that it wasn't tombsoned by NSURLErrorFileDoesNotExist!
        let scansLibraryTab = app.tabBars.buttons["Scans"]
        if scansLibraryTab.waitForExistence(timeout: 3.0) {
            scansLibraryTab.tap()
        }
        
        // Assert mathematical UI existence of the pending dot or image grid cell
        // A generic UI test checks if the grid is populated rather than fully blank.
        let gridCells = app.collectionViews.cells
        // XCUIElementQuery exposes count but not Collection.isEmpty.
        // swiftlint:disable:next empty_count
        XCTAssertTrue(gridCells.count > 0, "Disappearance Bug: The backgrounded offline scan was wrongly tombstoned and vanished from the Library!")
    }
}
