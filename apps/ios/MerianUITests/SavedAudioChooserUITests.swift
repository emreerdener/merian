import XCTest

@MainActor final class SavedAudioChooserUITests: XCTestCase {
    func testExplicitSelectionStatusAndRefreshNeverAutoContinue() {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedSavedAudioChooser"])
        defer { app.terminate() }
        let action = app.buttons["SavedAudioContinue"]
        XCTAssertTrue(action.waitForExistence(timeout: 15))
        XCTAssertFalse(action.isEnabled)
        XCTAssertTrue(app.staticTexts["Original result needs checking"].exists)
        let consumed = app.buttons["SavedAudioRow_00000000-0000-4000-8000-000000000051"]
        XCTAssertTrue(consumed.exists); consumed.tap()
        XCTAssertTrue(action.isEnabled); XCTAssertEqual(action.label, "Check saved result")
        action.tap()
        let message = app.staticTexts["SavedAudioMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("same request"))
        let unconsumed = app.buttons["SavedAudioRow_00000000-0000-4000-8000-000000000052"]
        unconsumed.tap(); XCTAssertEqual(action.label, "Continue saved request")
        app.buttons["SavedAudioRefresh"].tap()
        XCTAssertTrue(consumed.waitForExistence(timeout: 5))
        XCTAssertFalse(action.isEnabled)
        XCTAssertFalse(message.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Saved audio chooser requires explicit request selection"
        screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["SavedAudioDone"].tap()
        XCTAssertTrue(action.waitForNonExistence(timeout: 5))
    }
}
