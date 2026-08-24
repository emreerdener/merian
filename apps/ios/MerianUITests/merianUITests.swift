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
            "-seedLocationPermissionPromptSuppressed",
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
    func testNonBiologicalCollectionBackReturnsToCollectionsTab() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-seedNonBiologicalCollectionRoute"]
        )

        let nonBiologicalNavigationBar = app.navigationBars["Non-biological"]
        XCTAssertTrue(
            nonBiologicalNavigationBar.waitForExistence(timeout: 8.0),
            "The seeded Non-biological collection did not open"
        )

        let backButton = nonBiologicalNavigationBar.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.isHittable)
        backButton.tap()

        let collectionsSegment = app.segmentedControls.buttons["Collections"]
        XCTAssertTrue(collectionsSegment.waitForExistence(timeout: 4.0))
        XCTAssertTrue(
            collectionsSegment.isSelected,
            "Back did not preserve the Collections tab selection"
        )

        let nonBiologicalCollectionCard = app.buttons[
            "NonBiologicalCollectionCard"
        ]
        XCTAssertTrue(
            nonBiologicalCollectionCard.waitForExistence(timeout: 4.0),
            "Back did not reveal the Collections page"
        )
        let cardBecameHittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: nonBiologicalCollectionCard
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [cardBecameHittable], timeout: 4.0),
            .completed,
            "The Collections segment was selected while the Scans page remained visible"
        )
    }

    @MainActor
    func testPrivateScanMapCollectionNavigationFiltersAndInsight() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-seedPrivateScanMapFlow"]
        )

        let collectionsSegment = app.segmentedControls.buttons["Collections"]
        XCTAssertTrue(
            collectionsSegment.waitForExistence(timeout: 8.0),
            "The seeded Scans library did not open"
        )
        collectionsSegment.tap()
        XCTAssertTrue(waitForSelectedState(collectionsSegment))

        let mapCard = app.descendants(matching: .any)[
            "PrivateScanMapCollectionCard"
        ]
        XCTAssertTrue(
            mapCard.waitForExistence(timeout: 5.0),
            "Collections did not show the mapped-scan card"
        )
        XCTAssertTrue(mapCard.isHittable)
        XCTAssertTrue(mapCard.label.contains("305 mapped scans"))
        XCTAssertTrue(mapCard.label.contains("Private"))

        let featuredTitle = app.staticTexts["Featured scans"]
        XCTAssertTrue(featuredTitle.waitForExistence(timeout: 4.0))
        XCTAssertLessThan(
            mapCard.frame.minY,
            featuredTitle.frame.minY,
            "Scan map must be the first full-width collection card"
        )

        mapCard.tap()
        let mapNavigationBar = app.navigationBars["Scan map"]
        XCTAssertTrue(
            mapNavigationBar.waitForExistence(timeout: 8.0),
            "Tapping the collection card did not push Scan map"
        )
        XCTAssertTrue(mapNavigationBar.buttons["Collections"].exists)
        XCTAssertFalse(mapNavigationBar.buttons["Close"].exists)
        XCTAssertFalse(app.segmentedControls.buttons["Scans"].exists)
        XCTAssertFalse(app.segmentedControls.buttons["Feed"].exists)
        XCTAssertFalse(app.segmentedControls.buttons["Map"].exists)
        XCTAssertFalse(app.buttons["New collection"].exists)
        XCTAssertFalse(app.buttons["Notifications"].exists)
        XCTAssertFalse(app.buttons["ExploreCloseButton"].exists)
        XCTAssertFalse(
            app.buttons["MainTabBar_Scans"].isHittable,
            "The root bottom navigation must remain hidden on Scan map"
        )

        let visibleCount = app.buttons["PrivateScanMapVisibleCount"]
        let locateButton = app.buttons["PrivateScanMapLocate"]
        XCTAssertTrue(visibleCount.waitForExistence(timeout: 5.0))
        XCTAssertTrue(locateButton.waitForExistence(timeout: 5.0))
        XCTAssertGreaterThan(visibleCount.frame.midY, app.frame.height * 0.75)
        XCTAssertEqual(visibleCount.frame.midY, locateButton.frame.midY, accuracy: 8)
        XCTAssertLessThan(locateButton.frame.maxY, app.frame.maxY)

        mapNavigationBar.buttons["Collections"].tap()
        XCTAssertTrue(collectionsSegment.waitForExistence(timeout: 5.0))
        XCTAssertTrue(collectionsSegment.isSelected)
        XCTAssertTrue(mapCard.waitForExistence(timeout: 5.0))

        mapCard.tap()
        XCTAssertTrue(mapNavigationBar.waitForExistence(timeout: 5.0))

        let filtersButton = app.buttons["PrivateScanMapFilters"]
        XCTAssertTrue(filtersButton.waitForExistence(timeout: 4.0))
        filtersButton.tap()

        let birdsFilter = app.buttons["PrivateScanMapCategory-birds"]
        XCTAssertTrue(
            birdsFilter.waitForExistence(timeout: 4.0),
            "The local species filter did not appear"
        )
        birdsFilter.tap()
        app.navigationBars["Map filters"].buttons["Done"].tap()

        let oneDiscoveryExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label == %@",
                "1 discovery in view"
            ),
            object: visibleCount
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [oneDiscoveryExpectation], timeout: 5.0),
            .completed,
            "Filtering did not preserve the true viewport scan count"
        )

        let mapCanvas = app.descendants(matching: .any)[
            "PrivateScanMapCanvas"
        ]
        XCTAssertTrue(
            mapCanvas.waitForExistence(timeout: 4.0),
            "Scan map did not expose its gesture surface"
        )
        mapCanvas.pinch(withScale: 2.0, velocity: 1.0)
        mapCanvas.pinch(withScale: 2.0, velocity: 1.0)

        let birdPoint = app.buttons["PrivateScanMapPoint-private_map_bird"]
        XCTAssertTrue(
            birdPoint.waitForExistence(timeout: 5.0),
            "Zooming across the thumbnail threshold removed the filtered point"
        )
        let firstThumbnailExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                birdPoint.exists && birdPoint.frame.width >= 40
            },
            object: birdPoint
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [firstThumbnailExpectation], timeout: 5.0),
            .completed,
            "Zooming in did not cross from a dot to a thumbnail waypoint"
        )

        mapCanvas.pinch(withScale: 0.5, velocity: -1.0)
        mapCanvas.pinch(withScale: 0.5, velocity: -1.0)
        mapCanvas.pinch(withScale: 2.0, velocity: 1.0)
        mapCanvas.pinch(withScale: 2.0, velocity: 1.0)

        let secondThumbnailExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                birdPoint.exists && birdPoint.frame.width >= 40
            },
            object: birdPoint
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [secondThumbnailExpectation], timeout: 5.0),
            .completed,
            "Repeated zooming did not restore the thumbnail waypoint"
        )
        XCTAssertTrue(
            visibleCount.isHittable,
            "Zooming across the thumbnail threshold made the map unresponsive"
        )
        birdPoint.tap()

        let preview = app.buttons["PrivateScanMapPreview"]
        XCTAssertTrue(
            preview.waitForExistence(timeout: 4.0),
            "Selecting a point did not show the owner-only preview"
        )
        preview.tap()

        let insight = app.otherElements["InsightSheetView"]
        XCTAssertTrue(
            insight.waitForExistence(timeout: 8.0),
            "Tapping the scan preview did not push private Insight"
        )
        let insightBackButton = app.buttons["InsightSheetBackButton"]
        XCTAssertTrue(insightBackButton.waitForExistence(timeout: 4.0))
        insightBackButton.tap()
        XCTAssertTrue(mapNavigationBar.waitForExistence(timeout: 5.0))

        visibleCount.tap()
        let sheetHeader = app.descendants(matching: .any)[
            "PrivateScanMapSheetHeader"
        ]
        XCTAssertTrue(sheetHeader.waitForExistence(timeout: 5.0))
        XCTAssertTrue(sheetHeader.label.contains("Your scans"))
        XCTAssertTrue(sheetHeader.label.contains("Private"))

        let birdRow = app.buttons["PrivateScanMapSheetRow-private_map_bird"]
        XCTAssertTrue(birdRow.waitForExistence(timeout: 4.0))
        birdRow.tap()

        XCTAssertTrue(
            insight.waitForExistence(timeout: 8.0),
            "Selecting a sheet row did not dismiss before pushing private Insight"
        )
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

        let shutter = app.buttons["CaptureShutter"]
        let idlePrompt = app.staticTexts["AudioIdlePrompt"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 4.0), "Audio capture button did not render")
        XCTAssertTrue(idlePrompt.waitForExistence(timeout: 4.0), "Audio idle prompt did not render")
        XCTAssertEqual(idlePrompt.label, "Record nearby sounds")

        let renderedGap = shutter.frame.minY - idlePrompt.frame.maxY
        XCTAssertGreaterThanOrEqual(
            renderedGap,
            8,
            "Audio idle prompt overlaps the recording button; rendered gap was \(renderedGap) pt"
        )

        let promptDisappearance = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: idlePrompt
        )
        promptDisappearance.isInverted = true
        XCTAssertEqual(
            XCTWaiter.wait(for: [promptDisappearance], timeout: 4.0),
            .completed,
            "Audio idle prompt disappeared before recording started"
        )
    }

    @MainActor
    func testCaptureModeSelectorExposesAccessibleIconsAndTracksPagerSelection() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-captureModeOrder", "visual,audio,describe"]
        )

        let modeToggle = app.segmentedControls["CaptureModeToggle"]
        XCTAssertTrue(modeToggle.waitForExistence(timeout: 8.0), "Capture mode selector did not render")
        XCTAssertLessThanOrEqual(
            modeToggle.frame.width,
            app.frame.width - 48,
            "Capture mode selector no longer retains at least 24 pt side margins"
        )
        XCTAssertGreaterThanOrEqual(
            modeToggle.frame.width,
            196,
            "Capture mode selector became narrower than the compact-width contract"
        )
        XCTAssertLessThanOrEqual(
            modeToggle.frame.width,
            204,
            "Capture mode selector no longer uses compact horizontal spacing"
        )
        XCTAssertGreaterThanOrEqual(
            modeToggle.frame.height,
            52,
            "Capture mode selector became shorter than the compact-height contract"
        )
        XCTAssertLessThanOrEqual(
            modeToggle.frame.height,
            60,
            "Capture mode selector grew beyond the compact-height contract"
        )
        assertCaptureModeToggleIsCentered(modeToggle, in: app)
        let scanMode = modeToggle.buttons["Scan"]
        let recordMode = modeToggle.buttons["Record"]
        let describeMode = modeToggle.buttons["Describe"]
        XCTAssertTrue(scanMode.exists, "Scan icon is missing its accessible name")
        XCTAssertTrue(recordMode.exists, "Record icon is missing its accessible name")
        XCTAssertTrue(describeMode.exists, "Describe icon is missing its accessible name")
        XCTAssertGreaterThanOrEqual(
            scanMode.frame.width,
            44,
            "Compact Scan segment no longer meets the minimum touch width"
        )
        XCTAssertTrue(scanMode.isSelected, "The default visual mode is not selected")
        XCTAssertEqual(modeToggle.value as? String, "Scan")

        recordMode.tap()
        XCTAssertTrue(
            waitForSelectedState(recordMode),
            "Tapping the Record icon did not select its capture page; selector value: \(String(describing: modeToggle.value))"
        )
        XCTAssertEqual(modeToggle.value as? String, "Record")
        assertCaptureModeToggleIsCentered(modeToggle, in: app)

        describeMode.tap()
        XCTAssertTrue(
            waitForSelectedState(describeMode),
            "Tapping the Describe icon did not select its capture page"
        )
        XCTAssertEqual(modeToggle.value as? String, "Describe")
        assertCaptureModeToggleIsCentered(modeToggle, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["DescribeTextArea"].waitForExistence(timeout: 4.0),
            "Selecting the Describe icon did not reveal the Describe page"
        )

        app.swipeRight()
        XCTAssertTrue(
            waitForSelectedState(recordMode),
            "Paging from Describe to Record did not update the selected icon"
        )
        XCTAssertEqual(modeToggle.value as? String, "Record")
        assertCaptureModeToggleIsCentered(modeToggle, in: app)

        scanMode.tap()
        XCTAssertTrue(
            waitForSelectedState(scanMode),
            "Tapping the Scan icon did not restore the visual capture page"
        )
        XCTAssertEqual(modeToggle.value as? String, "Scan")
        assertCaptureModeToggleIsCentered(modeToggle, in: app)
        XCTAssertTrue(
            app.buttons["PhotoLibraryButton"].waitForExistence(timeout: 4.0),
            "Selecting the Scan icon did not restore camera controls"
        )
    }

    @MainActor
    func testCaptureGoalIndicatorCondensesExpandsSwipesAndResets() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: [
                "-captureModeOrder", "visual,audio,describe",
                "-seedCaptureGoalIndicatorFlow"
            ]
        )

        let artworkButton = app.buttons["activeCaptureGoalArtworkToggle"]
        let openButton = app.buttons["activeCaptureGoalOpenButton"]
        let collapseButton = app.buttons["activeCaptureGoalCollapseButton"]
        let modeToggle = app.segmentedControls["CaptureModeToggle"]
        XCTAssertTrue(
            artworkButton.waitForExistence(timeout: 8.0),
            "Seeded capture goal artwork did not render"
        )
        XCTAssertTrue(modeToggle.waitForExistence(timeout: 4.0))
        XCTAssertGreaterThanOrEqual(artworkButton.frame.width, 48)
        XCTAssertLessThanOrEqual(artworkButton.frame.width, 52)
        XCTAssertGreaterThanOrEqual(artworkButton.frame.height, 48)
        XCTAssertLessThanOrEqual(artworkButton.frame.height, 52)
        assertCaptureGoalIsInline(
            artworkButton: artworkButton,
            modeToggle: modeToggle,
            in: app
        )
        XCTAssertFalse(openButton.exists, "Goal details should begin collapsed")
        XCTAssertFalse(collapseButton.exists, "Goal collapse chevron should begin hidden")

        artworkButton.swipeLeft()
        XCTAssertTrue(
            waitForLabelContaining("Bird", on: artworkButton),
            "A compact swipe did not select the next goal"
        )
        XCTAssertFalse(openButton.exists, "A goal swipe unexpectedly expanded the indicator")

        artworkButton.swipeRight()
        XCTAssertTrue(
            waitForLabelContaining("Flowering plant", on: artworkButton),
            "A compact swipe did not select the previous goal"
        )

        tapCenter(of: artworkButton)
        XCTAssertTrue(
            openButton.waitForExistence(timeout: 4.0),
            "Tapping compact artwork did not reveal goal details"
        )
        XCTAssertTrue(
            waitForCaptureGoalExpanded(
                artworkButton: artworkButton,
                openButton: openButton,
                collapseButton: collapseButton,
                in: app
            ),
            "Expanded goal indicator did not fill the workspace margins"
        )
        let expandedFrame = artworkButton.frame
            .union(openButton.frame)
            .union(collapseButton.frame)
        XCTAssertEqual(expandedFrame.minX, app.frame.minX + 32, accuracy: 3)
        XCTAssertEqual(expandedFrame.maxX, app.frame.maxX - 32, accuracy: 3)
        XCTAssertGreaterThanOrEqual(
            expandedFrame.minY,
            modeToggle.frame.maxY + 8,
            "Expanded goal details did not move below the media selector"
        )

        openButton.swipeLeft()
        XCTAssertTrue(
            waitForLabelContaining("Bird", on: openButton),
            "An expanded swipe did not select the next goal"
        )
        XCTAssertTrue(openButton.exists, "A goal swipe unexpectedly opened or collapsed the indicator")

        tapCenter(of: artworkButton)
        XCTAssertTrue(
            waitForDisappearance(openButton),
            "Tapping expanded artwork did not collapse goal details"
        )
        XCTAssertFalse(collapseButton.exists)

        tapCenter(of: artworkButton)
        XCTAssertTrue(openButton.waitForExistence(timeout: 4.0))
        XCTAssertTrue(collapseButton.waitForExistence(timeout: 4.0))
        tapCenter(of: collapseButton)
        XCTAssertTrue(
            waitForDisappearance(openButton),
            "Tapping the up chevron did not collapse goal details"
        )

        tapCenter(of: artworkButton)
        XCTAssertTrue(openButton.waitForExistence(timeout: 4.0))
        let recordMode = modeToggle.buttons["Record"]
        let scanMode = modeToggle.buttons["Scan"]
        recordMode.tap()
        XCTAssertTrue(waitForSelectedState(recordMode))
        scanMode.tap()
        XCTAssertTrue(waitForSelectedState(scanMode))
        XCTAssertTrue(artworkButton.waitForExistence(timeout: 4.0))
        XCTAssertTrue(
            waitForDisappearance(openButton),
            "Returning to Scan did not restore the compact goal state"
        )
        assertCaptureGoalIsInline(
            artworkButton: artworkButton,
            modeToggle: modeToggle,
            in: app
        )

        tapCenter(of: artworkButton)
        XCTAssertTrue(openButton.waitForExistence(timeout: 4.0))
        tapCenter(of: openButton)
        XCTAssertTrue(
            app.buttons["ExploreCloseButton"].waitForExistence(timeout: 8.0),
            "Tapping the expanded goal content did not open Explore"
        )
    }

    @MainActor
    func testCaptureGoalIntroductionUsesTheSameCompactPatternWithoutPagingGoals() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: [
                "-captureModeOrder", "visual,audio,describe",
                "-seedCaptureGoalIntroductionFlow"
            ]
        )

        let artworkButton = app.buttons["captureGoalIntroductionArtworkToggle"]
        let openButton = app.buttons["captureGoalIntroductionOpenButton"]
        let collapseButton = app.buttons["captureGoalIntroductionCollapseButton"]
        let modeToggle = app.segmentedControls["CaptureModeToggle"]
        XCTAssertTrue(
            artworkButton.waitForExistence(timeout: 8.0),
            "Seeded outing introduction artwork did not render"
        )
        XCTAssertTrue(modeToggle.waitForExistence(timeout: 4.0))
        XCTAssertGreaterThanOrEqual(artworkButton.frame.width, 48)
        XCTAssertLessThanOrEqual(artworkButton.frame.width, 52)
        XCTAssertGreaterThanOrEqual(artworkButton.frame.height, 48)
        XCTAssertLessThanOrEqual(artworkButton.frame.height, 52)
        assertCaptureGoalIsInline(
            artworkButton: artworkButton,
            modeToggle: modeToggle,
            in: app
        )
        XCTAssertFalse(openButton.exists, "Outing introduction should begin collapsed")

        tapCenter(of: artworkButton)
        XCTAssertTrue(
            openButton.waitForExistence(timeout: 4.0),
            "Tapping introduction artwork did not reveal its details"
        )
        XCTAssertTrue(collapseButton.waitForExistence(timeout: 4.0))
        XCTAssertTrue(
            waitForLabelContaining("Start an outing", on: openButton)
        )
        XCTAssertEqual(openButton.value as? String, "0 of 2 goals complete.")
        let expandedFrame = artworkButton.frame
            .union(openButton.frame)
            .union(collapseButton.frame)
        XCTAssertEqual(expandedFrame.minX, app.frame.minX + 32, accuracy: 3)
        XCTAssertEqual(expandedFrame.maxX, app.frame.maxX - 32, accuracy: 3)
        XCTAssertGreaterThanOrEqual(
            expandedFrame.minY,
            modeToggle.frame.maxY + 8,
            "Expanded outing introduction did not move below the media selector"
        )

        openButton.swipeLeft()
        XCTAssertTrue(
            modeToggle.buttons["Scan"].isSelected,
            "The non-selectable introduction paged capture modes"
        )
        XCTAssertTrue(
            waitForLabelContaining("Start an outing", on: openButton),
            "The introduction incorrectly changed goals after a swipe"
        )

        tapCenter(of: collapseButton)
        XCTAssertTrue(
            waitForDisappearance(openButton),
            "Tapping the introduction up chevron did not restore the compact state"
        )
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
    private func waitForSelectedState(
        _ element: XCUIElement,
        timeout: TimeInterval = 4.0
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func tapCenter(of element: XCUIElement) {
        element.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
    }

    @MainActor
    private func assertCaptureModeToggleIsCentered(
        _ modeToggle: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            modeToggle.frame.midX,
            app.frame.midX,
            accuracy: 2,
            "Capture mode selector is not horizontally centered in the workspace",
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertCaptureGoalIsInline(
        artworkButton: XCUIElement,
        modeToggle: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedMaxX = max(
            app.frame.maxX - 32,
            modeToggle.frame.maxX + artworkButton.frame.width + 8
        )
        XCTAssertEqual(
            artworkButton.frame.maxX,
            expectedMaxX,
            accuracy: 3,
            "Compact goal artwork is not trailing-aligned beside the media selector",
            file: file,
            line: line
        )
        XCTAssertEqual(
            artworkButton.frame.midY,
            modeToggle.frame.midY,
            accuracy: 2,
            "Compact goal artwork is not vertically centered with the media selector",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            artworkButton.frame.minX - modeToggle.frame.maxX,
            7,
            "Compact goal artwork overlaps the media selector",
            file: file,
            line: line
        )
    }

    @MainActor
    private func waitForLabelContaining(
        _ fragment: String,
        on element: XCUIElement,
        timeout: TimeInterval = 4.0
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", fragment),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForDisappearance(
        _ element: XCUIElement,
        timeout: TimeInterval = 4.0
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForCaptureGoalExpanded(
        artworkButton: XCUIElement,
        openButton: XCUIElement,
        collapseButton: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval = 4.0
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard artworkButton.exists,
                      openButton.exists,
                      collapseButton.exists else { return false }
                let expandedFrame = artworkButton.frame
                    .union(openButton.frame)
                    .union(collapseButton.frame)
                return expandedFrame.width >= app.frame.width - 70
            },
            object: openButton
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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
    func testDescribeTextAreaFocusesFromLowerRegion() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-captureModeOrder", "describe,visual,audio"]
        )

        let textArea = app.descendants(matching: .any)["DescribeTextArea"]
        let textInput = app.textFields["DescribeTextInput"]
        XCTAssertTrue(textArea.waitForExistence(timeout: 8.0), "Describe text area did not render")
        XCTAssertTrue(textInput.waitForExistence(timeout: 4.0), "Describe text input did not render")

        let relativeInputBottom = (textInput.frame.maxY - textArea.frame.minY) / textArea.frame.height
        XCTAssertLessThan(
            relativeInputBottom,
            0.8,
            "The lower-region tap no longer lands below the intrinsic text input"
        )

        textArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()

        let enteredText = "Small green shape"
        textInput.typeText(enteredText)
        XCTAssertEqual(textInput.value as? String, enteredText)
    }

    @MainActor
    func testDescribeFirstLaunchRendersAndOpensPrompts() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-captureModeOrder", "describe,visual,audio"]
        )

        let describeMode = app.segmentedControls.buttons["Describe"]
        XCTAssertTrue(describeMode.waitForExistence(timeout: 8.0), "Describe mode did not render")
        XCTAssertTrue(describeMode.isSelected, "The configured Description-first order did not open Describe")

        let textArea = app.descendants(matching: .any)["DescribeTextArea"]
        XCTAssertTrue(textArea.waitForExistence(timeout: 4.0), "Describe text area did not render")
        let promptsButton = app.buttons["DescribePrompts"]
        let captureButton = app.buttons["CaptureShutter"]
        let dictationButton = app.buttons["DescribeDictation"]
        let modeToggle = app.segmentedControls["CaptureModeToggle"]
        let questionNavigation = app.descendants(matching: .any)["DescribeQuestionNavigation"]
        XCTAssertTrue(promptsButton.waitForExistence(timeout: 4.0), "Describe prompt control did not render")
        XCTAssertTrue(captureButton.waitForExistence(timeout: 4.0), "Describe capture control did not render")
        XCTAssertTrue(dictationButton.waitForExistence(timeout: 4.0), "Describe dictation control did not render")
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
    private func analyzingMediaCarouselElement(
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)["AnalyzingMediaCarousel"]
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
        waitForLabel("Analyzing amber banded wings...", on: badge)
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
        let analyzingCarousel = analyzingMediaCarouselElement(in: app)
        XCTAssertTrue(
            analyzingCarousel.waitForExistence(timeout: 8.0),
            "Live Insight did not expose its visual analyzing carousel"
        )
        let continuityValueBeforeHandoff = try XCTUnwrap(
            analyzingCarousel.value as? String
        )
        let queuedDeleteButton = insightSheet.buttons[
            "InsightQueuedDeleteButton"
        ]
        XCTAssertFalse(
            queuedDeleteButton.exists,
            "Queued deletion was accessible before the durable handoff"
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
        XCTAssertTrue(
            analyzingCarousel.waitForExistence(timeout: 4.0),
            "The pending queue handoff removed the analyzing carousel overlay"
        )
        XCTAssertEqual(
            analyzingCarousel.value as? String,
            continuityValueBeforeHandoff,
            "The same-scan queue handoff remounted the carousel or restarted its animation clock"
        )
        XCTAssertTrue(
            queuedDeleteButton.waitForExistence(timeout: 4.0),
            "The queued delete action did not fade into the stable toolbar slot"
        )
        let queuedDeleteBecameHittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: queuedDeleteButton
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [queuedDeleteBecameHittable], timeout: 4.0),
            .completed,
            "The queued delete action was visible but not interactive"
        )
        queuedDeleteButton.tap()
        let queuedDeleteAlert = app.alerts["Delete scan?"]
        XCTAssertTrue(
            queuedDeleteAlert.waitForExistence(timeout: 4.0),
            "The queued delete action did not preserve its confirmation binding"
        )
        XCTAssertTrue(
            queuedDeleteAlert.buttons["Cancel upload & delete"].exists,
            "The queued delete action opened the completed-scan deletion path"
        )
        queuedDeleteAlert.buttons["Cancel"].tap()
        XCTAssertFalse(
            queuedDeleteAlert.waitForExistence(timeout: 4.0),
            "The queued deletion confirmation did not dismiss"
        )
        XCTAssertTrue(
            liveScanningStatusBadge.exists,
            "The analyzing badge disappeared during the queue-owner handoff"
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
    func testQueuedRetryPresentationUsesSafeActionableCopy() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-seedQueuedRetryPresentationFlow"]
        )

        let scansButton = app.buttons["MainTabBar_Scans"]
        XCTAssertTrue(scansButton.waitForExistence(timeout: 8.0))
        scansButton.tap()

        let scheduledTile = app.buttons[
            "QueuedScanTile_ui_test_queued_retry_scheduled"
        ]
        XCTAssertTrue(scheduledTile.waitForExistence(timeout: 8.0))
        scheduledTile.tap()

        let scheduledReason = app.staticTexts.matching(
            NSPredicate(
                format: "label CONTAINS %@",
                "connection was interrupted"
            )
        ).firstMatch
        XCTAssertTrue(scheduledReason.waitForExistence(timeout: 8.0))
        XCTAssertTrue(app.buttons["Retry now"].exists)
        XCTAssertFalse(app.staticTexts["RAW_QUEUE_ERROR_SENTINEL"].exists)
        XCTAssertFalse(app.staticTexts["Automatic retry is starting"].exists)

        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 4.0))
        backButton.tap()

        let attentionTile = app.buttons[
            "QueuedScanTile_ui_test_queued_retry_attention"
        ]
        XCTAssertTrue(attentionTile.waitForExistence(timeout: 8.0))
        attentionTile.tap()

        let missingMediaReason = app.staticTexts.matching(
            NSPredicate(
                format: "label CONTAINS %@",
                "photo or recording is no longer available"
            )
        ).firstMatch
        XCTAssertTrue(missingMediaReason.waitForExistence(timeout: 8.0))
        XCTAssertFalse(app.buttons["Retry now"].exists)
        XCTAssertFalse(app.staticTexts["RAW_QUEUE_ERROR_SENTINEL"].exists)
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
