import XCTest

final class StagedAudioBoostUITests: XCTestCase {
    @MainActor
    func testStagedAudioBoostPreparesAndCanBeReverted() throws {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: [
            "-seedStagedAudioReviewFlow", "-captureModeOrder", "audio,visual,describe",
            "-hasShownCaptureNoteTip", "YES"
        ])
        let audio = app.buttons["StagedAudioBadge_0"]
        XCTAssertTrue(audio.waitForExistence(timeout: 8))
        audio.tap()
        let boost = app.buttons["Boost audio"]
        XCTAssertTrue(boost.waitForExistence(timeout: 8))
        boost.tap()
        let boosted = app.buttons["Turn off audio boost"]
        XCTAssertTrue(boosted.waitForExistence(timeout: 8))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Staged audio boosted playback"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        boosted.tap()
        XCTAssertTrue(boost.waitForExistence(timeout: 8))
        app.buttons["Close audio preview"].tap()
        XCTAssertTrue(audio.waitForExistence(timeout: 4))
        audio.tap()
        XCTAssertTrue(boost.waitForExistence(timeout: 8))
        XCTAssertFalse(boosted.exists)
    }
}
