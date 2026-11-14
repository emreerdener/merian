import XCTest

final class WhatsNewUITests: XCTestCase {
    @MainActor
    func testLaunchDismissalRevealsMountedWorkspace() {
        continueAfterFailure = false
        for action in ["continue", "close", "swipe"] {
            let app = UITestAppLauncher.launchConfiguredApp(
                extraArguments: ["-seedWhatsNewLaunch", "-opensExploreOnLaunch", "NO"]
            )
            let title = app.staticTexts["WhatsNew_Title"]
            XCTAssertTrue(title.waitForExistence(timeout: 8))
            retainScreenshot(app, name: "Whats New over workspace — \(action)")

            switch action {
            case "continue":
                XCTAssertFalse(app.buttons["WhatsNew_Continue"].isHittable,
                               "Continue must scroll with the content, not remain fixed")
                scrollToContinue(in: app)
                let viewMore = app.buttons["WhatsNew_ViewMore"]
                XCTAssertTrue(viewMore.isHittable)
                XCTAssertLessThan(viewMore.frame.maxY, app.buttons["WhatsNew_Continue"].frame.minY)
                retainScreenshot(app, name: "What's New scrolling actions")
                viewMore.tap()
                let changelog = app.navigationBars["Changelog"]
                XCTAssertTrue(changelog.waitForExistence(timeout: 5))
                XCTAssertFalse(app.buttons["MainTabBar_Profile"].isHittable)
                retainScreenshot(app, name: "Changelog from What's New")
                changelog.buttons.firstMatch.tap()
                XCTAssertTrue(app.buttons["WhatsNew_Close"].waitForExistence(timeout: 5))
                scrollToContinue(in: app)
                app.buttons["WhatsNew_Continue"].tap()
            case "close":
                app.buttons["WhatsNew_Close"].tap()
            default:
                // Drag the sheet chrome, not a short title inside its ScrollView.
                let close = app.buttons["WhatsNew_Close"]
                let chrome = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: app.frame.midX, dy: close.frame.midY))
                chrome.press(forDuration: 0.1, thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)
                ))
            }

            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: title
            )
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
            let profile = app.buttons["MainTabBar_Profile"]
            XCTAssertTrue(profile.exists, "The workspace must already be mounted after dismissal")
            XCTAssertTrue(profile.isHittable)
            retainScreenshot(app, name: "Workspace after \(action)")
            app.terminate()
        }
    }

    @MainActor
    private func scrollToContinue(in app: XCUIApplication) {
        let button = app.buttons["WhatsNew_Continue"]
        for _ in 0..<8 {
            if button.isHittable { break }
            app.scrollViews["WhatsNew_Content"].swipeUp()
        }
        XCTAssertTrue(button.isHittable)
    }

    @MainActor
    private func retainScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
