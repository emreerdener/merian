import XCTest

@MainActor final class PublicationConsentUITests: XCTestCase {
    func testSelectedBroaderTaxonNameConfirmationPersistsExactReview() {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedPublicationConsentChooser", "-seedSelectedNameConfirmation"])
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
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        let action = app.buttons["Confirm species name"]
        let initialMenu = XCTAttachment(screenshot: app.screenshot())
        initialMenu.name = "Broader identification review menu"; initialMenu.lifetime = .keepAlways; add(initialMenu)
        XCTAssertTrue(action.waitForExistence(timeout: 5)); action.tap()
        let confirm = app.buttons["SelectedReviewConfirmName"], name = app.textFields["SelectedReviewSpeciesName"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); XCTAssertFalse(confirm.isEnabled)
        XCTAssertTrue(name.exists)
        // Closing an untouched form leaves the retained host available.
        app.buttons["Done"].tap(); menu.tap()
        XCTAssertTrue(action.waitForExistence(timeout: 5)); action.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Danaus plexippus")
        XCTAssertTrue(confirm.isEnabled); confirm.tap()
        let status = app.staticTexts["SelectedReviewNameStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5)); XCTAssertTrue(status.label.contains("Review pending"))
        XCTAssertFalse(confirm.isEnabled)
        // The fixture wake verifies the real outbox's exact target, name and revisions.
        app.buttons["Done"].tap(); menu.tap()
        XCTAssertFalse(action.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Selected broader identification retains pending named review"
        shot.lifetime = .keepAlways; add(shot)
    }

    func testExplicitPhotoOrderPersistsAndReopeningCannotReplaceRequest() {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedPublicationConsentChooser"])
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
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        let ask = app.buttons["Ask the community"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5)); ask.tap()
        let choose = app.buttons["CommunityChoosePhotos"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10)); choose.tap()
        let confirm = app.buttons["CommunityConfirmPhotos"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); XCTAssertFalse(confirm.isEnabled)
        let second = app.buttons["CommunityPhoto_1"], first = app.buttons["CommunityPhoto_0"]
        XCTAssertTrue(second.exists && first.exists)
        second.tap(); first.tap()
        XCTAssertEqual(confirm.label, "Share 2 photos with the community")
        let preview = app.buttons["Preview photo 2"]
        XCTAssertTrue(preview.exists); preview.tap()
        XCTAssertTrue(app.images["Saved evidence photo"].waitForExistence(timeout: 10))
        if !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.isHittable); confirm.tap()
        // The Debug network boundary's wake also verifies the real outbox has
        // one request with [second, first], no notes, and unchanged selection.
        XCTAssertTrue(app.staticTexts["Waiting to send"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); menu.tap(); ask.tap()
        let occupied = app.staticTexts["Request on this device: Waiting to send"]
        XCTAssertTrue(occupied.waitForExistence(timeout: 10))
        XCTAssertFalse(choose.exists); XCTAssertFalse(confirm.exists)
        app.buttons["Done"].tap(); menu.tap()
        let history = app.buttons["Identification history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
        let current = app.buttons["HistoryRow_00000000-0000-4000-8000-000000000004"]
        XCTAssertTrue(current.waitForExistence(timeout: 10)); XCTAssertTrue(current.label.contains("Current"))
        let historical = app.buttons["HistoryRow_00000000-0000-4000-8000-000000000002"]
        XCTAssertTrue(historical.exists); historical.tap()
        let historyAsk = app.buttons["Ask the community"]
        XCTAssertTrue(historyAsk.waitForExistence(timeout: 5)); historyAsk.tap()
        XCTAssertTrue(occupied.waitForExistence(timeout: 10))
        XCTAssertFalse(choose.exists); XCTAssertFalse(confirm.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Community request retains exact consent across entry points"
        shot.lifetime = .keepAlways; add(shot)
    }
}
