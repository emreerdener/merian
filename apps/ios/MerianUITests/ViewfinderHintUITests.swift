import XCTest

final class ViewfinderHintUITests: XCTestCase {
    @MainActor
    func testIntroductionWaitsForLaunchSheetsAndDoesNotReplayAfterExplore() {
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: [
            "-seedWhatsNewLaunch", "-opensExploreOnLaunch", "YES",
            "-captureModeOrder", "visual,audio,describe",
            "-keepViewfinderHintVisible"
        ])
        let announcement = app.buttons["WhatsNew_Close"]
        XCTAssertTrue(announcement.waitForExistence(timeout: 8))
        let identify = app.staticTexts["Tap to identify"]
        XCTAssertFalse(identify.exists, "The introduction must not begin behind What's New")
        announcement.tap()
        let closeExplore = app.buttons["ExploreCloseButton"]
        XCTAssertTrue(closeExplore.waitForExistence(timeout: 8))
        XCTAssertFalse(identify.exists, "The introduction must not begin behind launch-time Explore")
        closeExplore.tap()
        XCTAssertTrue(identify.waitForExistence(timeout: 5))
        let hint = app.descendants(matching: .any)["ViewfinderHint"].firstMatch
        let shutter = app.buttons["CaptureShutter"]
        XCTAssertGreaterThanOrEqual(shutter.frame.minY - hint.frame.maxY, 8)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "First visible camera introduction"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["MainTabBar_Explore"].tap()
        XCTAssertTrue(closeExplore.waitForExistence(timeout: 5))
        closeExplore.tap()
        let cameraReturned = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: shutter
        )
        XCTAssertEqual(XCTWaiter.wait(for: [cameraReturned], timeout: 5), .completed)
        XCTAssertFalse(identify.exists, "Closing Explore again must not replay the introduction")
        XCTAssertFalse(app.staticTexts["Hold to record video"].exists)
    }

    @MainActor
    func testPhotoPermissionSheetInterruptsIntroductionWithoutReplay() {
        let app = UITestAppLauncher.makeConfiguredApp(extraArguments: [
            "-seedWhatsNewLaunch", "-opensExploreOnLaunch", "NO",
            "-captureModeOrder", "visual,audio,describe", "-keepViewfinderHintVisible"
        ])
        app.resetAuthorizationStatus(for: .photos)
        app.launch()
        let close = app.buttons["WhatsNew_Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        close.tap()
        let identify = app.staticTexts["Tap to identify"]
        XCTAssertTrue(identify.waitForExistence(timeout: 5))
        app.buttons["PhotoLibraryButton"].tap()
        let skip = app.buttons["Skip for now"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertFalse(identify.exists)
        skip.tap()
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: app.buttons["CaptureShutter"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        XCTAssertFalse(identify.exists)
    }

    @MainActor
    func testIntroductionExpiresOnFirstCameraVisit() {
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: [
            "-seedWhatsNewLaunch", "-opensExploreOnLaunch", "NO",
            "-captureModeOrder", "visual,audio,describe"
        ])
        let close = app.buttons["WhatsNew_Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        close.tap()
        let identify = app.staticTexts["Tap to identify"]
        XCTAssertTrue(identify.waitForExistence(timeout: 5))
        let expired = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: identify
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expired], timeout: 6), .completed)
    }
}
