import XCTest

@MainActor final class IdentificationHistoryUITests: XCTestCase {
    func testProtectedReanalysisFailureKeepsSavedScanWithoutLegacyFallback() {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedPrivateScanMapFlow", "-seedSavedReanalysisFailure"])
        defer { app.terminate() }
        let scans = app.segmentedControls.buttons["Scans"]
        if !scans.waitForExistence(timeout: 5) {
            let entry = app.buttons["MainTabBar_Naturebook"]
            XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        }
        XCTAssertTrue(scans.waitForExistence(timeout: 10)); scans.tap()
        let tile = app.buttons["ScanTile_00000000-0000-4000-8000-000000000004"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10)); tile.tap()
        let identification = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Map Meadowlark", "Sturnella magna"])).firstMatch
        XCTAssertTrue(identification.waitForExistence(timeout: 10))
        let menu = app.buttons["InsightTopMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        openIdentificationFromMenu(app)
        let reanalyze = app.buttons["ReanalyzeSpeciesMenu"]
        XCTAssertTrue(reanalyze.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "ReanalyzeSpeciesMenu").count, 1)
        XCTAssertFalse(app.buttons["Identification history"].exists)
        reanalyze.tap()
        let error = app.staticTexts["Reanalysis couldn’t be opened. Your identification is unchanged. Try again."]
        XCTAssertTrue(error.waitForExistence(timeout: 5), "Protected failure must reach its error, not a paywall or refinement.")
        XCTAssertTrue(menu.exists && identification.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Protected reanalysis failure preserves saved scan"; shot.lifetime = .keepAlways; add(shot)
    }

    func testProtectedConfidenceReanalysisDismissesChildWithoutLegacyFallback() {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedPrivateScanMapFlow", "-seedSavedReanalysisFailure"])
        defer { app.terminate() }
        let scans = app.segmentedControls.buttons["Scans"]
        if !scans.waitForExistence(timeout: 5) {
            let entry = app.buttons["MainTabBar_Naturebook"]
            XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        }
        XCTAssertTrue(scans.waitForExistence(timeout: 10)); scans.tap()
        let tile = app.buttons["ScanTile_00000000-0000-4000-8000-000000000004"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10)); tile.tap()
        let badge = app.buttons["Strong match"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10)); badge.tap()
        XCTAssertTrue(app.buttons["IdentificationActionsMenu"].waitForExistence(timeout: 10))
        app.buttons["IdentificationActionsMenu"].tap()
        let reanalyze = app.buttons["ReanalyzeSpeciesMenu"]
        XCTAssertTrue(reanalyze.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: reanalyze)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        reanalyze.tap()
        XCTAssertTrue(app.staticTexts["Reanalysis couldn’t be opened. Your identification is unchanged. Try again."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["InsightTopMenu"].exists)
        XCTAssertTrue(app.staticTexts["Map Meadowlark"].exists)
        XCTAssertFalse(reanalyze.exists, "Only the child explanation closes; the saved Insight remains.")
    }

    func testHistoryPreviewRestoreAndUndoKeepBothEntries() {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedPrivateScanMapFlow", "-seedIdentificationHistory"])
        defer { app.terminate() }
        let scans = app.segmentedControls.buttons["Scans"]
        // Prefer the seed's route when it is already presented; otherwise use
        // the visible root entry, as the other private-library UI flows do.
        if !scans.waitForExistence(timeout: 5) {
            let entry = app.buttons["MainTabBar_Naturebook"]
            XCTAssertTrue(entry.waitForExistence(timeout: 10))
            XCTAssertTrue(entry.isHittable)
            entry.tap()
        }
        XCTAssertTrue(scans.waitForExistence(timeout: 10)); scans.tap()
        let tile = app.buttons["ScanTile_private_map_bird"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10)); tile.tap()
        let identification = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Map Meadowlark", "Sturnella magna"])).firstMatch
        XCTAssertTrue(identification.waitForExistence(timeout: 10), "The saved scan must finish binding before opening its actions.")
        let menu = app.buttons["InsightTopMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        let entry = app.buttons["IdentificationMenu"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        capture(app, "Insights menu")
        entry.tap()
        let actions = app.buttons["IdentificationActionsMenu"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["IdentificationConfirm"].waitForExistence(timeout: 5),
                      "An unreviewed strong identification must offer confirmation even without alternatives.")
        XCTAssertTrue(app.buttons["IdentificationIncorrect"].exists)
        capture(app, "Identification sheet")
        actions.tap()
        let history = app.buttons["IdentificationHistoryMenu"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        capture(app, "Identification menu")
        history.tap()
        let second = UITestAppLauncher.historyCard(app, id: "00000000-0000-4000-8000-000000000003")
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["HistoryConfirmPrimary"].waitForExistence(timeout: 5))
        capture(app, "History sheet")
        UITestAppLauncher.openHistoryActions(app, id: "00000000-0000-4000-8000-000000000002")
        XCTAssertTrue(app.buttons["HistoryReanalyze"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["HistoryCorrectMenu"].exists)
        XCTAssertFalse(app.buttons["HistoryIncorrectMenu"].exists)
        XCTAssertFalse(app.buttons["Review alternatives"].exists)
        XCTAssertFalse(app.buttons["Review decision"].exists)
        capture(app, "Current identification menu without duplicate review actions")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        UITestAppLauncher.openHistoryActions(app, id: "00000000-0000-4000-8000-000000000003")
        XCTAssertTrue(app.buttons["HistoryCorrectMenu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["HistoryIncorrectMenu"].exists)
        XCTAssertFalse(app.buttons["Review alternatives"].exists)
        XCTAssertFalse(app.buttons["Review decision"].exists)
        capture(app, "Older identification review actions")
        let restore = app.buttons["HistoryRestore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        let actionable = NSPredicate(format: "hittable == true AND enabled == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: actionable, object: restore)], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["HistoryUndo"].exists)
        restore.tap()
        let selected = NSPredicate(format: "label CONTAINS %@", "Current")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: second)], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["HistoryUndo"].exists, "Selection Undo belongs in the top-level menu, not below the cards.")
        XCTAssertTrue(UITestAppLauncher.historyCard(app, id: "00000000-0000-4000-8000-000000000002").exists)
        XCTAssertTrue(second.exists)
        XCTAssertTrue(second.label.contains("Current"))
        XCTAssertLessThan(second.frame.minY, UITestAppLauncher.historyCard(app, id: "00000000-0000-4000-8000-000000000002").frame.minY)
        app.buttons["HistorySheetActions"].tap()
        let undo = app.buttons["HistoryUndo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        let original = UITestAppLauncher.historyCard(app, id: "00000000-0000-4000-8000-000000000002")
        // Selection Undo is delivered asynchronously, just like Use identification.
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: original)], timeout: 5), .completed)
        XCTAssertFalse(second.label.contains("Current"))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Identification history after Undo"; shot.lifetime = .keepAlways; add(shot)
        UITestAppLauncher.closeHistory(app)
        XCTAssertFalse(app.otherElements["IdentificationHistorySheet"].exists)
    }
    private func openIdentificationFromMenu(_ app: XCUIApplication) {
        let entry = app.buttons["IdentificationMenu"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        let actions = app.buttons["IdentificationActionsMenu"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5)); actions.tap()
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

}
