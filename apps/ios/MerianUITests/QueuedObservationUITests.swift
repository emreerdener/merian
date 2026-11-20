import XCTest

@MainActor
final class QueuedObservationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testHeldAudioVideoRemainExplicitAcrossProcessRelaunch() throws {
        let app = UITestAppLauncher.makeConfiguredApp(extraArguments: ["-seedQueuedObservationRestart"])
        defer { app.terminate() }
        // Retain the uniquely owned synthetic store for qualification evidence.
        // Termination closes the process; it does not remove the store.
        let namespace = try XCTUnwrap(app.launchEnvironment["UITestKeychainNamespace"])
        let receipt = XCTAttachment(string: "Retained synthetic fixture: tmp/queued-observation-ui-" + namespace.uppercased() + "/queue.sqlite")
        receipt.name = "Owned queued observation fixture"; receipt.lifetime = .keepAlways; add(receipt)
        app.launch()
        XCTAssertTrue(app.staticTexts["QueuedFixtureStore"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.staticTexts["QueuedFixtureStore"].label, "created")
        let identity = app.staticTexts["QueuedFixtureIdentity"].label
        XCTAssertEqual(identity.count, 64)
        let process = app.staticTexts["QueuedFixtureProcess"].label
        XCTAssertEqual(app.staticTexts["QueuedFixtureCounts"].label, "0:0:0")
        var expectedChecks = 0
        for media in ["Audio", "Video"] {
            app.buttons["QueuedFixture" + media].tap()
            XCTAssertTrue(app.buttons["QueuedFixtureClose"].waitForExistence(timeout: 8))
            XCTAssertEqual(app.staticTexts["QueuedFixtureCounts"].label, "\(expectedChecks):0:0")
            XCTAssertFalse(app.buttons["Retry now"].exists)
            for outcome in ["No matching server record was observed.", "Last recorded job status: processing.", "Last recorded job status: complete."] {
                let check = app.buttons["Check status"]
                for _ in 0..<3 where !check.isHittable { app.swipeUp() }
                XCTAssertTrue(check.waitForExistence(timeout: 8)); XCTAssertTrue(check.isEnabled); check.tap()
                expectedChecks += 1
                waitForCount(app, expectedChecks)
                let observed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", outcome)).firstMatch
                XCTAssertTrue(observed.waitForExistence(timeout: 8))
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
                    "The original result has not been confirmed")).firstMatch.exists)
                XCTAssertEqual(app.staticTexts["QueuedFixtureIdentity"].label, identity)
                XCTAssertFalse(app.staticTexts["QueuedFixtureError"].exists)
                XCTAssertFalse(app.buttons["Retry now"].exists)
            }
            app.buttons["QueuedFixtureClose"].tap()
            XCTAssertTrue(app.buttons["QueuedFixture" + media].waitForExistence(timeout: 8))
        }
        // The same XCUIApplication retains its unique test namespace. A fresh
        // process opens its disk store; the fixture must not reseed the rows.
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["QueuedFixtureStore"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.staticTexts["QueuedFixtureStore"].label, "reopened")
        XCTAssertNotEqual(app.staticTexts["QueuedFixtureProcess"].label, process)
        XCTAssertEqual(app.staticTexts["QueuedFixtureIdentity"].label, identity)
        XCTAssertEqual(app.staticTexts["QueuedFixtureCounts"].label, "0:0:0")
        for (index, media) in ["Audio", "Video"].enumerated() {
            app.buttons["QueuedFixture" + media].tap()
            XCTAssertTrue(app.buttons["QueuedFixtureClose"].waitForExistence(timeout: 8))
            XCTAssertEqual(app.staticTexts["QueuedFixtureCounts"].label, "\(index):0:0")
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
                "The original result has not been confirmed")).firstMatch.exists)
            let check = app.buttons["Check status"]
            for _ in 0..<3 where !check.isHittable { app.swipeUp() }
            XCTAssertTrue(check.waitForExistence(timeout: 8)); check.tap()
            waitForCount(app, index + 1)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
                "No matching server record was observed.")).firstMatch.waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
                "The original result has not been confirmed")).firstMatch.exists)
            XCTAssertFalse(app.buttons["Retry now"].exists)
            XCTAssertEqual(app.staticTexts["QueuedFixtureIdentity"].label, identity)
            XCTAssertFalse(app.staticTexts["QueuedFixtureError"].exists)
            app.buttons["QueuedFixtureClose"].tap()
            XCTAssertTrue(app.buttons["QueuedFixture" + media].waitForExistence(timeout: 8))
        }
    }

    private func waitForCount(_ app: XCUIApplication, _ count: Int) {
        let expected = NSPredicate(format: "label == %@", "\(count):0:0")
        expectation(for: expected, evaluatedWith: app.staticTexts["QueuedFixtureCounts"])
        waitForExpectations(timeout: 8)
    }
}
