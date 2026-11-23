import XCTest

@MainActor final class PublicationConsentUITests: XCTestCase {
    func testPrimaryConfirmationUndoFromMenu() { exerciseConfirmationUndo(named: false, surface: .menu) }
    func testNamedConfirmationUndoFromMenu() { exerciseConfirmationUndo(named: true, surface: .menu) }
    func testPrimaryConfirmationUndoFromConfidence() { exerciseConfirmationUndo(named: false, surface: .confidence) }
    func testNamedConfirmationUndoFromConfidence() { exerciseConfirmationUndo(named: true, surface: .confidence) }
    func testPrimaryConfirmationUndoFromCurrentHistoryCard() { exerciseConfirmationUndo(named: false, surface: .history) }
    func testNamedConfirmationUndoFromCurrentHistoryCard() { exerciseConfirmationUndo(named: true, surface: .history) }

    func testConfirmedBannerInsideIdentificationCard() { exerciseReviewBanner(rejected: false, history: false) }
    func testConfirmedBannerInsideHistoryCard() { exerciseReviewBanner(rejected: false, history: true) }
    func testIncorrectBannerInsideIdentificationCard() { exerciseReviewBanner(rejected: true, history: false) }
    func testIncorrectBannerInsideHistoryCard() { exerciseReviewBanner(rejected: true, history: true) }

