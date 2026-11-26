import XCTest

final class PhotoSelectionUITests: XCTestCase {
    @MainActor
    func testTapRetapCornersPanZoomRotateAndClear() throws {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedPhotoSelectionReview"])
        let preview = app.descendants(matching: .any)["CapturePhotoPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        // XCTest's synthesized pinch factor is not an exact model scale. Zoom
        // before selecting, then zoom out below to preserve the selected source.
        preview.pinch(withScale: 1.2, velocity: 1)
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let clear = app.buttons["clearPhotoSelection"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        let first = try selection(app)
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).tap()
        let moved = try selection(app)
        XCTAssertGreaterThan(moved.minX, first.minX)
        XCTAssertEqual(moved.width, first.width, accuracy: 0.001)
        XCTAssertEqual(moved.height, first.height, accuracy: 0.001)

        let corner = app.descendants(matching: .any)["photoSelection.topLeft"]
        XCTAssertTrue(corner.isHittable)
        XCTAssertGreaterThanOrEqual(corner.frame.width, 44)
        let start = corner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -18, dy: -18)))
        let resized = try selection(app)
        XCTAssertLessThan(resized.minX, moved.minX)
        XCTAssertEqual(resized.maxX, moved.maxX, accuracy: 0.002)
        XCTAssertEqual(resized.maxY, moved.maxY, accuracy: 0.002)

        let beforePan = app.staticTexts["PhotoSelectionSource"].value as? String
        let center = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 0, dy: 18)))
        assertSameSelection(try selection(app), resized)
        XCTAssertNotEqual(app.staticTexts["PhotoSelectionSource"].value as? String, beforePan)
        app.buttons["Rotate right"].tap()
        assertSameSelection(try selection(app), resized)
        recordGeometry(app, stage: "Before pinch out")
        preview.pinch(withScale: 0.8, velocity: -1)
        recordGeometry(app, stage: "After pinch out")
        assertSameSelection(try selection(app), resized)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Manual subject selection after corner resize pan zoom and rotation"
        shot.lifetime = .keepAlways; add(shot)
        clear.tap()
        XCTAssertEqual(app.staticTexts["PhotoSelectionSource"].label, "none")
        XCTAssertFalse(corner.exists)
        XCTAssertTrue(app.staticTexts["Naturebook will find the subject automatically."].exists)
    }

    @MainActor
    private func recordGeometry(_ app: XCUIApplication, stage: String) {
        let state = app.staticTexts["PhotoSelectionSource"]
        let value = state.label + " " + (state.value as? String ?? "missing framing")
        let attachment = XCTAttachment(string: value)
        attachment.name = stage; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor
    func testPanAndPinchDoNotCreateSelection() {
        continueAfterFailure = false
        let app = UITestAppLauncher.launchConfiguredApp(extraArguments: ["-seedPhotoSelectionReview"])
        let preview = app.descendants(matching: .any)["CapturePhotoPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        preview.pinch(withScale: 1.5, velocity: 1)
        preview.swipeUp()
        XCTAssertEqual(app.staticTexts["PhotoSelectionSource"].label, "none")
        XCTAssertFalse(app.buttons["clearPhotoSelection"].exists)
    }

    @MainActor
    private func selection(_ app: XCUIApplication) throws -> CGRect {
        let values = app.staticTexts["PhotoSelectionSource"].label.split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(values.count, 4)
        guard values.count == 4 else { throw NSError(domain: "PhotoSelectionUITests", code: 1) }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    private func assertSameSelection(_ actual: CGRect, _ expected: CGRect) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.002)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.002)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.002)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.002)
    }
}
