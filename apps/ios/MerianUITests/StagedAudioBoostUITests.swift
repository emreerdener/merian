import XCTest

final class StagedAudioBoostUITests: XCTestCase {
    @MainActor
    func testFieldNotesReturnToSameReviewAndKeepIdentifyAboveKeyboard() throws {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: [
            "-seedStagedAudioReviewFlow", "-mockCaptureReviewLocation",
            "-captureModeOrder", "audio,visual",
            "-hasShownCaptureNoteTip", "YES", "-hasShownCaptureSubmitTip", "YES"
        ])
        let audio = app.buttons["StagedAudioBadge_0"]
        XCTAssertTrue(audio.waitForExistence(timeout: 8))
        audio.tap()
        XCTAssertTrue(app.staticTexts["Review audio"].waitForExistence(timeout: 8))
        app.buttons["CaptureFieldNotes"].tap()
        // Multiline SwiftUI text input uses different accessibility roles across runtimes.
        let input = app.descendants(matching: .any)["DescribeTextInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Synthetic field note")
        let identify = app.buttons["Identify"]
        XCTAssertTrue(identify.isHittable)
        XCTAssertFalse(app.buttons["DescribeKeyboardDone"].exists)
        XCTAssertLessThanOrEqual(identify.frame.maxY, app.keyboards.firstMatch.frame.minY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Review Field notes with keyboard and Identify"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["FieldNotesClose"].tap()
        XCTAssertTrue(app.staticTexts["Review audio"].waitForExistence(timeout: 5))
        app.buttons["CaptureFieldNotes"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Synthetic field note")
        app.buttons["FieldNotesClose"].tap()
        app.buttons["Add media"].tap()
        XCTAssertTrue(audio.waitForExistence(timeout: 5))
        audio.tap()
        XCTAssertTrue(app.staticTexts["Review audio"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStagedAudioBoostPreparesAndCanBeReverted() throws {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: [
            "-seedStagedAudioReviewFlow", "-mockCaptureReviewLocation", "-captureModeOrder", "audio,visual,describe",
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
        app.buttons["Add media"].tap()
        XCTAssertTrue(audio.waitForExistence(timeout: 4))
        audio.tap()
        XCTAssertTrue(boost.waitForExistence(timeout: 8))
        XCTAssertFalse(boosted.exists)
    }
}
