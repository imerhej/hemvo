// InviteeScopeUITests.swift
// HemvoUITests
//
// Verifies the Invitees section only appears for Personal events and is
// hidden for Household events (which are shared with every member, so
// per-person invitees are implicit).
//
// Assumes the simulator already has a logged-in, subscribed session
// (launch lands on the Dashboard). Screenshots are attached at each state
// for visual confirmation via `xcresulttool export attachments`.

import XCTest

final class InviteeScopeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testInviteesHiddenForHouseholdScope() throws {
        let app         = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launch()

        // A notification-permission alert can sit over a fresh launch.
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        // ── Schedule tab → Add Event ───────────────────────────────────────
        let scheduleTab = app.buttons["Schedule"]
        XCTAssertTrue(scheduleTab.waitForExistence(timeout: 30),
                      "Schedule tab never appeared — is the sim logged in? UI: \(app.debugDescription.prefix(2000))")
        scheduleTab.tap()

        let addEvent = app.buttons["Add Event"]
        XCTAssertTrue(addEvent.waitForExistence(timeout: 10), "Add Event button not found")
        addEvent.tap()

        // ── Default scope is Personal → Invitees visible ───────────────────
        let invitees = app.staticTexts["Invitees"]
        XCTAssertTrue(invitees.waitForExistence(timeout: 10),
                      "Invitees section not shown for the default Personal scope")
        attach(app, name: "01-personal-invitees-visible")

        // ── Switch to Household → Invitees hidden ──────────────────────────
        let household = app.buttons["Household"]
        XCTAssertTrue(household.waitForExistence(timeout: 5), "Household segment not found")
        household.tap()

        let hidden = invitees.waitForNonExistence(timeout: 5)
        attach(app, name: "02-household-invitees-hidden")
        XCTAssertTrue(hidden, "Invitees section still visible after switching to Household")

        // ── Back to Personal → Invitees returns ────────────────────────────
        let personal = app.buttons["Personal"]
        XCTAssertTrue(personal.waitForExistence(timeout: 5), "Personal segment not found")
        personal.tap()
        XCTAssertTrue(invitees.waitForExistence(timeout: 5),
                      "Invitees section did not return after switching back to Personal")
        attach(app, name: "03-back-to-personal-invitees-visible")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
