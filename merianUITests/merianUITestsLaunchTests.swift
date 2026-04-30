//
//  merianUITestsLaunchTests.swift
//  merianUITests
//
//  Created by Emre Erdener on 3/6/26.
//

import XCTest

final class merianUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = UITestAppLauncher.makeConfiguredApp()
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
