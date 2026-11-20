import XCTest

@MainActor final class ReanalysisRecoveryRestartUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testPhotoCheckingBudgetAndOriginalRequestSurviveRelaunch() throws { try run("photo") }
    func testAudioCheckingBudgetAndOriginalRequestSurviveRelaunch() throws { try run("audio") }
    func testVideoCheckingBudgetAndOriginalRequestSurviveRelaunch() throws { try run("video") }
    func testPhotoRecoversAfterExhaustionIntoPersistedHistoryAndUndo() throws { try run("photo", success: true) }
    func testAudioRecoversAfterExhaustionIntoPersistedHistoryAndUndo() throws { try run("audio", success: true) }
    func testVideoRecoversAfterExhaustionIntoPersistedHistoryAndUndo() throws { try run("video", success: true) }

    private func run(_ media: String, success: Bool = false) throws {
        let arguments = ["-seedReanalysisRecoveryRestart"] + (success ? ["-seedReanalysisRecoverySuccess"] : [])
        let app = UITestAppLauncher.makeConfiguredApp(extraArguments: arguments)
        defer { app.terminate() }
        app.launchEnvironment["ReanalysisRecoveryMedia"] = media
        let namespace = try XCTUnwrap(app.launchEnvironment["UITestKeychainNamespace"])
        let receipt = XCTAttachment(string: "Retained synthetic " + media + " fixture: Application Support/reanalysis-recovery-ui-" + namespace.uppercased())
        receipt.name = "Owned reanalysis recovery fixture"; receipt.lifetime = .keepAlways; add(receipt)
        app.launch()
        XCTAssertTrue(app.staticTexts["ReanalysisFixtureStore"].waitForExistence(timeout: 180))
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureStore"].label, "created")
        let child = app.staticTexts["ReanalysisFixtureChild"].label
        let selection = app.staticTexts["ReanalysisFixtureSelection"].label
        let request = app.staticTexts["ReanalysisFixtureRequest"].label
        let fingerprint = app.staticTexts["ReanalysisFixtureFingerprint"].label
        XCTAssertNotNil(UUID(uuidString: child)); XCTAssertNotNil(UUID(uuidString: selection))
        XCTAssertEqual(request.count, 64); XCTAssertEqual(fingerprint.count, 64)
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureCharge"].label, "0")
        openAndCheck(app, media, child, verifyPhotoPreview: true)
        waitForMessage(app, media, "We lost confirmation of your result. We’re checking whether it finished.", timeout: 90)
        close(app, media)
        let spent = try XCTUnwrap(Int(app.staticTexts["ReanalysisFixtureCharge"].label))
        XCTAssertGreaterThan(spent, 0); XCTAssertLessThan(spent, 30_000)
        assertFacts(app, child, selection, request, fingerprint)
        relaunch(app)
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureCharge"].label, String(spent))
        assertFacts(app, child, selection, request, fingerprint)
        openAndCheck(app, media, child)
        waitForMessage(app, media, "We haven’t been able to recover your result yet.", timeout: 45)
        close(app, media)
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureCharge"].label, "30000")
        assertFacts(app, child, selection, request, fingerprint)
        if success {
            tapEnabled(app, "ReanalysisFixtureReleaseResult")
            XCTAssertEqual(app.staticTexts["ReanalysisFixtureServer"].label, "available")
        }
        relaunch(app)
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureCharge"].label, "30000")
        openAndCheck(app, media, child)
        if success {
            waitForMessage(app, media, "Your original result is available in identification history.", timeout: 90)
            close(app, media, terminal: true)
            XCTAssertEqual(app.staticTexts["ReanalysisFixtureCompletion"].label, "complete")
            XCTAssertEqual(app.staticTexts["ReanalysisFixtureCompletionNotifications"].label, "1")
            XCTAssertEqual(app.staticTexts["ReanalysisFixtureCharge"].label, "30000")
            assertFacts(app, child, selection, request, fingerprint)
            exerciseHistory(app, child: child, original: selection)
            assertFacts(app, child, selection, request, fingerprint)
            relaunch(app)
            XCTAssertEqual(app.staticTexts["ReanalysisFixtureCompletion"].label, "complete")
            XCTAssertEqual(app.staticTexts["ReanalysisFixtureCharge"].label, "30000")
            XCTAssertFalse(app.buttons["ReanalysisFixtureOpen"].exists)
            assertFacts(app, child, selection, request, fingerprint)
            tapEnabled(app, "ReanalysisFixtureHistory")
            assertHistoryRows(app, child: child, selected: selection)
            tapEnabled(app, "HistoryDone")
            XCTAssertTrue(app.buttons["ReanalysisFixtureHistory"].waitForExistence(timeout: 90))
            XCTAssertFalse(app.staticTexts["ReanalysisFixtureError"].exists)
            return
        }
        waitForMessage(app, media, "We haven’t been able to recover your result yet.", timeout: 15)
        close(app, media)
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureCharge"].label, "30000")
        assertFacts(app, child, selection, request, fingerprint)
    }
    private func openAndCheck(_ app: XCUIApplication, _ media: String, _ child: String, verifyPhotoPreview: Bool = false) {
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureChecks"].label, "0")
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureForbidden"].label, "0")
        app.buttons["ReanalysisFixtureOpen"].tap()
        let action: XCUIElement
        if media == "photo" {
            if verifyPhotoPreview {
                let preview = app.buttons["ReanalysisPhotos_" + child]
                reveal(app, identifier: "ReanalysisPhotos_" + child, label: "View saved photos", button: true)
                XCTAssertTrue(preview.waitForExistence(timeout: 90))
                expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: preview)
                waitForExpectations(timeout: 90)
                preview.tap()
                reveal(app, identifier: "Original submitted photo 1 of 1", label: "Original submitted photo 1 of 1", button: false)
                let closePreview = app.buttons["Close photo preview"]
                reveal(app, identifier: "Close photo preview", label: "Close photo preview", button: true)
                XCTAssertTrue(closePreview.waitForExistence(timeout: 90))
                XCTAssertEqual(app.staticTexts["ReanalysisFixtureChecks"].label, "0")
                XCTAssertEqual(app.staticTexts["ReanalysisFixtureForbidden"].label, "0")
                closePreview.tap()
            }
            action = app.buttons["ReanalysisOutcome_" + child]
            reveal(app, identifier: "ReanalysisOutcome_" + child, label: "Check for the original result", button: true)
        }
        else {
            let rowID = (media == "audio" ? "SavedAudioRow_" : "SavedVideoRequestRow_") + child
            reveal(app, identifier: rowID, label: nil, button: true)
            let row = app.buttons[rowID]
            XCTAssertTrue(row.waitForExistence(timeout: 90)); row.tap()
            action = app.buttons[media == "audio" ? "SavedAudioContinue" : "SavedVideoRequestContinue"]
        }
        reveal(app, identifier: media == "photo" ? "ReanalysisOutcome_" + child : (media == "audio" ? "SavedAudioContinue" : "SavedVideoRequestContinue"),
            label: media == "photo" ? "Check for the original result" : (media == "audio" ? "Check saved result" : "Check saved request"), button: true)
        XCTAssertTrue(action.waitForExistence(timeout: 90))
        expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: action)
        waitForExpectations(timeout: 90)
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureChecks"].label, "0")
        XCTAssertTrue(action.isHittable)
        action.tap()
        expectation(for: NSPredicate(format: "label == %@", "1"), evaluatedWith: app.staticTexts["ReanalysisFixtureChecks"])
        waitForExpectations(timeout: 90)
        if media == "photo" { XCTAssertFalse(app.staticTexts["Original submitted photo 1 of 1"].exists) }
    }
    private func waitForMessage(_ app: XCUIApplication, _ media: String, _ message: String, timeout: TimeInterval) {
        let identifier = media == "photo" ? "ReanalysisRecoveryMessage" : (media == "audio" ? "SavedAudioRecoveryMessage" : "SavedVideoRecoveryMessage")
        reveal(app, identifier: identifier, label: nil, button: false, timeout: timeout)
        expectation(for: NSPredicate(format: "exists == true AND label == %@", message), evaluatedWith: app.staticTexts[identifier])
        waitForExpectations(timeout: timeout)
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureForbidden"].label, "0")
    }
    private func close(_ app: XCUIApplication, _ media: String, terminal: Bool = false) {
        app.buttons[media == "photo" ? "Done" : (media == "audio" ? "SavedAudioDone" : "SavedVideoRequestDone")].tap()
        XCTAssertTrue(app.buttons[terminal ? "ReanalysisFixtureHistory" : "ReanalysisFixtureOpen"].waitForExistence(timeout: 90))
        XCTAssertFalse(app.staticTexts["ReanalysisFixtureError"].exists)
    }
    @discardableResult
    private func tapEnabled(_ app: XCUIApplication, _ identifier: String) -> Date {
        let button = app.buttons[identifier]
        if identifier.hasPrefix("HistoryRow_") {
            revealHistoryRowForTap(app, identifier: identifier)
        } else {
            reveal(app, identifier: identifier, label: nil, button: true)
        }
        XCTAssertTrue(button.waitForExistence(timeout: 90))
        expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: button)
        waitForExpectations(timeout: 90)
        XCTAssertTrue(button.isHittable)
        if identifier.hasPrefix("HistoryRow_") {
            guard let (_, viewport) = historyTapViewport(app), historyRowReady(button, viewport: viewport) else {
                captureHistoryTapFailure(app, reason: "Exact History row lost safe geometry before tap: " + identifier)
                return Date()
            }
        }
        let tapStartedAt = Date()
        button.tap()
        if identifier.hasPrefix("HistoryRow_") && !app.buttons["HistoryBack"].waitForExistence(timeout: 90) {
            captureHistoryTapFailure(app, reason: "One exact History row tap did not open a preview: " + identifier)
        }
        return tapStartedAt
    }
    private func historyTapViewport(_ app: XCUIApplication) -> (XCUIElement, CGRect)? {
        let sheets = app.otherElements.matching(identifier: "IdentificationHistorySheet").allElementsBoundByIndex
            .filter { $0.exists && !$0.frame.intersection(app.frame).isEmpty }
        guard sheets.count == 1 else { return nil }
        let lists = sheets[0].collectionViews.allElementsBoundByIndex
            .filter { $0.exists && !$0.frame.intersection(app.frame).isEmpty }
        guard lists.count == 1 else { return nil }
        var viewport = lists[0].frame.intersection(app.frame)
        for bar in app.navigationBars.allElementsBoundByIndex where bar.exists {
            let overlap = bar.frame.intersection(viewport)
            if !overlap.isNull && !overlap.isEmpty {
                guard overlap.midY < viewport.midY else { return nil }
                viewport = CGRect(x: viewport.minX, y: overlap.maxY, width: viewport.width,
                    height: max(0, viewport.maxY - overlap.maxY))
            }
        }
        guard !viewport.isEmpty, !viewport.isNull else { return nil }
        return (lists[0], viewport)
    }
    private func historyRowReady(_ row: XCUIElement, viewport: CGRect) -> Bool {
        guard row.exists, row.isEnabled, row.isHittable else { return false }
        let frame = row.frame
        // Oversized rows need a visible center, not impossible whole-row containment.
        return !frame.isEmpty && !frame.intersection(viewport).isEmpty
            && viewport.contains(CGPoint(x: frame.midX, y: frame.midY))
    }
    private func revealHistoryRowForTap(_ app: XCUIApplication, identifier: String) {
        let deadline = Date().addingTimeInterval(90)
        var gestures = 0
        while Date() < deadline {
            guard let (list, viewport) = historyTapViewport(app) else {
                captureHistoryTapFailure(app, reason: "Missing or ambiguous History list geometry: " + identifier); return
            }
            let row = app.buttons[identifier]
            if historyRowReady(row, viewport: viewport) { return }
            if gestures < 12 {
                if row.exists && !row.frame.isEmpty {
                    if row.frame.midY < viewport.minY { list.swipeDown() }
                    else if row.frame.midY > viewport.maxY { list.swipeUp() }
                    else {
                        RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.25)))
                        continue
                    }
                } else if gestures < 6 { list.swipeUp() } else { list.swipeDown() }
                gestures += 1
            } else {
                RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.25)))
            }
        }
        captureHistoryTapFailure(app, reason: "History row was not safely positioned within 90 seconds and 12 gestures: " + identifier)
    }
    private func captureHistoryTapFailure(_ app: XCUIApplication, reason: String) {
        let state = XCTAttachment(string: reason + "\n" + app.debugDescription)
        state.name = "History row tap state"; state.lifetime = .keepAlways; add(state)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "History row tap viewport"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCTFail(reason)
    }
    private func reveal(_ app: XCUIApplication, identifier: String, label: String?, button: Bool, timeout: TimeInterval = 90) {
        func element() -> XCUIElement { button ? app.buttons[identifier] : app.staticTexts[identifier] }
        let deadline = Date().addingTimeInterval(timeout)
        var gestures = 0
        var scrollDiagnostics: [String] = []
        // Readiness retains its explicit deadline; exhausting viewport gestures
        // does not turn asynchronous completion into a shorter timeout.
        while true {
            if element().exists && element().isHittable {
                if let label { XCTAssertEqual(element().label, label) }
                return
            }
            guard Date() < deadline else { break }
            if gestures < 12 {
                let sheetIDs = ["ReanalysisStatusSheet", "SavedAudioSheet", "SavedVideoRequestSheet", "IdentificationHistorySheet"]
                let sheets = sheetIDs.flatMap { app.otherElements.matching(identifier: $0).allElementsBoundByIndex }
                    .filter { $0.exists && !$0.frame.intersection(app.frame).isEmpty }
                let lists = sheets.flatMap { $0.collectionViews.allElementsBoundByIndex }
                    .filter { $0.exists && !$0.frame.intersection(app.frame).isEmpty }
                var scrollTarget: XCUIElement?
                var diagnostic = "sheets=\(sheets.count), lists=\(lists.count), gestures=\(gestures)"
                if sheets.count == 1, lists.count == 1, let list = lists.first {
                    let visible = list.frame.intersection(app.frame)
                    // A hittable descendant proves this exact list is visible.
                    // Swipe the stable list viewport, not a partially clipped row.
                    let witness = (list.staticTexts.allElementsBoundByIndex + list.cells.allElementsBoundByIndex)
                        .first { $0.exists && $0.isHittable && !$0.frame.intersection(visible).isEmpty }
                    diagnostic += ", listFrame=\(list.frame), containerHittable=\(list.isHittable)"
                    if let witness {
                        diagnostic += ", witness=\(witness.elementType), frame=\(witness.frame), hittable=\(witness.isHittable)"
                        scrollTarget = list
                    }
                }
                if scrollDiagnostics.last != diagnostic && scrollDiagnostics.count < 32 { scrollDiagnostics.append(diagnostic) }
                if let scrollTarget {
                    if gestures < 6 { scrollTarget.swipeUp() } else { scrollTarget.swipeDown() }
                    gestures += 1
                    continue // Includes a fresh query after the final permitted swipe.
                }
            }
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.25)))
        }
        let diagnostics = XCTAttachment(string: scrollDiagnostics.joined(separator: "\n") + "\nissuedGestures=\(gestures)")
        diagnostics.name = "Recovery scroll diagnostics " + identifier; diagnostics.lifetime = .keepAlways; add(diagnostics)
        let snapshot = XCTAttachment(string: app.debugDescription)
        snapshot.name = "Unrevealed recovery element " + identifier; snapshot.lifetime = .keepAlways; add(snapshot)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Unrevealed element " + identifier; screenshot.lifetime = .keepAlways; add(screenshot)
        XCTFail("Recovery element was not revealed within its readiness deadline and scroll bound: " + identifier)
    }
    private func assertHistoryRows(_ app: XCUIApplication, child: String, selected: String) {
        let row = app.buttons["HistoryRow_" + child]
        reveal(app, identifier: "HistoryRow_" + child, label: nil, button: true)
        XCTAssertTrue(row.waitForExistence(timeout: 90))
        // List virtualizes offscreen rows; count the same loaded model used by
        // the production sheet, then independently reveal the selected UI row.
        XCTAssertTrue(app.staticTexts["ReanalysisFixtureHistoryRowCount"].waitForExistence(timeout: 90))
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureHistoryRowCount"].label, "3")
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureHistoryNextPage"].label, "none")
        reveal(app, identifier: "HistoryRow_" + selected, label: nil, button: true)
        expectation(for: NSPredicate(format: "exists == true AND label CONTAINS %@", "Current"),
            evaluatedWith: app.buttons["HistoryRow_" + selected])
        waitForExpectations(timeout: 90)
    }
    private func exerciseHistory(_ app: XCUIApplication, child: String, original: String) {
        tapEnabled(app, "ReanalysisFixtureHistory")
        assertHistoryRows(app, child: child, selected: original)
        tapEnabled(app, "HistoryRow_" + child)
        tapEnabled(app, "HistoryRestore")
        assertHistoryRows(app, child: child, selected: child)
        tapEnabled(app, "HistoryRow_" + child)
        tapEnabled(app, "HistoryReject")
        // Reconciliation changes the parent revision and retires this preview.
        // Receipt delivery reloads fresh authority without a manual Refresh.
        waitForReviewRefresh(app, child: child, incorrect: true)
        assertHistoryRows(app, child: child, selected: child)
        XCTAssertTrue(app.buttons["HistoryRow_" + child].label.contains("Marked incorrect"))
        tapEnabled(app, "HistoryRow_" + child)
        tapEnabled(app, "HistoryUndoReview")
        waitForReviewRefresh(app, child: child, incorrect: false)
        assertHistoryRows(app, child: child, selected: child)
        XCTAssertFalse(app.buttons["HistoryRow_" + child].label.contains("Marked incorrect"))
        tapEnabled(app, "HistoryRow_" + child)
        reveal(app, identifier: "HistoryReject", label: nil, button: true)
        XCTAssertTrue(app.buttons["HistoryReject"].waitForExistence(timeout: 90))
        XCTAssertFalse(app.buttons["HistoryUndoReview"].exists)
        tapEnabled(app, "HistoryBack")
        // Review invalidates the earlier selection Undo. Make a fresh explicit
        // return to the source before exercising that new selection's Undo.
        tapEnabled(app, "HistoryRow_" + original)
        let restoreStartedAt = tapEnabled(app, "HistoryRestore")
        undoSelectionImmediately(app, selected: original, restoreStartedAt: restoreStartedAt)
        assertHistoryRows(app, child: child, selected: child)
        tapEnabled(app, "HistoryRow_" + original); tapEnabled(app, "HistoryRestore")
        assertHistoryRows(app, child: child, selected: original)
        tapEnabled(app, "HistoryDone")
        XCTAssertTrue(app.buttons["ReanalysisFixtureHistory"].waitForExistence(timeout: 90))
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureSelection"].label, original)
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureForbidden"].label, "0")
        XCTAssertFalse(app.staticTexts["ReanalysisFixtureError"].exists)
    }
    private func undoSelectionImmediately(_ app: XCUIApplication, selected: String, restoreStartedAt: Date) {
        // Do not spend the real 15-second opportunity traversing virtualized rows.
        // This conservative bound starts before the tap, earlier than server acknowledgement.
        let deadline = restoreStartedAt.addingTimeInterval(15)
        var timing = ["restoreTapStartedSeconds=0"]
        defer {
            let attachment = XCTAttachment(string: timing.joined(separator: "\n"))
            attachment.name = "Selection Undo timing"; attachment.lifetime = .keepAlways; add(attachment)
        }
        let witness = app.staticTexts["ReanalysisFixtureSelection"]
        while Date() < deadline {
            if witness.exists && witness.label == selected { break }
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.1)))
        }
        guard witness.exists, witness.label == selected, Date() < deadline else {
            XCTFail("Acknowledged selection was not observed within the conservative pre-tap Undo budget"); return
        }
        timing.append("acknowledgementWitnessObservedSeconds=\(Date().timeIntervalSince(restoreStartedAt))")
        timing.append("firstUndoQuerySeconds=\(Date().timeIntervalSince(restoreStartedAt))")
        reveal(app, identifier: "HistoryUndo", label: "Undo identification change", button: true,
            timeout: max(0, deadline.timeIntervalSinceNow))
        let undo = app.buttons["HistoryUndo"]
        guard undo.exists, undo.isEnabled, undo.isHittable, Date() < deadline else {
            XCTFail("Selection Undo was not safely actionable within the conservative pre-tap budget"); return
        }
        timing.append("undoTapStartedSeconds=\(Date().timeIntervalSince(restoreStartedAt))")
        undo.tap()
    }
    private func waitForReviewRefresh(_ app: XCUIApplication, child: String, incorrect: Bool) {
        let row = app.buttons["HistoryRow_" + child]
        expectation(for: NSPredicate { _, _ in
            row.exists && row.isEnabled && row.label.contains("Marked incorrect") == incorrect
        }, evaluatedWith: row)
        waitForExpectations(timeout: 90)
        XCTAssertFalse(app.buttons["HistoryBack"].exists)
        XCTAssertFalse(app.buttons["HistoryReject"].exists)
        XCTAssertFalse(app.buttons["HistoryUndoReview"].exists)
    }
    private func relaunch(_ app: XCUIApplication) {
        let process = app.staticTexts["ReanalysisFixtureProcess"].label
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["ReanalysisFixtureStore"].waitForExistence(timeout: 90))
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureStore"].label, "reopened")
        XCTAssertNotEqual(app.staticTexts["ReanalysisFixtureProcess"].label, process)
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureChecks"].label, "0")
    }
    private func assertFacts(_ app: XCUIApplication, _ child: String, _ selection: String, _ request: String, _ fingerprint: String) {
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureChild"].label, child)
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureSelection"].label, selection)
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureRequest"].label, request)
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureFingerprint"].label, fingerprint)
        XCTAssertEqual(app.staticTexts["ReanalysisFixtureForbidden"].label, "0")
        XCTAssertFalse(app.staticTexts["ReanalysisFixtureError"].exists)
    }
}
