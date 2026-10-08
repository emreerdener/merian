import XCTest

@MainActor final class AudioReanalysisSheetUITests: XCTestCase {
    func testPreparedInputAndDurableRequestSurviveReopening() {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedAudioReanalysisSheet"])
        defer { app.terminate() }
        let open = app.buttons["AudioFixtureOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 15)); open.tap()
        let ready = app.descendants(matching: .any)["AudioReanalysisReady"].firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["AudioReanalysisSubmit"].isEnabled)
        app.buttons["AudioReanalysisDone"].tap()
        XCTAssertTrue(ready.waitForNonExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(ready.waitForExistence(timeout: 10))
        app.buttons["AudioReanalysisSubmit"].tap()
        let message = app.staticTexts["AudioReanalysisMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.contains("same request"))
        XCTAssertFalse(app.buttons["AudioReanalysisChoose"].exists)
        app.buttons["AudioReanalysisDone"].tap()
        let saved = app.staticTexts["AudioFixtureSavedIdentity"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        let identity = saved.label
        XCTAssertNotNil(UUID(uuidString: identity))
        open.tap()
        let resume = app.buttons["AudioReanalysisContinue"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap()
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Reopened audio submission retains original durable request"
        screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["AudioReanalysisDone"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.label, identity)
    }
}
