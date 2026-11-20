import XCTest

@MainActor final class InitialMediaHistoryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testInitialPhotoWithoutTextCompletesIntoResultAndHistoryAcrossRelaunch() throws { try run(media: "photo", text: false) }
    func testInitialPhotoWithTextCompletesIntoResultAndHistoryAcrossRelaunch() throws { try run(media: "photo", text: true) }
    func testInitialAudioWithoutTextCompletesIntoResultAndHistoryAcrossRelaunch() throws { try run(media: "audio", text: false) }
    func testInitialAudioWithTextCompletesIntoResultAndHistoryAcrossRelaunch() throws { try run(media: "audio", text: true) }
    func testInitialVideoWithoutTextCompletesIntoResultAndHistoryAcrossRelaunch() throws { try run(media: "video", text: false) }
    func testInitialVideoWithTextCompletesIntoResultAndHistoryAcrossRelaunch() throws { try run(media: "video", text: true) }

    private func run(media: String, text: Bool) throws {
        let app = UITestAppLauncher.makeConfiguredApp(extraArguments: ["-seedInitialMediaHistory"])
        defer { app.terminate() }
        app.launchEnvironment["InitialHistoryMedia"] = media
        app.launchEnvironment["InitialHistoryText"] = text ? "yes" : "no"
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "state-v1", withExtension: "json"))
        let bytes = try Data(contentsOf: url); XCTAssertLessThan(bytes.count, 24_576)
        app.launchEnvironment["InitialHistoryState"] = bytes.base64EncodedString()
        let namespace = try XCTUnwrap(app.launchEnvironment["UITestKeychainNamespace"])
        let attachment = XCTAttachment(string: "Retained synthetic store: Application Support/initial-media-history-ui-" + namespace.uppercased())
        attachment.name = "Owned initial media History fixture"; attachment.lifetime = .keepAlways; add(attachment)
        app.launch()
        ready(app, timeout: 180)
        XCTAssertEqual(app.staticTexts["InitialHistoryStore"].label, "created")
        let scan = app.staticTexts["InitialHistoryScan"].label, baseline = app.staticTexts["InitialHistoryBaseline"].label
        let fingerprint = app.staticTexts["InitialHistoryFingerprint"].label, process = app.staticTexts["InitialHistoryProcess"].label
        XCTAssertNotNil(UUID(uuidString: scan)); XCTAssertNotNil(UUID(uuidString: baseline)); XCTAssertEqual(fingerprint.count, 64)
        XCTAssertEqual(app.staticTexts["InitialHistorySelection"].label, "none")
        XCTAssertEqual(app.staticTexts["InitialHistoryEnrollments"].label, "0")
        openResult(app)
        XCTAssertEqual(app.staticTexts["InitialHistorySelection"].label, "none")
        XCTAssertEqual(app.staticTexts["InitialHistoryEnrollments"].label, "0")
        app.buttons["InitialHistoryEnroll"].tap()
        XCTAssertTrue(app.buttons["InitialHistoryOpen"].waitForExistence(timeout: 90))
        XCTAssertEqual(app.staticTexts["InitialHistoryEnrollments"].label, "1")
        XCTAssertEqual(app.staticTexts["InitialHistorySelection"].label, baseline)
        openHistory(app, baseline: baseline)
        XCTAssertEqual(app.staticTexts["InitialHistoryFingerprint"].label, fingerprint)
        XCTAssertFalse(app.staticTexts["InitialHistoryError"].exists)
        app.terminate(); app.launch()
        ready(app, timeout: 90)
        XCTAssertEqual(app.staticTexts["InitialHistoryStore"].label, "reopened")
        XCTAssertNotEqual(app.staticTexts["InitialHistoryProcess"].label, process)
        XCTAssertEqual(app.staticTexts["InitialHistoryScan"].label, scan)
        XCTAssertEqual(app.staticTexts["InitialHistoryBaseline"].label, baseline)
        XCTAssertEqual(app.staticTexts["InitialHistoryFingerprint"].label, fingerprint)
        XCTAssertEqual(app.staticTexts["InitialHistorySelection"].label, baseline)
        XCTAssertEqual(app.staticTexts["InitialHistoryEnrollments"].label, "0")
        XCTAssertFalse(app.buttons["InitialHistoryEnroll"].exists)
        openResult(app); openHistory(app, baseline: baseline)
        XCTAssertEqual(app.staticTexts["InitialHistoryEnrollments"].label, "0")
        XCTAssertEqual(app.staticTexts["InitialHistoryFingerprint"].label, fingerprint)
        XCTAssertFalse(app.staticTexts["InitialHistoryError"].exists)
    }
    private func openResult(_ app: XCUIApplication) {
        app.buttons["InitialHistoryResult"].tap()
        XCTAssertTrue(app.otherElements["InsightSheetView"].waitForExistence(timeout: 90))
        XCTAssertTrue(app.staticTexts["Synthetic Audio"].firstMatch.waitForExistence(timeout: 90))
        app.buttons["InitialHistoryCloseResult"].tap()
        XCTAssertTrue(app.buttons["InitialHistoryResult"].waitForExistence(timeout: 30))
    }
    private func openHistory(_ app: XCUIApplication, baseline: String) {
        app.buttons["InitialHistoryOpen"].tap()
        let row = app.buttons["HistoryRow_" + baseline]
        XCTAssertTrue(row.waitForExistence(timeout: 90))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "HistoryRow_")).count, 1)
        row.tap()
        XCTAssertTrue(app.staticTexts["This is your current identification."].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Synthetic audio result."].exists)
        XCTAssertTrue(app.staticTexts["Original evidence is unavailable for this saved identification."].exists)
        app.buttons["HistoryDone"].tap()
        XCTAssertTrue(app.buttons["InitialHistoryOpen"].waitForExistence(timeout: 30))
    }
    private func ready(_ app: XCUIApplication, timeout: TimeInterval) {
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.staticTexts["InitialHistoryStore"].exists || app.staticTexts["InitialHistoryError"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: timeout), .completed)
        XCTAssertFalse(app.staticTexts["InitialHistoryError"].exists, app.staticTexts["InitialHistoryError"].exists ? app.staticTexts["InitialHistoryError"].label : "")
        XCTAssertTrue(app.staticTexts["InitialHistoryStore"].exists)
    }
}
