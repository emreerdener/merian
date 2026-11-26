//
//  merianUITests.swift
//  merianUITests
//
//  Created by Emre Erdener on 3/6/26.
//

import XCTest

enum UITestAppLauncher {
    @MainActor
    static func openIdentification(_ app: XCUIApplication, history: Bool = false, actions: Bool = false) {
        let menu = app.buttons["InsightTopMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        let entry = app.buttons["IdentificationMenu"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        let overflow = app.buttons["IdentificationActionsMenu"]
        XCTAssertTrue(overflow.waitForExistence(timeout: 5))
        if history || actions { overflow.tap() }
        if history {
            let historyAction = app.buttons["IdentificationHistoryMenu"]
            XCTAssertTrue(historyAction.waitForExistence(timeout: 5)); historyAction.tap()
        }
    }

    @MainActor
    static func slideIdentificationConfirmation(_ app: XCUIApplication) {
        let slider = app.buttons["IdentificationConfirm"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)))
    }

    @MainActor
    static func historyCard(_ app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "HistoryRow_" + id).firstMatch
    }

    @MainActor
    static func openHistoryActions(_ app: XCUIApplication, id: String) {
        let menu = app.buttons["HistoryActions_" + id]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        for _ in 0..<3 where !menu.isHittable { app.swipeUp() }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true AND hittable == true"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        menu.tap()
    }

    @MainActor
    static func closeHistory(_ app: XCUIApplication) {
        app.buttons["HistorySheetActions"].tap()
        app.buttons["HistoryDone"].tap()
    }

    @MainActor
    static func makeConfiguredApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITesting"] = "true"
        // Separate UI scenarios from unit-test ownership/recovery markers,
        // while retaining their own state when the same app is relaunched.
        app.launchEnvironment["UITestKeychainNamespace"] = UUID().uuidString
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
    func testLibraryLabelOpensScans() {
        let app = UITestAppLauncher.launchConfiguredApp()
        let library = app.buttons["MainTabBar_Naturebook"]
        XCTAssertTrue(library.waitForExistence(timeout: 8))
        XCTAssertEqual(library.label, "Library")
        XCTAssertTrue(library.isHittable)
        library.tap()
        XCTAssertTrue(app.segmentedControls.buttons["Scans"].waitForExistence(timeout: 8))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Library label and Scans navigation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testPrivateScanMapCollectionNavigationFiltersAndInsight() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-seedPrivateScanMapFlow"]
        )

        // Enter through the visible root when startup has not presented the seeded library.
        let scansEntry = app.buttons["MainTabBar_Naturebook"]
        if scansEntry.waitForExistence(timeout: 2), scansEntry.isHittable {
            scansEntry.tap()
        }

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
            featuredTitle.frame.maxY,
            mapCard.frame.minY,
            "Scan map must appear below Featured scans"
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
            app.buttons["MainTabBar_Naturebook"].isHittable,
            "The root bottom navigation must remain hidden on Scan map"
        )

        let visibleCount = app.buttons["PrivateScanMapVisibleCount"]
        let locateButton = app.buttons["PrivateScanMapLocate"]
        XCTAssertTrue(visibleCount.waitForExistence(timeout: 5.0))
        XCTAssertTrue(locateButton.waitForExistence(timeout: 5.0))
        XCTAssertGreaterThan(visibleCount.frame.midY, app.frame.height * 0.75)
        XCTAssertEqual(visibleCount.frame.midY, locateButton.frame.midY, accuracy: 8)
        XCTAssertLessThan(locateButton.frame.maxY, app.frame.maxY)

        let styleButton = app.buttons["PrivateScanMapStyle"]
        let searchButton = app.buttons["PrivateScanMapSearch"]
        XCTAssertTrue(styleButton.exists)
        XCTAssertTrue(searchButton.exists)
        let originalStyle = styleButton.value as? String
        styleButton.tap()
        XCTAssertNotEqual(styleButton.value as? String, originalStyle)
        styleButton.tap()
        searchButton.tap()
        let searchField = app.textFields["MapPlaceSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 4))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        searchField.tap()
        searchField.typeText("Synthetic")
        let place = app.buttons.containing(.staticText, identifier: "Synthetic nature reserve").firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 4))
        place.tap()
        XCTAssertTrue(searchField.waitForNonExistence(timeout: 4))
        XCTAssertTrue(mapNavigationBar.exists)

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
        let birdPoint = app.buttons["PrivateScanMapPoint-private_map_bird"]
        XCTAssertTrue(
            birdPoint.waitForExistence(timeout: 5.0),
            "Zooming across the thumbnail threshold removed the filtered point"
        )
        XCTAssertGreaterThan(birdPoint.frame.width, 0)
        XCTAssertLessThan(birdPoint.frame.width, 40, "The broad map must initially show a dot")
        zoomPrivateMap(mapCanvas, point: birdPoint, toThumbnail: true)
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

        zoomPrivateMap(mapCanvas, point: birdPoint, toThumbnail: false)
        XCTAssertTrue(birdPoint.exists)
        XCTAssertGreaterThan(birdPoint.frame.width, 0)
        XCTAssertLessThan(birdPoint.frame.width, 40, "Zooming out must restore the dot waypoint")
        zoomPrivateMap(mapCanvas, point: birdPoint, toThumbnail: true)

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
    private func zoomPrivateMap(_ canvas: XCUIElement, point: XCUIElement, toThumbnail: Bool) {
        for _ in 0..<3 {
            if toThumbnail {
                // Keep both taps in blank map content. Pinching the full SwiftUI
                // wrapper includes navigation/filter chrome in its gesture bounds.
                let frame = canvas.frame
                let pointFrame = point.frame
                let offset: CGFloat = pointFrame.midX < frame.midX ? -48 : 48
                let x = min(max(pointFrame.midX + offset, frame.minX + 30), frame.maxX - 30)
                let y = min(max(pointFrame.midY, frame.minY + 160), frame.maxY - 160)
                canvas.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: x - frame.minX, dy: y - frame.minY)).doubleTap()
            } else {
                canvas.pinch(withScale: 0.5, velocity: -1.0)
            }
            let reached = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                point.exists && point.frame.width > 0 && (point.frame.width >= 40) == toThumbnail
            }, object: point)
            if XCTWaiter.wait(for: [reached], timeout: 1) == .completed { return }
        }
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
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-captureModeOrder", "visual,audio"])
        let modes = app.segmentedControls["CaptureModeToggle"]
        XCTAssertTrue(modes.waitForExistence(timeout: 8))
        XCTAssertEqual(modes.frame.width, 144, accuracy: 2)
        XCTAssertGreaterThanOrEqual(modes.frame.height, 52)
        assertCaptureModeToggleIsCentered(modes, in: app)
        XCTAssertFalse(modes.buttons["Describe"].exists)
        let scan = modes.buttons["Scan"], record = modes.buttons["Record"]
        XCTAssertTrue(scan.isSelected)
        for segment in [scan, record] { XCTAssertGreaterThanOrEqual(segment.frame.width, 44) }
        record.tap()
        XCTAssertTrue(waitForSelectedState(record))
        XCTAssertEqual(modes.value as? String, "Record")
        scan.tap()
        XCTAssertTrue(waitForSelectedState(scan))
        XCTAssertEqual(modes.value as? String, "Scan")
        XCTAssertTrue(app.buttons["PhotoLibraryButton"].waitForExistence(timeout: 4))
        let pager = app.scrollViews["CaptureWorkspacePager"]
        pager.swipeUp()
        XCTAssertTrue(scan.isSelected, "Vertical viewfinder interaction must not change workspaces")
        pager.swipeLeft()
        XCTAssertTrue(waitForSelectedState(record))
        pager.swipeRight()
        XCTAssertTrue(waitForSelectedState(scan))
        assertCaptureModeToggleIsCentered(modes, in: app)
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
            app.staticTexts["Field trip unavailable"].waitForExistence(timeout: 8.0),
            "Tapping the expanded goal did not reach the seeded Field trip destination"
        )
        app.buttons["BackButton"].tap()
        let closeExplore = app.buttons["ExploreCloseButton"]
        XCTAssertTrue(closeExplore.waitForExistence(timeout: 4))
        closeExplore.tap()
        XCTAssertTrue(waitForDisappearance(closeExplore))
        XCTAssertTrue(modeToggle.isHittable)
        XCTAssertTrue(artworkButton.isHittable)
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
        XCTAssertFalse(app.staticTexts["Field trip unavailable"].exists, "Swiping the introduction opened its destination")
        XCTAssertTrue(collapseButton.isHittable)

        tapCenter(of: collapseButton)
        XCTAssertTrue(
            waitForDisappearance(openButton),
            "Tapping the introduction up chevron did not restore the compact state"
        )
        tapCenter(of: artworkButton)
        XCTAssertTrue(openButton.waitForExistence(timeout: 4))
        tapCenter(of: openButton)
        XCTAssertTrue(app.staticTexts["Field trip unavailable"].waitForExistence(timeout: 8))
        app.buttons["BackButton"].tap()
        let closeExplore = app.buttons["ExploreCloseButton"]
        XCTAssertTrue(closeExplore.waitForExistence(timeout: 4))
        closeExplore.tap()
        XCTAssertTrue(waitForDisappearance(closeExplore))
        XCTAssertTrue(artworkButton.isHittable)
    }

    @MainActor
    func testFinishedRecordingJoinsTrayWithoutIntermediateReview() throws {
        for paused in [false, true] {
            let app = UITestAppLauncher.launchConfiguredApp(extraArguments: [
                "-seedAudioFinishFlow", "-autoSubmitScans", "NO",
                "-captureModeOrder", "audio,visual,describe", "-hasShownCaptureNoteTip", "YES",
                "-boostRecordingPreviewsEnabled", "YES"
            ] + (paused ? ["-seedAudioFinishPaused"] : []))
            let finish = app.buttons["Finish recording"]
            XCTAssertTrue(finish.waitForExistence(timeout: 8))
            XCTAssertTrue(finish.isHittable)
            XCTAssertGreaterThanOrEqual(finish.frame.width, 44)
            XCTAssertGreaterThanOrEqual(finish.frame.height, 44)
            XCTAssertFalse(app.buttons["StagedAudioBadge_0"].exists)
            finish.tap()
            let audio = app.buttons["StagedAudioBadge_0"]
            XCTAssertTrue(audio.waitForExistence(timeout: 8))
            XCTAssertFalse(finish.exists)
            XCTAssertFalse(app.buttons["Retry adding recording"].exists)
            XCTAssertTrue(app.buttons["Identify"].isEnabled)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = paused ? "Paused recording finished directly into tray" : "Recording finished directly into tray"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            audio.tap()
            XCTAssertTrue(app.buttons["Remove audio recording"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["Turn off audio boost"].waitForExistence(timeout: 8))
            app.buttons["Add media"].tap()
            XCTAssertTrue(audio.waitForExistence(timeout: 4))
            audio.tap()
            app.buttons["Remove audio recording"].tap()
            let discard = app.alerts["Discard observation?"]
            XCTAssertTrue(discard.waitForExistence(timeout: 3))
            discard.buttons["Keep editing"].tap()
            XCTAssertTrue(app.buttons["Remove audio recording"].isHittable)
            XCTAssertTrue(app.buttons["Identify"].isEnabled)
            app.buttons["Remove audio recording"].tap()
            XCTAssertTrue(discard.waitForExistence(timeout: 3))
            discard.buttons["Discard"].tap()
            XCTAssertTrue(waitForDisappearance(audio))
            XCTAssertTrue(app.buttons["Record audio"].waitForExistence(timeout: 4))
            app.terminate()
        }
    }

    @MainActor
    func testStagedAudioBadgeOpensPlaybackReview() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: [
                "-seedStagedAudioReviewFlow", "-mockCaptureReviewLocation", "-captureModeOrder", "audio,visual,describe",
                "-hasShownCaptureNoteTip", "YES",
                "-hasShownCaptureSubmitTip", "NO",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"
            ]
        )

        let submitTip = app.staticTexts["CaptureSubmitTooltip"]
        XCTAssertTrue(submitTip.waitForExistence(timeout: 8))
        // Capture transient guidance once; subsequent accessibility queries can
        // otherwise outlast its four-second presentation on a busy simulator.
        let submitTipSnapshot = try submitTip.snapshot()
        XCTAssertEqual(submitTipSnapshot.label, "Submit to identify")
        XCTAssertLessThanOrEqual(submitTipSnapshot.frame.maxY, app.buttons["Identify"].frame.minY - 7)
        XCTAssertLessThanOrEqual(submitTipSnapshot.frame.maxX, app.frame.width - 16)
        let stagedAudioBadge = app.buttons["StagedAudioBadge_0"]
        XCTAssertTrue(
            stagedAudioBadge.waitForExistence(timeout: 8.0),
            "Seeded staged audio did not appear in the active scan toolbar"
        )
        XCTAssertTrue(stagedAudioBadge.isHittable)
        XCTAssertTrue(stagedAudioBadge.isEnabled)
        XCTAssertTrue(waitForDisappearance(submitTip, timeout: 6))
        let toolbarScreenshot = XCTAttachment(screenshot: app.screenshot())
        toolbarScreenshot.name = "Compact bordered audio and note review nodes"
        let note = app.buttons["CaptureFieldNotes"], identify = app.buttons["Identify"]
        XCTAssertTrue(note.isHittable)
        XCTAssertEqual(note.frame.midY, stagedAudioBadge.frame.midY, accuracy: 1)
        XCTAssertEqual(identify.frame.midY, note.frame.midY, accuracy: 1)
        for control in [note, identify, stagedAudioBadge] {
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }
        XCTAssertGreaterThan(identify.frame.width, identify.frame.height)
        let discard = app.buttons["Discard scan"]
        XCTAssertTrue(discard.isHittable)
        XCTAssertLessThan(discard.frame.maxY, stagedAudioBadge.frame.minY)
        XCTAssertFalse(app.buttons["Next"].exists)
        toolbarScreenshot.lifetime = .keepAlways
        add(toolbarScreenshot)
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

        let closeButton = app.buttons["Add media"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 4.0))
        closeButton.tap()
        XCTAssertFalse(preview.waitForExistence(timeout: 4.0))
        XCTAssertTrue(stagedAudioBadge.waitForExistence(timeout: 4.0))
        XCTAssertFalse(submitTip.exists, "The one-time submit tip must not return after preview")
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
        let expectedMinX = min(
            app.frame.minX + 32,
            modeToggle.frame.minX - artworkButton.frame.width - 8
        )
        XCTAssertEqual(
            artworkButton.frame.minX,
            expectedMinX,
            accuracy: 3,
            "Compact goal artwork is not leading-aligned beside the media selector",
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
            modeToggle.frame.minX - artworkButton.frame.maxX,
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
    func testStagedProSlotOpensDefaultPaywallAndPreservesDraft() throws {
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: [
            "-seedAudioFinishFlow", "-autoSubmitScans", "NO",
            "-captureModeOrder", "audio,visual,describe",
            "-hasShownCaptureNoteTip", "YES", "-themeMode", "Dark"
        ])
        let finish = app.buttons["Finish recording"]
        XCTAssertTrue(finish.waitForExistence(timeout: 8))
            XCTAssertTrue(finish.isHittable)
            XCTAssertGreaterThanOrEqual(finish.frame.width, 44)
            XCTAssertGreaterThanOrEqual(finish.frame.height, 44)
        finish.tap()
        let upgrade = app.buttons["StagedMediaProPlaceholder"]
        let audio = app.buttons["StagedAudioBadge_0"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 8))
        XCTAssertTrue(upgrade.isHittable)
        XCTAssertEqual(upgrade.label, "Add another media item with Pro")
        XCTAssertEqual(upgrade.frame.width, 58, accuracy: 1)
        XCTAssertEqual(upgrade.frame.height, 58, accuracy: 1)
        XCTAssertTrue(audio.isHittable)
        XCTAssertFalse(app.buttons["StagedMediaPlaceholder_0"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Free staged tray with Pro upgrade slot"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        upgrade.tap()
        let close = app.buttons["Close paywall"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Photos"].exists)
        close.tap()
        XCTAssertTrue(waitForDisappearance(close))
        XCTAssertTrue(audio.isHittable)
        XCTAssertTrue(upgrade.isHittable)
        XCTAssertTrue(app.buttons["CaptureFieldNotes"].isHittable)
        XCTAssertTrue(app.buttons["Identify"].isHittable)
    }

    @MainActor
    private func assertToolbarBounds(_ toolbar: XCUIElement, match expected: CGRect,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let actual = toolbar.frame
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 1, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 1, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 1, file: file, line: line)
    }

    @MainActor
    func testNoteAtMediaCapacityWithLargerText() throws {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: [
            "-seedStagedAudioReviewFlow", "-mockCaptureReviewLocation", "-autoSubmitScans", "NO",
            "-captureModeOrder", "audio,visual", "-hasShownCaptureNoteTip", "YES",
            "-hasShownCaptureSubmitTip", "YES", "-themeMode", "Light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        let note = app.buttons["CaptureFieldNotes"], identify = app.buttons["Identify"]
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        XCTAssertTrue(identify.isHittable)
        XCTAssertGreaterThanOrEqual(identify.frame.height, 44)
        XCTAssertGreaterThanOrEqual(note.frame.width, 44)
        XCTAssertGreaterThanOrEqual(note.frame.height, 44)
        XCTAssertFalse(app.buttons["Next"].exists)
        XCTAssertTrue(app.buttons["Discard scan"].isHittable)
        XCTAssertFalse(app.segmentedControls["CaptureModeToggle"].buttons["Describe"].exists)
        let toolbar = app.otherElements["CaptureObservationToolbar"]
        let closedBounds = toolbar.frame
        note.tap()
        let input = app.descendants(matching: .any)["DescribeTextInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 4))
        assertToolbarBounds(toolbar, match: closedBounds)
        input.tap(); input.typeText("Beside a pond")
        let title = app.staticTexts["FieldNotesTitle"]
        XCTAssertTrue(title.isHittable)
        XCTAssertEqual(title.label, "Field notes")
        XCTAssertGreaterThan(title.frame.height, 80, "Accessibility heading must wrap rather than truncate")
        let viewport = app.scrollViews["FieldNotesContent"].frame
        XCTAssertTrue(input.isHittable)
        XCTAssertGreaterThanOrEqual(input.frame.height, 44)
        XCTAssertGreaterThanOrEqual(input.frame.minY, viewport.minY - 1)
        XCTAssertLessThanOrEqual(input.frame.maxY, viewport.maxY + 1)
        XCTAssertEqual(input.value as? String, "Beside a pond")
        XCTAssertTrue(identify.isHittable)
        XCTAssertLessThanOrEqual(identify.frame.maxY, app.keyboards.firstMatch.frame.minY)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Field notes and whole-observation action at accessibility text size"
        attachment.lifetime = .keepAlways; add(attachment)
        let continuation = "\nSmall green shape beside leaves.\nIt moved slowly."
        input.typeText(continuation)
        XCTAssertEqual(input.value as? String, "Beside a pond" + continuation)
        XCTAssertLessThanOrEqual(input.frame.maxY, app.scrollViews["FieldNotesContent"].frame.maxY + 1)
        let multiline = XCTAttachment(screenshot: app.screenshot())
        multiline.name = "Long Field notes retain visible final line and caret at accessibility size"
        multiline.lifetime = .keepAlways; add(multiline)
        app.buttons["FieldNotesClose"].tap()
        XCTAssertTrue(waitForDisappearance(app.keyboards.firstMatch))
        XCTAssertTrue(waitForDisappearance(app.buttons["FieldNotesClose"]))
        XCTAssertTrue(note.isHittable)
        assertToolbarBounds(toolbar, match: closedBounds)
        note.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 4))
        XCTAssertEqual(input.value as? String, "Beside a pond" + continuation)
        app.buttons["FieldNotesClose"].tap()
        XCTAssertTrue(identify.isHittable)
    }

    @MainActor
    func testWrappedReanalysisTrayKeepsEveryNodeAndActionVisible() throws {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: [
            "-seedStagedAudioReviewFlow", "-mockCaptureReviewLocation", "-seedWrappedStagedReanalysis",
            "-captureModeOrder", "audio,visual", "-hasShownCaptureNoteTip", "YES"
        ])
        let analyze = app.buttons["Reanalyze"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 8))
        XCTAssertTrue(analyze.isHittable)
        let note = app.buttons["CaptureFieldNotes"]
        XCTAssertTrue(note.isHittable)
        let first = app.buttons["Edit historical description 1"]
        let last = app.buttons["Edit historical description 7"]
        for index in 1...7 {
            let node = app.buttons["Edit historical description \(index)"]
            XCTAssertTrue(node.isHittable)
            XCTAssertGreaterThanOrEqual(node.frame.width, 48)
            XCTAssertGreaterThanOrEqual(node.frame.minX, 16)
            XCTAssertLessThanOrEqual(node.frame.maxX, app.frame.width - 16)
        }
        XCTAssertGreaterThan(last.frame.minY, first.frame.minY)
        XCTAssertGreaterThanOrEqual(analyze.frame.height, 44)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Wrapped historical evidence above Analyze and Discard"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Discard scan"].tap()
        XCTAssertTrue(app.alerts["Discard reanalysis?"].waitForExistence(timeout: 3))
        app.buttons["Keep editing"].tap()
        XCTAssertTrue(last.isHittable)
        XCTAssertTrue(analyze.isHittable)

        // Reanalysis has the same two physical slots as Pro, with one still open.
        // Exercise both capture surfaces so a hidden shutter cannot skip clearance coverage.
        let modeToggle = app.segmentedControls["CaptureModeToggle"]
        for mode in ["Record", "Scan"] {
            let segment = modeToggle.buttons[mode]
            segment.tap()
            XCTAssertTrue(waitForSelectedState(segment))
            let shutter = app.buttons["CaptureShutter"]
            XCTAssertTrue(shutter.isHittable, "Capture must remain available in \(mode)")
            XCTAssertGreaterThanOrEqual(first.frame.minY - 8 - shutter.frame.maxY, 15)
            XCTAssertTrue(analyze.isHittable)
            XCTAssertTrue(app.buttons["Discard scan"].isHittable)
        }
        XCTAssertFalse(modeToggle.buttons["Describe"].exists)
        XCTAssertTrue(note.isHittable)
    }

    @MainActor
    func testFieldNotesReviewAndConfirmedDiscard() throws {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: [
            "-seedStagedAudioReviewFlow", "-mockCaptureReviewLocation", "-autoSubmitScans", "NO",
            "-captureModeOrder", "audio,visual", "-hasShownCaptureNoteTip", "YES",
            "-seedCaptureGoalIndicatorFlow"
        ])
        let note = app.buttons["CaptureFieldNotes"], audio = app.buttons["StagedAudioBadge_0"]
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        note.tap()
        let input = app.descendants(matching: .any)["DescribeTextInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 4))
        input.tap(); input.typeText("A small green beetle")
        app.buttons["FieldNotesClose"].tap()
        XCTAssertTrue(waitForDisappearance(app.keyboards.firstMatch))
        XCTAssertTrue(audio.isHittable)
        XCTAssertTrue(app.buttons["Identify"].isEnabled)
        app.buttons["Discard scan"].tap()
        let alert = app.alerts["Discard observation?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["Keep editing"].tap()
        note.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 4))
        XCTAssertEqual(input.value as? String, "A small green beetle")
        app.buttons["FieldNotesClose"].tap()
        XCTAssertTrue(waitForDisappearance(app.buttons["FieldNotesClose"]))
        app.buttons["Discard scan"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["Discard"].tap()
        XCTAssertTrue(waitForDisappearance(audio))
        XCTAssertFalse(note.exists)
        XCTAssertFalse(app.buttons["Identify"].exists)
        XCTAssertFalse(app.buttons["Discard scan"].exists)
        XCTAssertTrue(app.buttons["Record audio"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["activeCaptureGoalArtworkToggle"].waitForExistence(timeout: 4))
        app.segmentedControls["CaptureModeToggle"].buttons["Scan"].tap()
        XCTAssertTrue(app.buttons["activeCaptureGoalArtworkToggle"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["Discard scan"].exists)
    }

    @MainActor
    func testFieldNotesTextAreaFocusesFromLowerRegion() throws {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: [
            "-seedStagedAudioReviewFlow", "-mockCaptureReviewLocation", "-hasShownCaptureNoteTip", "YES"
        ])
        let notes = app.buttons["CaptureFieldNotes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 8)); notes.tap()
        let textArea = app.descendants(matching: .any)["DescribeTextArea"]
        let input = app.descendants(matching: .any)["DescribeTextInput"]
        XCTAssertTrue(textArea.waitForExistence(timeout: 4))
        XCTAssertTrue(input.waitForExistence(timeout: 4))
        // The editor scrolls at compact heights. Tap its visible lower region,
        // rather than a clipped portion of its full accessibility frame.
        let visibleArea = textArea.frame.intersection(app.scrollViews["FieldNotesContent"].frame)
        XCTAssertGreaterThanOrEqual(visibleArea.height, 44)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: visibleArea.midX, dy: visibleArea.minY + visibleArea.height * 0.8
        )).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))
        input.typeText("Small green shape")
        expectation(for: NSPredicate(format: "value == %@", "Small green shape"), evaluatedWith: input)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.buttons["Identify"].isHittable)
    }

    @MainActor
    func testFieldNotesDragsFromToolbarAndPreservesNotesOnDismissal() throws {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: [
            "-seedStagedAudioReviewFlow", "-mockCaptureReviewLocation", "-autoSubmitScans", "NO",
            "-hasShownCaptureNoteTip", "YES", "-hasShownCaptureSubmitTip", "YES"
        ])
        let notes = app.buttons["CaptureFieldNotes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 8))
        let toolbar = app.otherElements["CaptureObservationToolbar"]
        XCTAssertTrue(toolbar.waitForExistence(timeout: 4))
        let closedBounds = toolbar.frame
        XCTAssertEqual(notes.frame.width, 58, accuracy: 1)
        XCTAssertEqual(closedBounds.height, 88, accuracy: 1)
        let origin = toolbar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 8))
        origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: -100)))
        let close = app.buttons["FieldNotesClose"], title = app.staticTexts["FieldNotesTitle"]
        XCTAssertTrue(close.waitForExistence(timeout: 4))
        let input = app.descendants(matching: .any)["DescribeTextInput"]
        XCTAssertTrue(input.isHittable)
        assertToolbarBounds(toolbar, match: closedBounds)
        let viewport = app.scrollViews["FieldNotesContent"].frame
        XCTAssertGreaterThanOrEqual(input.frame.minY, viewport.minY - 1)
        XCTAssertLessThanOrEqual(input.frame.maxY, viewport.maxY + 1, "Initial sheet fits the complete editor")
        XCTAssertEqual(app.buttons.matching(identifier: "Identify").count, 1)
        XCTAssertLessThan(app.buttons["FieldNotesPrompts"].frame.maxY, viewport.minY)
        let opened = XCTAttachment(screenshot: app.screenshot())
        opened.name = "Field notes expands from toolbar with fixed header and complete editor"
        opened.lifetime = .keepAlways; add(opened)
        let restingInputHeight = input.frame.height
        let expand = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        expand.press(forDuration: 0.05, thenDragTo: expand.withOffset(CGVector(dx: 0, dy: -90)))
        XCTAssertGreaterThan(input.frame.height, restingInputHeight,
                             "Expanding the panel gives the input its remaining space")
        assertToolbarBounds(toolbar, match: closedBounds)
        let expandedViewport = app.scrollViews["FieldNotesContent"].frame
        XCTAssertLessThanOrEqual(input.frame.maxY, expandedViewport.maxY + 1)
        XCTAssertLessThanOrEqual(expandedViewport.maxY - input.frame.maxY, 16,
                                 "The expanded input should not leave a large gap above the toolbar")
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "Expanded Field notes fills its body with the notes input"
        expanded.lifetime = .keepAlways; add(expanded)
        input.tap(); input.typeText("Near the fallen branch")
        XCTAssertTrue(app.buttons["Identify"].isHittable)
        let prompt = app.staticTexts["What did you notice?"]
        XCTAssertTrue(prompt.isHittable, "Normal keyboard layout retains the prompt above the editor")
        XCTAssertGreaterThanOrEqual(prompt.frame.minY, app.scrollViews["FieldNotesContent"].frame.minY - 1)
        XCTAssertEqual(toolbar.frame.width, closedBounds.width, accuracy: 1)
        XCTAssertEqual(toolbar.frame.height, closedBounds.height, accuracy: 1)
        XCTAssertLessThanOrEqual(toolbar.frame.maxY, app.keyboards.firstMatch.frame.minY)
        let keyboard = XCTAttachment(screenshot: app.screenshot())
        keyboard.name = "Keyboard fits prompt cards and editor above shared toolbar"
        keyboard.lifetime = .keepAlways; add(keyboard)
        let header = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        header.press(forDuration: 0.05, thenDragTo: header.withOffset(CGVector(dx: 0, dy: 180)))
        XCTAssertTrue(waitForDisappearance(close), "Dragging the header dismisses notes, including with keyboard open")
        XCTAssertTrue(waitForDisappearance(app.keyboards.firstMatch))
        XCTAssertTrue(notes.isHittable)
        assertToolbarBounds(toolbar, match: closedBounds)
        notes.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 4))
        XCTAssertEqual(input.value as? String, "Near the fallen branch")
        let grabber = close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grabber.press(forDuration: 0.05, thenDragTo: grabber.withOffset(CGVector(dx: 0, dy: 160)))
        XCTAssertTrue(waitForDisappearance(close))
        notes.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 4))
        XCTAssertEqual(input.value as? String, "Near the fallen branch")
        close.tap()
        XCTAssertTrue(waitForDisappearance(close))
    }

    @MainActor
    func testFieldNotesOpensPromptsWithoutDescribeWorkspace() throws {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: [
            "-seedStagedAudioReviewFlow", "-mockCaptureReviewLocation",
            "-captureModeOrder", "describe,visual,audio", "-hasShownCaptureNoteTip", "YES"
        ])
        let notes = app.buttons["CaptureFieldNotes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 8))
        XCTAssertFalse(app.segmentedControls["CaptureModeToggle"].buttons["Describe"].exists)
        notes.tap()
        let prompts = app.buttons["FieldNotesPrompts"], dictation = app.buttons["FieldNotesDictation"]
        XCTAssertTrue(prompts.waitForExistence(timeout: 4))
        XCTAssertTrue(dictation.isHittable)
        XCTAssertEqual(prompts.frame.midY, dictation.frame.midY, accuracy: 1)
        // AX converts screen coordinates through floating-point transforms.
        // Tolerate only arithmetic noise, never a visibly smaller target.
        for control in [prompts, dictation, app.buttons["FieldNotesClose"]] {
            XCTAssertGreaterThanOrEqual(control.frame.width, 44 - 1e-6)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44 - 1e-6)
        }
        XCTAssertTrue(app.buttons["Identify"].isHittable)
        prompts.tap()
        let back = app.buttons["FieldNotesPromptsBack"], reset = app.buttons["FieldNotesReset"]
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        XCTAssertTrue(reset.isHittable)
        XCTAssertEqual(back.frame.midY, reset.frame.midY, accuracy: 1)
        XCTAssertFalse(dictation.exists)
        XCTAssertFalse(prompts.exists)
        XCTAssertTrue(app.buttons["FieldNotesPrompt_0"].isSelected)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Field notes single prompts toolbar and neutral rows"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["FieldNotesPrompt_1"].tap()
        XCTAssertTrue(prompts.waitForExistence(timeout: 4))
        prompts.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["FieldNotesPrompt_1"].isSelected)
        back.tap()
        XCTAssertTrue(prompts.waitForExistence(timeout: 4))
        XCTAssertTrue(dictation.isHittable)
        XCTAssertTrue(app.buttons["Identify"].isHittable)
        let input = app.descendants(matching: .any)["DescribeTextInput"]
        input.tap(); input.typeText("Synthetic notes to reset")
        prompts.tap()
        XCTAssertTrue(reset.waitForExistence(timeout: 4))
        reset.tap()
        XCTAssertTrue(dictation.waitForExistence(timeout: 4))
        XCTAssertEqual(input.value as? String, "")
        prompts.tap()
        XCTAssertTrue(app.buttons["FieldNotesPrompt_0"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["FieldNotesPrompt_0"].isSelected)
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
        // A loaded hosted simulator can spend longer than four seconds taking
        // one accessibility snapshot. This is a synchronization budget, not a
        // phrase-cadence assertion: the manual fixture publishes on each tap.
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 30.0),
            .completed,
            "Expected analyzing label \(label); observed \(element.label)",
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

        let scansButton = app.buttons["MainTabBar_Naturebook"]
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

        let scansButton = app.buttons["MainTabBar_Naturebook"]
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
    func testBetaOpenAIResumePreservesPausedScanWithoutConsentUI() throws {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-seedQueuedRetryPresentationFlow", "-seedOpenAIPermissionFlow"]
        )
        let scansButton = app.buttons["MainTabBar_Naturebook"]
        XCTAssertTrue(scansButton.waitForExistence(timeout: 8))
        scansButton.tap()
        let tile = app.buttons["QueuedScanTile_ui_test_queued_retry_attention"]
        XCTAssertTrue(tile.waitForExistence(timeout: 8))
        tile.tap()

        XCTAssertTrue(app.buttons["Retry now"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Your scan is saved and paused")
        ).firstMatch.exists)
        XCTAssertFalse(app.buttons["Review permission"].exists)
        XCTAssertFalse(app.buttons["Settings_OpenAIProcessing"].exists)
        XCTAssertFalse(app.staticTexts["Permission needed"].exists)
        // Opening the historical pause never submits or removes it. Explicit
        // retry's durable transition is covered by OfflineQueueOpenAIPermissionTests.
        app.buttons["Back"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 4))
        tile.tap()
        XCTAssertTrue(app.buttons["Retry now"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testQueuedAudioScanRetainsAudioAcrossCompletionHandoff() throws {
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedQueuedAudioHandoffFlow"])

        let scansButton = app.buttons["MainTabBar_Naturebook"]
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

        let boostButton = app.buttons["Boost audio"]
        XCTAssertTrue(boostButton.waitForExistence(timeout: 8.0))
        let audioControls = XCTAttachment(screenshot: app.screenshot())
        audioControls.name = "Queued audio controls before completion"
        audioControls.lifetime = .keepAlways
        add(audioControls)
        XCTAssertTrue(boostButton.isHittable, "Boost must be tappable while the scan is analyzing")
        boostButton.tap()
        let boostedButton = app.buttons["Turn off audio boost"]
        XCTAssertTrue(
            boostedButton.waitForExistence(timeout: 8.0),
            "Boost did not prepare a playable source while the scan was analyzing"
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
            boostedButton.waitForExistence(timeout: 8.0),
            "Boost selection did not survive analysis completion"
        )
        boostedButton.tap()
        XCTAssertTrue(
            boostButton.waitForExistence(timeout: 8.0),
            "The completed scan could not return to original audio"
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

        let scansButton = app.buttons["MainTabBar_Naturebook"]
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

        let scansButton = app.buttons["MainTabBar_Naturebook"]
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
    func testBackgroundInterruptionPreservesQueuedAudioInsight() throws {
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedQueuedAudioHandoffFlow"])
        defer { app.terminate() }
        let scans = app.buttons["MainTabBar_Naturebook"]
        XCTAssertTrue(scans.waitForExistence(timeout: 8))
        scans.tap()
        let tile = app.buttons["QueuedScanTile_ui_test_queued_audio_handoff"]
        XCTAssertTrue(tile.waitForExistence(timeout: 8))
        tile.tap()
        let insight = app.otherElements["InsightSheetView"]
        let audio = app.buttons["AudioPlaybackControl_ui_test_queued_audio_handoff.wav"]
        XCTAssertTrue(insight.waitForExistence(timeout: 8))
        XCTAssertTrue(audio.waitForExistence(timeout: 8))

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 8))
        app.activate()
        XCTAssertTrue(insight.waitForExistence(timeout: 8))
        XCTAssertTrue(audio.waitForExistence(timeout: 8))
        app.buttons["Back"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 8))
        tile.tap()
        XCTAssertTrue(insight.waitForExistence(timeout: 8))
        XCTAssertTrue(audio.waitForExistence(timeout: 8))
    }
}
