// ChangePasswordFlowUITests.swift
// HemvoUITests
//
// Drives the authenticated change-password flow end to end:
//   1. Launch logged out and sign in with a test account
//      (CHANGE_PW_EMAIL / CHANGE_PW_CURRENT env vars — pass TEST_RUNNER_-
//      prefixed so xcodebuild forwards them).
//   2. Dashboard → Settings (hamburger) → Edit Profile → Security tab.
//   3. Fill current/new/confirm and tap Update Password.
//   4. Assert the success toast appears and the app is still running.
//
// Skips itself when the env vars are missing so a normal ⌘U pass never
// runs it (it mutates the test account's real password).

import XCTest

final class ChangePasswordFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testChangePasswordFlow() throws {
        guard let email      = ProcessInfo.processInfo.environment["CHANGE_PW_EMAIL"],
              let currentPw  = ProcessInfo.processInfo.environment["CHANGE_PW_CURRENT"] else {
            throw XCTSkip("CHANGE_PW_EMAIL / CHANGE_PW_CURRENT env vars not set")
        }
        let newPw = ProcessInfo.processInfo.environment["CHANGE_PW_NEW"] ?? "ChangePwNew2026y7"

        let app         = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launch()

        // Notification-permission alert can appear over a fresh install.
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        // ── Sign in ────────────────────────────────────────────────────────
        let onboardingSignIn = app.buttons["Sign In"]
        XCTAssertTrue(onboardingSignIn.waitForExistence(timeout: 15),
                      "Onboarding Sign In button never appeared — is the sim already logged in?")
        onboardingSignIn.tap()

        let emailField = app.textFields["Email or Username"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Login form did not appear")
        emailField.tap()
        emailField.typeText(email)

        let pwField = app.secureTextFields["Password"]
        pwField.tap()
        pwField.typeText(currentPw)

        // Two "Sign In" buttons exist (onboarding underneath + submit); the
        // submit is the hittable one inside the full-screen cover.
        let submits = app.buttons.matching(NSPredicate(format: "label == 'Sign In'"))
        submits.allElementsBoundByIndex.last(where: { $0.isHittable })?.tap()

        // Password-manager save prompt may appear (springboard or in-process).
        let notNow = springboard.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
        let appNotNow = app.buttons["Not Now"]
        if appNotNow.waitForExistence(timeout: 2) { appNotNow.tap() }

        // ── Dashboard → Settings ───────────────────────────────────────────
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 30),
                      "Dashboard never appeared after login. UI now: \(app.debugDescription.prefix(3000))")
        settingsButton.tap()

        let editProfile = app.buttons["Edit Profile"]
        XCTAssertTrue(editProfile.waitForExistence(timeout: 10), "Settings sheet did not appear")
        editProfile.tap()

        // ── Profile → Security tab ─────────────────────────────────────────
        let securityTab = app.buttons["Security"]
        XCTAssertTrue(securityTab.waitForExistence(timeout: 10), "Profile view did not appear")
        securityTab.tap()

        let currentField = app.secureTextFields["Current Password"]
        XCTAssertTrue(currentField.waitForExistence(timeout: 10), "Security tab did not appear")
        currentField.tap()
        currentField.typeText(currentPw)

        let newField = app.secureTextFields["New Password"]
        newField.tap()
        newField.typeText(newPw)

        let confirmField = app.secureTextFields["Confirm New Password"]
        confirmField.tap()
        confirmField.typeText(newPw)

        // Dismiss the keyboard so the button is reachable, then update.
        if app.keyboards.buttons["done"].exists { app.keyboards.buttons["done"].tap() }

        let update = app.buttons["Update Password"]
        XCTAssertTrue(update.waitForExistence(timeout: 5), "Update Password button not found")
        if !update.isHittable { app.swipeUp() }
        XCTAssertTrue(update.isEnabled, "Update Password disabled — checklist not satisfied")
        update.tap()

        // ── Outcome ────────────────────────────────────────────────────────
        let success = app.staticTexts["Password updated successfully!"]
        let succeeded = success.waitForExistence(timeout: 30)

        if app.state != .runningForeground {
            XCTFail("APP CRASHED or exited during password change (state: \(app.state.rawValue))")
        }
        if !succeeded {
            XCTFail("No success toast after Update Password. UI now: \(app.debugDescription.prefix(4000))")
        }

        // Give the post-success work (local notification, email fn) a moment
        // to run — the reported crash may occur after the toast.
        Thread.sleep(forTimeInterval: 5)
        XCTAssertEqual(app.state, .runningForeground,
                       "App crashed shortly AFTER the success toast")
    }
}
