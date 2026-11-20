import XCTest

@MainActor
final class NativePhotoRecoveryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPendingPhotoChecksRemainExplicitAcrossProcessRelaunch() throws {
        let app = UITestAppLauncher.makeConfiguredApp(extraArguments: ["-seedNativePhotoRecoveryRestart"])
        defer { app.terminate() }
        let namespace = try XCTUnwrap(app.launchEnvironment["UITestKeychainNamespace"])
        let receipt = XCTAttachment(string: "Retained synthetic fixture: Application Support/native-recovery-ui-" + namespace.uppercased())
        receipt.name = "Owned native recovery fixture"; receipt.lifetime = .keepAlways; add(receipt)
        app.launch()
        XCTAssertTrue(app.staticTexts["NativeFixtureStore"].waitForExistence(timeout: 180))
        XCTAssertEqual(app.staticTexts["NativeFixtureStore"].label, "created")
        let identity = app.staticTexts["NativeFixtureIdentity"].label
        let process = app.staticTexts["NativeFixtureProcess"].label
        XCTAssertEqual(identity.count, 64)
        XCTAssertEqual(app.staticTexts["NativeFixtureChecks"].label, "0")
        XCTAssertEqual(app.staticTexts["NativeFixtureCharge"].label, "0")
        open(app)
        tap(app, "NativeRecoveryCheckResult", label: "Check status")
        waitForLabel(app.staticTexts["NativeFixtureChecks"], "1")
        reveal(app, identifier: "NativeRecoveryPause", label: "Pause checking", button: true, timeout: 12)
        tap(app, "NativeRecoveryPause", label: "Pause checking")
        XCTAssertTrue(app.staticTexts["Status checking paused. Your submission is unchanged."].waitForExistence(timeout: 90))
        close(app)
        let pausedCharge = try XCTUnwrap(Int64(app.staticTexts["NativeFixtureCharge"].label))
        XCTAssertGreaterThan(pausedCharge, 0)
        open(app)
        XCTAssertEqual(app.staticTexts["NativeFixtureChecks"].label, "1")
        tap(app, "NativeRecoveryCheckResult", label: "Check status")
        reveal(app, identifier: "NativeRecoveryResultAvailable", label: "A server record was observed. The original result has not been confirmed.", button: false)
        XCTAssertTrue(app.staticTexts["NativeRecoveryResultAvailable"].waitForExistence(timeout: 90))
        XCTAssertEqual(app.staticTexts["NativeFixtureChecks"].label, "2")
        XCTAssertFalse(app.buttons["NativeRecoveryAddHistory"].exists)
        close(app)
        XCTAssertEqual(app.staticTexts["NativeFixtureIdentity"].label, identity)
        let charge = try XCTUnwrap(Int64(app.staticTexts["NativeFixtureCharge"].label))
        XCTAssertGreaterThan(charge, pausedCharge); XCTAssertLessThan(charge, 30_000)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["NativeFixtureStore"].waitForExistence(timeout: 90))
        XCTAssertEqual(app.staticTexts["NativeFixtureStore"].label, "reopened")
        XCTAssertNotEqual(app.staticTexts["NativeFixtureProcess"].label, process)
        XCTAssertEqual(app.staticTexts["NativeFixtureIdentity"].label, identity)
        XCTAssertEqual(app.staticTexts["NativeFixtureCharge"].label, String(charge))
        XCTAssertEqual(app.staticTexts["NativeFixtureChecks"].label, "0")
        open(app)
        XCTAssertEqual(app.staticTexts["NativeFixtureChecks"].label, "0")
        XCTAssertFalse(app.staticTexts["NativeRecoveryResultAvailable"].exists)
        tap(app, "NativeRecoveryCheckResult", label: "Check status")
        reveal(app, identifier: "NativeRecoveryResultAvailable", label: "A server record was observed. The original result has not been confirmed.", button: false)
        XCTAssertTrue(app.staticTexts["NativeRecoveryResultAvailable"].waitForExistence(timeout: 90))
        XCTAssertEqual(app.staticTexts["NativeFixtureChecks"].label, "1")
        close(app)
        XCTAssertEqual(app.staticTexts["NativeFixtureIdentity"].label, identity)
        XCTAssertFalse(app.staticTexts["NativeFixtureError"].exists)
    }

    func testRecoveredPhotoAddsHistoryOnlyAfterExplicitActionAndRequestsExactResult() throws {
        let app = UITestAppLauncher.makeConfiguredApp(extraArguments: ["-seedNativePhotoRecoveryHistory"])
        defer { app.terminate() }
        let namespace = try XCTUnwrap(app.launchEnvironment["UITestKeychainNamespace"])
        let receipt = XCTAttachment(string: "Retained synthetic fixture: Application Support/native-recovery-ui-" + namespace.uppercased())
        receipt.name = "Owned positive native recovery fixture"; receipt.lifetime = .keepAlways; add(receipt)
        let bundle = Bundle(for: Self.self)
        let completionURL = try XCTUnwrap(bundle.url(forResource: "InitialCompletionFixtures", withExtension: "json"))
        let stateURL = try XCTUnwrap(bundle.url(forResource: "state-v1", withExtension: "json"))
        let completion = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: completionURL)) as? [String: Any])
        let results = try XCTUnwrap(completion["retained_results"] as? [[String: Any]])
        let evidence = try XCTUnwrap(results.first?["evidence"] as? [String: Any])
        let recovery = try XCTUnwrap(completion["recovery_record"] as? [String: Any])
        let packet: [String: Any] = ["result": try XCTUnwrap(evidence["result_canonical"] as? String),
            "recovery": recovery.filter { ["reference", "provenance", "receipt", "projection"].contains($0.key) },
            "state": try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL))]
        let bytes = try JSONSerialization.data(withJSONObject: packet, options: [.sortedKeys])
        XCTAssertLessThanOrEqual(bytes.count, 24576)
        app.launchEnvironment["NativeRecoveryHistoryFixtures"] = bytes.base64EncodedString()
        app.launch()
        XCTAssertTrue(app.staticTexts["NativeFixtureStore"].waitForExistence(timeout: 180))
        let fingerprint = app.staticTexts["NativeFixtureIdentity"].label
        XCTAssertEqual(app.staticTexts["NativeFixtureEnrollments"].label, "0")
        XCTAssertEqual(app.staticTexts["NativeFixtureSelection"].label, "none")
        open(app)
        reveal(app, identifier: "NativeRecoveryAddHistory", label: "Add result to History", button: true)
        XCTAssertFalse(app.buttons["NativeRecoveryAddHistory"].isEnabled)
        tap(app, "NativeRecoveryCheckResult", label: "Check status")
        reveal(app, identifier: "NativeRecoveryResultAvailable", label: "A server record was observed. The original result has not been confirmed.", button: false)
        XCTAssertTrue(app.staticTexts["NativeRecoveryResultAvailable"].waitForExistence(timeout: 90))
        XCTAssertEqual(app.staticTexts["NativeFixtureEnrollments"].label, "0")
        XCTAssertEqual(app.staticTexts["NativeFixtureRoute"].label, "none")
        reveal(app, identifier: "NativeRecoveryAddHistory", label: "Add result to History", button: true)
        let addHistory = app.buttons["NativeRecoveryAddHistory"]
        // Observed copy appears before the status reservation finishes settling.
        expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: addHistory)
        waitForExpectations(timeout: 90)
        XCTAssertEqual(app.staticTexts["NativeFixtureEnrollments"].label, "0")
        XCTAssertEqual(app.staticTexts["NativeFixtureRoute"].label, "none")
        tap(app, "NativeRecoveryAddHistory", label: "Add result to History")
        reveal(app, identifier: "NativeRecoveryHistorySaved", label: "Result saved in History. Your current selection is unchanged.", button: false, timeout: 120)
        XCTAssertTrue(app.staticTexts["NativeRecoveryHistorySaved"].waitForExistence(timeout: 120))
        XCTAssertEqual(app.staticTexts["NativeFixtureEnrollments"].label, "1")
        let selection = app.staticTexts["NativeFixtureSelection"].label
        XCTAssertNotNil(UUID(uuidString: selection))
        reveal(app, identifier: "NativeRecoveryAddHistory", label: "Add result to History", button: true)
        XCTAssertFalse(app.buttons["NativeRecoveryAddHistory"].isEnabled)
        XCTAssertEqual(app.staticTexts["NativeFixtureIdentity"].label, fingerprint)
        XCTAssertEqual(app.staticTexts["NativeFixtureRoute"].label, "none")
        tap(app, "NativeRecoveryOpenResult", label: "Open result")
        XCTAssertTrue(app.buttons["NativeFixtureOpen"].waitForExistence(timeout: 90))
        XCTAssertEqual(app.staticTexts["NativeFixtureRoute"].label, "requested")
        XCTAssertEqual(app.staticTexts["NativeFixtureSelection"].label, selection)
        XCTAssertEqual(app.staticTexts["NativeFixtureEnrollments"].label, "1")
        XCTAssertEqual(app.staticTexts["NativeFixtureIdentity"].label, fingerprint)
        XCTAssertFalse(app.staticTexts["NativeFixtureError"].exists)
    }

    private func open(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["NativeFixtureOpen"].waitForExistence(timeout: 90))
        app.buttons["NativeFixtureOpen"].tap()
        XCTAssertTrue(app.buttons["NativeRecoverySelect_0"].waitForExistence(timeout: 90))
        tap(app, "NativeRecoverySelect_0", label: "Pending submission 1")
        XCTAssertTrue(app.staticTexts["NativeRecoveryHolding"].waitForExistence(timeout: 90))
        reveal(app, identifier: "NativeRecoveryCheckResult", label: "Check status", button: true)
        XCTAssertTrue(app.buttons["NativeRecoveryCheckResult"].isEnabled)
    }
    private func close(_ app: XCUIApplication) {
        tap(app, "NativeRecoveryClose", label: "Close")
        XCTAssertTrue(app.buttons["NativeFixtureOpen"].waitForExistence(timeout: 90))
        XCTAssertFalse(app.staticTexts["NativeFixtureError"].exists)
    }
    private func tap(_ app: XCUIApplication, _ identifier: String, label: String) {
        reveal(app, identifier: identifier, label: label, button: true)
        let action = app.buttons[identifier]
        XCTAssertTrue(action.isEnabled)
        XCTAssertTrue(action.isHittable)
        action.tap()
    }
    private func reveal(_ app: XCUIApplication, identifier: String, label: String, button: Bool, timeout: TimeInterval = 90) {
        func element() -> XCUIElement { button ? app.buttons[identifier] : app.staticTexts[identifier] }
        let deadline = Date().addingTimeInterval(timeout)
        var gestures = 0
        var scrollDiagnostics: [String] = []
        // Readiness retains its explicit deadline; exhausting viewport gestures
        // does not turn asynchronous completion into a shorter timeout.
        while true {
            if element().exists && element().isHittable {
                XCTAssertEqual(element().label, label)
                return
            }
            guard Date() < deadline else { break }
            if gestures < 12 {
                let sheetIDs = ["NativeRecoverySheet"]
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
    private func waitForLabel(_ element: XCUIElement, _ label: String) {
        expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
        waitForExpectations(timeout: 90)
    }
}
