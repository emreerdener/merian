import XCTest

@MainActor final class IdentificationHistoryUITests: XCTestCase {
    func testProtectedReanalysisFailureKeepsSavedScanWithoutLegacyFallback() {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedPrivateScanMapFlow", "-seedSavedReanalysisFailure"])
        defer { app.terminate() }
        let scans = app.segmentedControls.buttons["Scans"]
        if !scans.waitForExistence(timeout: 5) {
            let entry = app.buttons["MainTabBar_Scans"]
            XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        }
        XCTAssertTrue(scans.waitForExistence(timeout: 10)); scans.tap()
        let tile = app.buttons["ScanTile_00000000-0000-4000-8000-000000000004"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10)); tile.tap()
        let identification = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Map Meadowlark", "Sturnella magna"])).firstMatch
        XCTAssertTrue(identification.waitForExistence(timeout: 10))
        let menu = app.buttons["InsightTopMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        let reanalyze = app.buttons["Reanalyze species"]
        XCTAssertTrue(reanalyze.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Reanalyze species").count, 1)
        XCTAssertFalse(app.buttons["Identification history"].exists)
        reanalyze.tap()
        let error = app.staticTexts["Reanalysis couldn’t be opened. Your identification is unchanged. Try again."]
        XCTAssertTrue(error.waitForExistence(timeout: 5), "Protected failure must reach its error, not a paywall or refinement.")
        XCTAssertTrue(menu.exists && identification.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Protected reanalysis failure preserves saved scan"; shot.lifetime = .keepAlways; add(shot)
    }

    func testHistoryPreviewRestoreAndUndoKeepBothEntries() {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedPrivateScanMapFlow", "-seedIdentificationHistory"])
        defer { app.terminate() }
        let scans = app.segmentedControls.buttons["Scans"]
        // Prefer the seed's route when it is already presented; otherwise use
        // the visible root entry, as the other private-library UI flows do.
        if !scans.waitForExistence(timeout: 5) {
            let entry = app.buttons["MainTabBar_Scans"]
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
        let history = app.buttons["Identification history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
        let second = app.buttons["HistoryRow_00000000-0000-4000-8000-000000000003"]
        XCTAssertTrue(second.waitForExistence(timeout: 5)); second.tap()
        let restore = app.buttons["HistoryRestore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["HistoryUndo"].exists)
        restore.tap()
        let undo = app.buttons["HistoryUndo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["HistoryRow_00000000-0000-4000-8000-000000000002"].exists)
        XCTAssertTrue(second.exists)
        XCTAssertTrue(second.label.contains("Current"))
        undo.tap()
        XCTAssertTrue(app.buttons["HistoryRow_00000000-0000-4000-8000-000000000002"].label.contains("Current"))
        XCTAssertFalse(second.label.contains("Current"))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Identification history after Undo"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["HistoryDone"].tap()
        XCTAssertFalse(app.otherElements["IdentificationHistorySheet"].exists)
    }
}
