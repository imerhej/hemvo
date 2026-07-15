// BillCardLayoutUITests.swift
// HemvoUITests
//
// Screenshots the redesigned bill cards so the cadence pills ("Weekly", "Monthly") can be
// checked for the mid-word wrap they used to suffer, and the "Created by …" byline confirmed.
//
// Read-only: it opens the Manage and History sheets and captures them, writing nothing. Still
// opt-in, because it needs a simulator that is already signed in, subscribed, and has bills:
// run with TEST_RUNNER_BILL_LAYOUT_PROBE=1 so xcodebuild forwards it.

import XCTest

final class BillCardLayoutUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testBillCardsRenderPillsAndByline() throws {
        guard ProcessInfo.processInfo.environment["BILL_LAYOUT_PROBE"] == "1" else {
            throw XCTSkip("BILL_LAYOUT_PROBE not set — screenshot probe, needs a signed-in simulator")
        }

        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launch()

        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }

        let budgetTab = app.buttons["Budget"]
        guard budgetTab.waitForExistence(timeout: 20) else {
            throw XCTSkip("Budget tab never appeared — simulator is not signed in / subscribed.")
        }
        budgetTab.tap()

        // ── Manage sheet (BillReminderView) ───────────────────────────────
        let manage = app.buttons["Manage"]
        XCTAssertTrue(manage.waitForExistence(timeout: 10), "Budget dashboard never loaded")
        manage.tap()

        XCTAssertTrue(app.staticTexts["BILL REMINDERS"].waitForExistence(timeout: 10),
                      "Bill reminders sheet never opened")
        shoot(app, "01-manage-top")

        // Slow drags that keep the finger down, so an external capture loop can catch the Add Bill
        // button mid-scroll while it is tucked away. XCUITest screenshots always wait for idle, by
        // which point it has already slid back.
        let low  = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        for _ in 0..<4 {
            low.press(forDuration: 0.1,
                      thenDragTo: high,
                      withVelocity: .slow,
                      thenHoldForDuration: 1.0)
        }

        // Back at idle the button must have returned — a FAB stuck off-screen would make
        // adding a bill impossible.
        let addBill = app.buttons["Add Bill"]
        XCTAssertTrue(addBill.waitForExistence(timeout: 5), "Add Bill button missing after scrolling")
        XCTAssertTrue(addBill.isHittable, "Add Bill button stayed tucked away after scrolling stopped")
        shoot(app, "02-manage-scrolled")

        app.buttons["Done"].firstMatch.tap()

        // ── History sheet (BillHistoryView) ───────────────────────────────
        let history = app.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 10), "History button missing")
        history.tap()

        XCTAssertTrue(app.staticTexts["EXPENSE HISTORY"].waitForExistence(timeout: 10),
                      "History sheet never opened")
        shoot(app, "03-history-top")
        app.swipeUp()
        shoot(app, "04-history-scrolled")
    }
}
