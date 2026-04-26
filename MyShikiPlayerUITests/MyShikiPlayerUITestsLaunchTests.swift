//
//  MyShikiPlayerUITestsLaunchTests.swift
//  MyShikiPlayerUITests
//
//  Created by Антон Коренской on 07.04.2026.
//

import XCTest

final class MyShikiPlayerUITestsLaunchTests: XCTestCase {

    /// `true` runs per Light/Dark and can alter Appearance; `false` plus `SystemAppearancePreservation` restores `defaults`.
    override static var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        SystemAppearancePreservation.registerIfNeeded()
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