    private func exerciseReviewBanner(rejected: Bool, history: Bool) {
        continueAfterFailure = false
        var arguments = ["-seedPublicationConsentChooser", "-seedConfirmationUndo"]
        if rejected { arguments.append("-seedRejectionUndo") }
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: arguments)
        defer { app.terminate() }
        let scans = app.segmentedControls.buttons["Scans"]
        if !scans.waitForExistence(timeout: 5) {
            let library = app.buttons["MainTabBar_Naturebook"]
            XCTAssertTrue(library.waitForExistence(timeout: 10)); library.tap()
        }
        XCTAssertTrue(scans.waitForExistence(timeout: 10)); scans.tap()
        let tile = app.buttons["ScanTile_00000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10)); tile.tap()
        XCTAssertTrue(app.buttons["InsightTopMenu"].waitForExistence(timeout: 10))
        UITestAppLauncher.openIdentification(app, history: history)
        let undoID = history ? (rejected ? "HistoryUndoReview" : "HistoryUndoConfirmation")
            : (rejected ? "IncorrectIdentificationUndoButton" : "ConfidenceUndoConfirmation")
        let undo = app.buttons[undoID]
        XCTAssertTrue(undo.waitForExistence(timeout: 20))
        if !undo.isHittable { app.swipeUp() }
        XCTAssertTrue(undo.isHittable)
        XCTAssertFalse(app.buttons[history ? "HistoryConfirmPrimary" : "IdentificationConfirm"].exists)
        XCTAssertFalse(app.buttons[history ? "HistoryReject" : "IdentificationIncorrect"].exists)
        if rejected && history {
            XCTAssertTrue(app.buttons["IdentificationCommunityAction"].exists)
            XCTAssertTrue(app.buttons["IdentificationReanalysisAction"].exists)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(history ? "History" : "Identification") \(rejected ? "incorrect" : "confirmed") banner inside card"
        shot.lifetime = .keepAlways; add(shot)
        undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 20))
        if !history { app.buttons["IdentificationClose"].tap(); UITestAppLauncher.openIdentification(app, history: true) }
        let row = UITestAppLauncher.historyCard(app, id: "00000000-0000-4000-8000-000000000004")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Not confirmed"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 15), .completed)
        XCTAssertTrue(row.label.contains("Current"))
    }

    private enum UndoSurface { case menu, confidence, history }
    private func exerciseConfirmationUndo(named: Bool, surface: UndoSurface) {
        continueAfterFailure = false
        var arguments = ["-seedPublicationConsentChooser", "-seedConfirmationUndo"]
        if named { arguments.append("-seedSelectedNameConfirmation") }
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: arguments)
        defer { app.terminate() }
        let scans = app.segmentedControls.buttons["Scans"]
        if !scans.waitForExistence(timeout: 5) {
            let entry = app.buttons["MainTabBar_Naturebook"]
            XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        }
        XCTAssertTrue(scans.waitForExistence(timeout: 10)); scans.tap()
        let tile = app.buttons["ScanTile_00000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10)); tile.tap()
        let menu = app.buttons["InsightTopMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        let target = "00000000-0000-4000-8000-000000000004"
        let action: XCUIElement
        switch surface {
        case .menu:
            UITestAppLauncher.openIdentification(app); action = app.buttons["ConfidenceUndoConfirmation"]
        case .confidence:
            let badge = app.buttons["Confirmed"]
            XCTAssertTrue(badge.waitForExistence(timeout: 10)); badge.tap()
            action = app.buttons["ConfidenceUndoConfirmation"]
        case .history:
            UITestAppLauncher.openIdentification(app, history: true)
            let row = UITestAppLauncher.historyCard(app, id: target)
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            action = app.buttons["HistoryUndoConfirmation"]
        }
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        if !action.isHittable { app.swipeUp() }
        XCTAssertTrue(action.isHittable); action.tap()
        let alert = app.alerts["Undo your species identification?"]
        if named {
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            let explanation = "Your correction will be removed and the original AI identification will return as unreviewed. The current selection will not change."
            XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label == %@", explanation)).firstMatch.exists)
            alert.buttons["Cancel"].tap()
            // Cancellation leaves the same exact target eligible for the final decision.
            XCTAssertTrue(action.waitForExistence(timeout: 5)); XCTAssertTrue(action.isEnabled); action.tap()
            XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Undo confirmation"].tap()
        } else { XCTAssertFalse(alert.exists) }
        // The synthetic boundary runs real claim/receipt/paired reconciliation and verifies
        // exactly one completed outbox operation, unchanged selection and immutable snapshots.
        if surface == .history {
            XCTAssertTrue(action.waitForNonExistence(timeout: 10))
            UITestAppLauncher.closeHistory(app)
        } else {
            XCTAssertTrue(action.waitForNonExistence(timeout: 10))
            // Dismiss through the sheet chrome, independent of content scroll position.
            app.buttons["IdentificationClose"].tap()
        }
        let menuReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [menuReady], timeout: 10), .completed)
        UITestAppLauncher.openIdentification(app, actions: true)
        let history = app.buttons["IdentificationHistoryMenu"]
        XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
        let row = UITestAppLauncher.historyCard(app, id: target)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Not confirmed"))
        if surface != .history { XCTAssertFalse(app.buttons["HistoryUndoConfirmation"].exists) }
        XCTAssertTrue(row.label.contains("Current"), "Review Undo must preserve the selected identification")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Confirmation Undo preserves original result"; shot.lifetime = .keepAlways; add(shot)
    }

    func testSelectedBroaderTaxonNameConfirmationPersistsExactReview() {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedPublicationConsentChooser", "-seedSelectedNameConfirmation"])
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
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); UITestAppLauncher.openIdentification(app)
        let action = app.buttons["IdentificationConfirm"]
        let initialMenu = XCTAttachment(screenshot: app.screenshot())
        initialMenu.name = "Broader identification review menu"; initialMenu.lifetime = .keepAlways; add(initialMenu)
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ReanalyzeSpeciesMenu"].exists, "An enrolled result without protected access must not offer legacy refinement")
        UITestAppLauncher.slideIdentificationConfirmation(app)
        let confirm = app.buttons["SelectedReviewConfirmName"], name = app.textFields["SelectedReviewSpeciesName"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); XCTAssertFalse(confirm.isEnabled)
        XCTAssertTrue(name.exists)
        // Closing an untouched form leaves the retained host available.
        app.buttons["Done"].tap(); UITestAppLauncher.openIdentification(app)
        XCTAssertTrue(action.waitForExistence(timeout: 5)); UITestAppLauncher.slideIdentificationConfirmation(app)
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Danaus plexippus")
        XCTAssertTrue(confirm.isEnabled); confirm.tap()
        let status = app.staticTexts["SelectedReviewNameStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5)); XCTAssertTrue(status.label.contains("Review pending"))
        XCTAssertFalse(confirm.isEnabled)
        // The fixture wake verifies the real outbox's exact target, name and revisions.
        app.buttons["Done"].tap(); UITestAppLauncher.openIdentification(app)
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
            let entry = app.buttons["MainTabBar_Naturebook"]
            XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        }
        XCTAssertTrue(scans.waitForExistence(timeout: 10)); scans.tap()
        let tile = app.buttons["ScanTile_00000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10)); tile.tap()
        XCTAssertTrue(app.staticTexts["Consent Butterfly"].waitForExistence(timeout: 10))
        let menu = app.buttons["InsightTopMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); UITestAppLauncher.openIdentification(app, actions: true)
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
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); UITestAppLauncher.openIdentification(app, actions: true); ask.tap()
        let occupied = app.staticTexts["Request on this device: Waiting to send"]
        XCTAssertTrue(occupied.waitForExistence(timeout: 10))
        XCTAssertFalse(choose.exists); XCTAssertFalse(confirm.exists)
        app.buttons["Done"].tap(); UITestAppLauncher.openIdentification(app, actions: true)
        let history = app.buttons["IdentificationHistoryMenu"]
        XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
        let current = UITestAppLauncher.historyCard(app, id: "00000000-0000-4000-8000-000000000004")
        XCTAssertTrue(current.waitForExistence(timeout: 10)); XCTAssertTrue(current.label.contains("Current"))
        let historical = UITestAppLauncher.historyCard(app, id: "00000000-0000-4000-8000-000000000002")
        XCTAssertTrue(historical.exists); UITestAppLauncher.openHistoryActions(app, id: "00000000-0000-4000-8000-000000000002")
        let historyAsk = app.buttons["Ask the community"]
        XCTAssertTrue(historyAsk.waitForExistence(timeout: 5)); historyAsk.tap()
        XCTAssertTrue(occupied.waitForExistence(timeout: 10))
        XCTAssertFalse(choose.exists); XCTAssertFalse(confirm.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Community request retains exact consent across entry points"
        shot.lifetime = .keepAlways; add(shot)
    }
}
