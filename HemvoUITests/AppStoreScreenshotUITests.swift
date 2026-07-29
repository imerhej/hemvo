// AppStoreScreenshotUITests.swift
// HemvoUITests
//
// Captures App Store screenshots that show the app actually in use — the fix for the
// Guideline 2.3.3 rejection ("screenshots do not show the actual app in use"). It signs in,
// then walks every tab and captures a full-resolution screenshot of each.
//
// Run it against whichever simulator matches the size class you need (6.7" = iPhone 14 Pro Max,
// 6.5" = iPhone 11 Pro Max), then pull the PNGs out of the result bundle:
//
//   SHOT_EMAIL=… SHOT_PASSWORD=… xcodebuild \
//     -project Hemvo.xcodeproj -scheme Hemvo \
//     -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' \
//     -only-testing:HemvoUITests/AppStoreScreenshotUITests \
//     -resultBundlePath /tmp/shots-67.xcresult test
//   xcrun xcresulttool export attachments --path /tmp/shots-67.xcresult --output-path /tmp/shots-67
//
// Skips itself unless SHOT_EMAIL / SHOT_PASSWORD are set, so a normal ⌘U pass never runs it.
// It only reads — no rows are written.

import XCTest

final class AppStoreScreenshotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func goToTab(_ app: XCUIApplication, _ name: String) {
        let button = app.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "Tab '\(name)' not found")
        button.tap()
        Thread.sleep(forTimeInterval: 4)
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        guard let email    = ProcessInfo.processInfo.environment["SHOT_EMAIL"],
              let password = ProcessInfo.processInfo.environment["SHOT_PASSWORD"] else {
            throw XCTSkip("SHOT_EMAIL / SHOT_PASSWORD not set — App Store screenshot capture")
        }

        let app         = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launch()

        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        // ── Sign in (skipped when the sim already holds a Keychain session) ──
        let homeTab = app.buttons["Home"]
        if !homeTab.waitForExistence(timeout: 8) {
            let onboardingSignIn = app.buttons["Sign In"]
            XCTAssertTrue(onboardingSignIn.waitForExistence(timeout: 20),
                          "Neither the tab bar nor onboarding appeared. UI: \(app.debugDescription.prefix(3000))")
            onboardingSignIn.tap()

            let emailField = app.textFields["Email or Username"]
            XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Login form did not appear")
            emailField.tap()
            emailField.typeText(email)

            let pwField = app.secureTextFields["Password"]
            pwField.tap()
            pwField.typeText(password)

            let submits = app.buttons.matching(NSPredicate(format: "label == 'Sign In'"))
            submits.allElementsBoundByIndex.last(where: { $0.isHittable })?.tap()

            XCTAssertTrue(homeTab.waitForExistence(timeout: 45),
                          "Tab bar never appeared after login — is the account past the paywall? UI: \(app.debugDescription.prefix(3000))")
        }

        // The iCloud Keychain "Save Password?" sheet arrives *after* the dashboard renders, so it
        // has to be swatted here rather than right after the Sign In tap — otherwise it lands on
        // top of the first screenshot. Poll, because its timing drifts.
        for _ in 0..<12 {
            let notNow = springboard.buttons["Not Now"]
            if notNow.exists && notNow.isHittable { notNow.tap(); break }
            let appNotNow = app.buttons["Not Now"]
            if appNotNow.exists && appNotNow.isHittable { appNotNow.tap(); break }
            Thread.sleep(forTimeInterval: 1)
        }

        // Let the dashboard settle so nothing is captured mid-fetch.
        Thread.sleep(forTimeInterval: 6)
        shoot(app, "01-home")

        // The demo account is held past the paywall with a far-future trial_end_date, which the
        // dashboard renders as an absurd "1,251 days left in your trial" banner mid-screen. A
        // scrolled variant pushes it out of frame while still showing real content.
        app.swipeUp()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "01b-home-scrolled")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "01c-home-scrolled-more")

        goToTab(app, "Meals")
        shoot(app, "02-meals")

        goToTab(app, "Budget")
        shoot(app, "03-budget")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "03b-budget-bills")

        goToTab(app, "Schedule")
        shoot(app, "04-schedule-month")
        // The month grid is mostly empty cells; the week view actually shows the events. The
        // toggle is an icon-only Button, so XCUITest labels it with the SF Symbol name.
        let gridToggle = app.buttons["rectangle.grid.1x2"]
        if gridToggle.waitForExistence(timeout: 5) {
            gridToggle.tap()
            Thread.sleep(forTimeInterval: 3)
            shoot(app, "04b-schedule-week")
        }

        goToTab(app, "Fix-It")
        shoot(app, "05-fix-it")

        // Dump the final hierarchy so unexpected overlays (trial banners, popups) are diagnosable.
        print("FINAL_UI_DUMP >>>\n\(app.debugDescription.prefix(6000))\n<<< END")
    }
}
