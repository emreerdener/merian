import XCTest

@MainActor final class CandidateConfirmationUITests: XCTestCase {
    func testSelectedMenuConfirmsExactSavedCandidate() { exercise(.menu) }
    func testHistoryReturnToIdentificationConfirmsExactSavedCandidate() { exercise(.history) }
    func testConfidenceDismissalConfirmsExactSavedCandidate() { exercise(.confidence) }

    private enum Surface { case menu, history, confidence }
    private func exercise(_ surface: Surface) {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedPublicationConsentChooser", "-seedCandidateConfirmation"])
        defer { app.terminate() }
        let scans = app.segmentedControls.buttons["Scans"]
        if !scans.waitForExistence(timeout: 5) {
            let entry = app.buttons["MainTabBar_Naturebook"]
            XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        }
        XCTAssertTrue(scans.waitForExistence(timeout: 10)); scans.tap()
        let tile = app.buttons["ScanTile_00000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10)); tile.tap()
        XCTAssertTrue(app.staticTexts["Consent Butterfly"].waitForExistence(timeout: 10))
        let menu = app.buttons["InsightTopMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        switch surface {
        case .menu:
            UITestAppLauncher.openIdentification(app)
            openIdentificationAlternatives(app)
        case .history:
            UITestAppLauncher.openIdentification(app, history: true)
            let row = UITestAppLauncher.historyCard(app, id: "00000000-0000-4000-8000-000000000004")
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            UITestAppLauncher.closeHistory(app)
            UITestAppLauncher.openIdentification(app)
            openIdentificationAlternatives(app)
        case .confidence:
            let badge = app.buttons["Needs review"]
            XCTAssertTrue(badge.waitForExistence(timeout: 10)); badge.tap()
            openIdentificationAlternatives(app)
        }
        // Duplicate scientific names deliberately require the second raw ordinal.
        let confirm = app.buttons["CandidateConfirm_1"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        let list = app.scrollViews["CandidateReviewScroll"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        for _ in 0..<4 where !confirm.isHittable { list.swipeUp() }
        XCTAssertTrue(confirm.isHittable); confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 10))
        let deck = app.navigationBars["Review alternatives"]
        if deck.exists, deck.buttons["Done"].isHittable { deck.buttons["Done"].tap() }
        if app.buttons["HistorySheetActions"].exists { UITestAppLauncher.closeHistory(app) }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        UITestAppLauncher.openIdentification(app, history: true)
        let current = UITestAppLauncher.historyCard(app, id: "00000000-0000-4000-8000-000000000004")
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        XCTAssertTrue(current.label.contains("Limenitis archippus")); XCTAssertTrue(current.label.contains("Current"))
        XCTAssertTrue(app.buttons["HistoryUndoConfirmation"].waitForExistence(timeout: 10))
        // The boundary verifies the actual completed schema-2 operation/receipt,
        // exact ordinal, unchanged selection and byte-identical immutable snapshots.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Exact candidate confirmation completed"; shot.lifetime = .keepAlways; add(shot)
    }

    private func openIdentificationAlternatives(_ app: XCUIApplication) {
        let sheet = app.scrollViews["IdentificationSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        let action = sheet.buttons["Review alternatives"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        for _ in 0..<3 where !action.isHittable { sheet.swipeUp() }
        XCTAssertTrue(action.isHittable); action.tap()
    }
}
