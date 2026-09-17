import XCTest

@MainActor
final class RuntimePerformanceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        options.invocationOptions = [.manuallyStart]
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
