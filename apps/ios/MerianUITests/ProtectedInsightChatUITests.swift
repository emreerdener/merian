import XCTest

@MainActor extension merianUITests {
    func testExactQuestionPersistsAndReopeningKeepsPendingIdentity() {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedProtectedInsightChat"])
        defer { app.terminate() }
        let scans = app.segmentedControls.buttons["Scans"]
        if !scans.waitForExistence(timeout: 5) {
            let entry = app.buttons["MainTabBar_Scans"]
            XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        }
        XCTAssertTrue(scans.waitForExistence(timeout: 10)); scans.tap()
        let tile = app.buttons["ScanTile_00000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10)); tile.tap()
        XCTAssertTrue(app.staticTexts["Consent Butterfly"].waitForExistence(timeout: 10))
        let chat = app.buttons["FieldChatToolbarButton"]
        tapChat(chat, in: app)
        let send = app.buttons["ProtectedChatSend"]
        XCTAssertTrue(send.waitForExistence(timeout: 10)); XCTAssertFalse(send.isEnabled)
        let question = app.textFields["ProtectedChatQuestion"]
        XCTAssertTrue(question.waitForExistence(timeout: 5)); question.tap()
        question.typeText("What does this identification mean?")
        XCTAssertTrue(send.isEnabled); send.tap()
        let saved = app.buttons["ProtectedChatSendSaved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertFalse(send.exists)
        XCTAssertTrue(app.staticTexts["What does this identification mean?"].exists)
        app.buttons["Done"].tap()
        tapChat(chat, in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: 10)); XCTAssertFalse(send.exists)
        // The injected boundary reads real persistence and checks the original
        // identity, displayed revisions, exact text and unchanged selection again.
        saved.tap()
        XCTAssertTrue(saved.exists); XCTAssertFalse(send.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Protected chat retains original pending question after reopening"
        shot.lifetime = .keepAlways; add(shot)
    }

    private func tapChat(_ chat: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(chat.waitForExistence(timeout: 10)); XCTAssertTrue(chat.isEnabled)
        XCTAssertTrue(app.frame.contains(chat.frame), chat.debugDescription)
        // iOS 27 reports a zero-sized ancestor for this native bottom toolbar.
        // Use the visible control's measured center, never a fixed screen point.
        // The following composer assertions still require the real action to run.
        chat.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

}
