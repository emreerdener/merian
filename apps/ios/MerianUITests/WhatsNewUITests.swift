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
    private func retainScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
