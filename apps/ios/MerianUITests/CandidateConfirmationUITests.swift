import XCTest

@MainActor final class CandidateConfirmationUITests: XCTestCase {
    func testSelectedMenuConfirmsExactSavedCandidate() { exercise(.menu) }
    func testHistoryPreviewConfirmsExactSavedCandidate() { exercise(.history) }
    func testConfidenceDismissalConfirmsExactSavedCandidate() { exercise(.confidence) }

    private enum Surface { case menu, history, confidence }
    private func exercise(_ surface: Surface) {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedPublicationConsentChooser", "-seedCandidateConfirmation"])
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
        let menu = app.buttons["InsightTopMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        switch surface {
        case .menu:
            menu.tap()
            let action = app.collectionViews.buttons["Review alternatives"]
            XCTAssertTrue(action.waitForExistence(timeout: 10)); action.tap()
        case .history:
            menu.tap(); app.buttons["Identification history"].tap()
            let row = app.buttons["HistoryRow_00000000-0000-4000-8000-000000000004"]
            XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
            let action = app.buttons["HistoryReviewCandidates"]
            XCTAssertTrue(action.waitForExistence(timeout: 10))
            if !action.isHittable { app.swipeUp() }
            action.tap()
        case .confidence:
            let badge = app.buttons["Needs review"]
            XCTAssertTrue(badge.waitForExistence(timeout: 10)); badge.tap()
            let action = app.buttons["Review alternatives"].firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 10))
            if !action.isHittable { app.swipeUp() }
            action.tap()
        }
        if surface == .history {
            let deck = app.navigationBars["Review alternatives"]
            XCTAssertTrue(deck.waitForExistence(timeout: 10))
            deck.buttons["Done"].tap()
            let reopen = app.buttons["HistoryReviewCandidates"]
            XCTAssertTrue(reopen.waitForExistence(timeout: 10)); reopen.tap()
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
        let historyDone = app.buttons["HistoryDone"]
        if historyDone.exists { historyDone.tap() }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        menu.tap(); app.buttons["Identification history"].tap()
        let current = app.buttons["HistoryRow_00000000-0000-4000-8000-000000000004"]
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        XCTAssertTrue(current.label.contains("Limenitis archippus")); XCTAssertTrue(current.label.contains("Current"))
        current.tap()
        XCTAssertTrue(app.buttons["HistoryUndoConfirmation"].waitForExistence(timeout: 10))
        // The boundary verifies the actual completed schema-2 operation/receipt,
        // exact ordinal, unchanged selection and byte-identical immutable snapshots.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Exact candidate confirmation completed"; shot.lifetime = .keepAlways; add(shot)
    }
}
