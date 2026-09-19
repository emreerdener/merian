import XCTest

@MainActor
final class TopToolbarAppearanceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testScrolledLibraryAndPushedInsightToolbarAppearance() {
        let app = UITestAppLauncher.launchConfiguredApp(
            extraArguments: ["-seedPrivateScanMapFlow"]
        )
        defer { app.terminate() }

        let scans = app.segmentedControls.buttons["Scans"]
        XCTAssertTrue(scans.waitForExistence(timeout: 10))
        scans.tap()
        capture("Scans at top", app: app)
        app.swipeUp()
        XCTAssertTrue(scans.isHittable)
        capture("Scans scrolled", app: app)

        // Return to the known image-backed fixture; the stress rows have no media.
        app.swipeDown()
        let tile = app.buttons["ScanTile_private_map_bird"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertTrue(tile.isHittable)
        tile.tap()
        XCTAssertTrue(app.otherElements["InsightSheetView"].waitForExistence(timeout: 10))
        capture("Pushed Insight at top", app: app)
        app.swipeUp()
        XCTAssertTrue(app.buttons["Back"].isHittable)
        capture("Pushed Insight scrolled", app: app)
        app.buttons["Back"].tap()
        XCTAssertTrue(scans.waitForExistence(timeout: 5))
    }

    func testScrolledProfileAndSettingsToolbarAppearance() {
        let app = UITestAppLauncher.launchConfiguredApp()
        defer { app.terminate() }
        let profile = app.buttons["MainTabBar_Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()
        let settings = app.segmentedControls.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(settings.isHittable)
        capture("Profile scrolled", app: app)
        settings.tap()
        app.swipeUp()
        XCTAssertTrue(settings.isHittable)
        capture("Settings scrolled", app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
