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

    func testConsumedSavedRequestReopensWithoutFilesConsentOrReplacement() {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedAudioReanalysisSheet"])
        defer { app.terminate() }
        let open = app.buttons["AudioFixtureOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 15)); open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["AudioReanalysisReady"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["AudioReanalysisSubmit"].tap()
        XCTAssertTrue(app.staticTexts["AudioReanalysisMessage"].waitForExistence(timeout: 10))
        app.buttons["AudioReanalysisDone"].tap()
        let identity = app.staticTexts["AudioFixtureSavedIdentity"]
        XCTAssertTrue(identity.waitForExistence(timeout: 5))
        let original = identity.label
        XCTAssertNotNil(UUID(uuidString: original))
        let counts = app.staticTexts["AudioFixtureCounts"]
        XCTAssertEqual(counts.label, "1:1:0")
        app.buttons["AudioFixtureConsume"].tap()
        XCTAssertEqual(identity.label, original)
        let savedOpen = app.buttons["AudioFixtureSavedOpen"]
        savedOpen.tap()
        let row = app.buttons["SavedAudioRow_" + original]
        let action = app.buttons["SavedAudioContinue"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); XCTAssertFalse(action.isEnabled)
        app.buttons["SavedAudioDone"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5)); XCTAssertEqual(counts.label, "1:1:0")
        for expected in ["1:1:1", "1:1:2"] {
            savedOpen.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 10)); XCTAssertFalse(action.isEnabled)
            row.tap(); XCTAssertEqual(action.label, "Check saved result")
            app.buttons["SavedAudioPreview"].tap()
            let unavailable = app.staticTexts["SavedAudioMessage"]
            XCTAssertTrue(unavailable.waitForExistence(timeout: 10))
            XCTAssertTrue(unavailable.label.contains("saved audio is unavailable"))
            action.tap()
            let recovery = app.staticTexts["SavedAudioRecoveryMessage"]
            XCTAssertTrue(recovery.waitForExistence(timeout: 10))
            let absent = NSPredicate(format: "label == %@", "We haven’t been able to recover your result yet.")
            expectation(for: absent, evaluatedWith: recovery)
            waitForExpectations(timeout: 10)
            XCTAssertTrue(app.staticTexts["SavedAudioConnectivity"].label.contains("internet connection"))
            app.buttons["SavedAudioDone"].tap()
            XCTAssertTrue(row.waitForNonExistence(timeout: 5))
            XCTAssertEqual(counts.label, expected); XCTAssertEqual(identity.label, original)
        }
        savedOpen.tap(); XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        app.buttons["AudioFixtureLoseAccount"].tap()
        XCTAssertTrue(action.waitForNonExistence(timeout: 5))
        app.buttons["SavedAudioDone"].tap()
        XCTAssertEqual(counts.label, "1:1:2"); XCTAssertEqual(identity.label, original)
    }

}
