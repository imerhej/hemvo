// ResetPasswordFlowUITests.swift
// HemvoUITests
//
// Drives the forgot-password deep-link flow end to end:
//   1. Launch the app logged out.
//   2. Open a real hemvo://reset-password#access_token=… recovery deep link
//      (minted outside the test and passed in via the RESET_URL env var —
//      run with TEST_RUNNER_RESET_URL=… so xcodebuild forwards it).
//   3. Type the new password into ResetPasswordView and tap Update Password.
//   4. Assert the success state appears and Go to Sign In returns to onboarding.
//
// The test skips itself when RESET_URL is not provided, so it never runs
// (or fails) as part of a normal ⌘U test pass — recovery links are single-use
// and must be generated per run.

import XCTest

final class ResetPasswordFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testResetPasswordDeepLinkFlow() throws {
        guard let urlString = ProcessInfo.processInfo.environment["RESET_URL"],
              let url = URL(string: urlString) else {
            throw XCTSkip("RESET_URL env var not set — mint a recovery link and pass TEST_RUNNER_RESET_URL to xcodebuild")
        }
        let newPassword = ProcessInfo.processInfo.environment["RESET_NEW_PASSWORD"] ?? "GlitchRepro2026B"
        let coldStart   = ProcessInfo.processInfo.environment["RESET_COLD_START"] == "1"

        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        if coldStart {
            // Real-world path: the app is not running and the email link launches it.
            XCUIDevice.shared.system.open(url)
        } else {
            app.launch()
            // Dismiss the notification-permission alert if it shows up.
            let allow = springboard.alerts.buttons["Allow"]
            if allow.waitForExistence(timeout: 5) { allow.tap() }
            // Open the recovery deep link exactly like tapping the email link.
            XCUIDevice.shared.system.open(url)
        }

        // A notification-permission alert can also appear over the cold-started app.
        let allowLate = springboard.alerts.buttons["Allow"]
        if allowLate.waitForExistence(timeout: 3) { allowLate.tap() }

        // ResetPasswordView should appear as a full-screen cover.
        let newPw = app.secureTextFields["Min 8 chars, 1 uppercase, 1 number"]
        XCTAssertTrue(newPw.waitForExistence(timeout: 20),
                      "ResetPasswordView never appeared after opening the deep link")

        // The view auto-focuses the field 0.5 s after appearing; wait that out
        // so our tap and the auto-focus don't fight.
        Thread.sleep(forTimeInterval: 1.5)

        newPw.tap()
        newPw.typeText(newPassword)

        let confirm = app.secureTextFields["Repeat new password"]
        confirm.tap()
        confirm.typeText(newPassword)

        let update = app.buttons["Update Password"]
        XCTAssertTrue(update.waitForExistence(timeout: 5), "Update Password button not found")
        XCTAssertTrue(update.isEnabled, "Update Password button is disabled — checklist not satisfied")
        update.tap()

        // Wait for either the success header or an inline error.
        let success = app.staticTexts["Password Updated!"]
        let succeeded = success.waitForExistence(timeout: 30)
        if !succeeded {
            let hierarchy = app.debugDescription
            XCTFail("Never reached success state after tapping Update Password. UI now: \(hierarchy.prefix(4000))")
        }

        let goToSignIn = app.buttons["Go to Sign In"]
        XCTAssertTrue(goToSignIn.waitForExistence(timeout: 5))
        goToSignIn.tap()

        // Back at onboarding: the cover must be gone and the app responsive.
        let signInButton = app.buttons["Sign In"]
        let backAtOnboarding = signInButton.waitForExistence(timeout: 15)
        XCTAssertTrue(backAtOnboarding,
                      "Did not return to onboarding after Go to Sign In. UI now: \(app.debugDescription.prefix(4000))")
    }
}
