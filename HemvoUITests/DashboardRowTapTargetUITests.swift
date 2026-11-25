//  DashboardRowTapTargetUITests.swift
//  HemvoUITests
//
//  The Dashboard's Upcoming Events rows are Buttons whose label is an HStack with a
//  Spacer in it. SwiftUI hit-tests a plain-styled Button against the *drawn* content of
//  its label, so without `.contentShape(Rectangle())` the wide gap between the event
//  title and the trailing chevron swallows taps and only the text itself responds.
//
//  This test taps that gap — not the title, not the chevron — and asserts the tap both
//  left the Dashboard and opened the tapped event's detail sheet. It fails if the content
//  shape is ever dropped, or if the row stops opening the event.
//
//  Env-gated on SHOT_EMAIL / SHOT_PASSWORD like the other account-backed UI tests, so a
//  normal ⌘U pass skips it. The vars must be TEST_RUNNER_-prefixed *environment*
//  variables — passing them bare on the xcodebuild line makes them build settings, which
//  never reach the runner process and the test silently skips:
//
//    TEST_RUNNER_SHOT_EMAIL=… TEST_RUNNER_SHOT_PASSWORD=… \
//    xcodebuild -project Hemvo.xcodeproj -scheme Hemvo \
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
//      test -only-testing:HemvoUITests/DashboardRowTapTargetUITests

import XCTest

final class DashboardRowTapTargetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testUpcomingEventRowRespondsToATapInItsEmptyMiddle() throws {
        guard let email    = ProcessInfo.processInfo.environment["SHOT_EMAIL"],
              let password = ProcessInfo.processInfo.environment["SHOT_PASSWORD"] else {
            throw XCTSkip("SHOT_EMAIL / SHOT_PASSWORD not set — dashboard tap-target check")
        }

        let app = XCUIApplication()
        signIn(app, email: email, password: password)

        let header = app.staticTexts["Upcoming Events"]
        XCTAssertTrue(header.waitForExistence(timeout: 25), "Dashboard never showed the Upcoming Events card")

        // The rows sit directly under the card header. Take the first wide button below
        // it that isn't the header's own "Full Calendar" pill.
        let row = firstEventRow(in: app, below: header)
        guard let row else {
            throw XCTSkip("No upcoming events on this account — nothing to tap")
        }

        // 80% across the row is the dead zone: past the end of the title, short of the
        // chevron. Tapping by coordinate rather than .tap() so the tap lands there
        // whether or not XCUITest considers that point hittable.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()

        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: header)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed,
                       "Tapping the middle of an Upcoming Events row did nothing — the row's "
                       + "contentShape is missing, so only its drawn text is tappable.")

        // The tap should land on the Schedule tab *and* open that event's detail sheet.
        let sheetMarker = app.buttons["Edit"].firstMatch
        XCTAssertTrue(sheetMarker.waitForExistence(timeout: 10),
                      "Schedule opened but the event's detail sheet never appeared. "
                      + "UI: \(app.debugDescription.prefix(2500))")
    }

    // MARK: - Helpers

    private func firstEventRow(in app: XCUIApplication, below header: XCUIElement) -> XCUIElement? {
        let headerBottom = header.frame.maxY
        let candidates = app.buttons.allElementsBoundByIndex.filter {
            $0.exists
            && $0.frame.minY > headerBottom
            && $0.frame.width  > 200   // full-width row, not the "Full Calendar" pill
            && $0.frame.height > 30
        }
        return candidates.sorted { $0.frame.minY < $1.frame.minY }.first
    }

    private func signIn(_ app: XCUIApplication, email: String, password: String) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launch()

        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        let homeTab = app.buttons["Home"]
        if !homeTab.waitForExistence(timeout: 8) {
            let onboardingSignIn = app.buttons["Sign In"]
            XCTAssertTrue(onboardingSignIn.waitForExistence(timeout: 20), "Onboarding never appeared")
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

            XCTAssertTrue(homeTab.waitForExistence(timeout: 45), "Tab bar never appeared after login")
        }

        for _ in 0..<12 {
            let notNow = springboard.buttons["Not Now"]
            if notNow.exists && notNow.isHittable { notNow.tap(); break }
            let appNotNow = app.buttons["Not Now"]
            if appNotNow.exists && appNotNow.isHittable { appNotNow.tap(); break }
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
