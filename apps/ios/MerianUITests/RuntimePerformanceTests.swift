import XCTest

@MainActor
final class RuntimePerformanceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        return options
    }

    func testProcessColdLaunch() {
        let app = UITestAppLauncher.makeConfiguredApp()
        defer { app.terminate() }
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.terminate()
            startMeasuring()
            app.launch()
            XCTAssertTrue(app.buttons["MainTabBar_Scans"].waitForExistence(timeout: 8))
            stopMeasuring()
        }
    }

    func testWarmForeground() {
        let app = UITestAppLauncher.launchConfiguredApp()
        defer { app.terminate() }
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app)], options: options) {
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 8))
            startMeasuring()
            app.activate()
            XCTAssertTrue(app.buttons["MainTabBar_Scans"].waitForExistence(timeout: 8))
            stopMeasuring()
        }
    }

    /// Report-only app-process measurements of production staging, exact proof
    /// settlement and explicit refresh. Setup/reopening are outside the interval.
    func testProtectedChatProofRefresh() {
        let app = UITestAppLauncher.makeConfiguredApp(extraArguments: ["-seedProtectedChatStale"])
        defer { app.terminate() }
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            app.terminate()
            app.launch()
            openSeededProtectedChat(app)
            let question = app.textFields["ProtectedChatQuestion"]
            XCTAssertTrue(question.waitForExistence(timeout: 10)); question.tap()
            question.typeText("What does this identification mean?")
            let send = app.buttons["ProtectedChatSend"]
            XCTAssertTrue(send.isEnabled)
            startMeasuring()
            send.tap()
            let proof = app.staticTexts["ProtectedChatNotAdmitted"]
            XCTAssertTrue(proof.waitForExistence(timeout: 10))
            let refresh = app.buttons["ProtectedChatRefreshIdentification"]
            XCTAssertTrue(refresh.waitForExistence(timeout: 5)); XCTAssertTrue(refresh.isEnabled)
            refresh.tap()
            XCTAssertTrue(app.navigationBars["Field chat"].waitForNonExistence(timeout: 10))
            stopMeasuring()
            tapProtectedChat(app)
            XCTAssertTrue(question.waitForExistence(timeout: 10))
            XCTAssertTrue(send.exists); XCTAssertFalse(send.isEnabled)
            XCTAssertTrue(proof.exists); XCTAssertFalse(refresh.exists)
        }
    }

    private func openSeededProtectedChat(_ app: XCUIApplication) {
        let scans = app.segmentedControls.buttons["Scans"]
        if !scans.waitForExistence(timeout: 5) {
            let entry = app.buttons["MainTabBar_Scans"]
            XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        }
        XCTAssertTrue(scans.waitForExistence(timeout: 10)); scans.tap()
        let tile = app.buttons["ScanTile_00000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10)); tile.tap()
        tapProtectedChat(app)
    }

    private func tapProtectedChat(_ app: XCUIApplication) {
        let chat = app.buttons["FieldChatToolbarButton"]
        XCTAssertTrue(chat.waitForExistence(timeout: 10)); XCTAssertTrue(chat.isEnabled)
        XCTAssertTrue(app.frame.contains(chat.frame), chat.debugDescription)
        // The native toolbar's zero-size AX ancestor requires its measured center.
        chat.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func testRepeatedAudioInsightPresentation() {
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedQueuedAudioHandoffFlow"])
        defer { app.terminate() }
        let scans = app.buttons["MainTabBar_Scans"]
        XCTAssertTrue(scans.waitForExistence(timeout: 8))
        scans.tap()
        let tile = app.buttons["QueuedScanTile_ui_test_queued_audio_handoff"]
        var metrics: [XCTMetric] = [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)]
        if #available(iOS 26.0, *) {
            metrics.append(XCTHitchMetric(application: app))
        }
        measure(metrics: metrics, options: options) {
            XCTAssertTrue(tile.waitForExistence(timeout: 8))
            startMeasuring()
            tile.tap()
            XCTAssertTrue(app.otherElements["InsightSheetView"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["AudioPlaybackControl_ui_test_queued_audio_handoff.wav"].waitForExistence(timeout: 8))
            stopMeasuring()
            app.buttons["Back"].tap()
            XCTAssertTrue(tile.waitForExistence(timeout: 8))
        }
    }
}
