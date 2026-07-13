// BillClassificationUITests.swift
// HemvoUITests
//
// Drives the Budget tab and proves the isBill split: an expense saved with
// "Bill — pay later" ON is an unpaid bill and must appear under Upcoming Bills,
// not Recent Expenses — the bug where leaving "Recurring" off silently
// reclassified a bill as money already spent.
//
// Writes a real expense row to the signed-in household, so it is opt-in: set
// BILL_UI_PROBE=1 (pass it TEST_RUNNER_-prefixed so xcodebuild forwards it) and
// run against a simulator that is already signed in and subscribed. A normal ⌘U
// pass skips it. Delete the "Probe Bill" row afterwards.

import XCTest

final class BillClassificationUITests: XCTestCase {

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
    func testBillPayLaterLandsInUpcomingBills() throws {
        guard ProcessInfo.processInfo.environment["BILL_UI_PROBE"] == "1" else {
            throw XCTSkip("BILL_UI_PROBE not set — this test writes a real expense row")
        }

        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launch()

        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }

        // ── Budget tab ────────────────────────────────────────────────────
        let budgetTab = app.buttons["Budget"]
        guard budgetTab.waitForExistence(timeout: 20) else {
            throw XCTSkip("Budget tab never appeared — simulator is not signed in / subscribed.")
        }
        budgetTab.tap()

        let addExpense = app.buttons["Add Expense"]
        XCTAssertTrue(addExpense.waitForExistence(timeout: 10), "Budget dashboard never loaded")
        shoot(app, "01-budget-before")

        // ── Add an unpaid, non-repeating bill ─────────────────────────────
        addExpense.tap()

        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10), "Amount field missing")
        amount.tap()
        amount.typeText("70")

        let title = app.textFields["e.g. Electric Bill"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Title field missing")
        title.tap()
        title.typeText("Probe Bill")

        // Get the keyboard out of the way — it covers the Repeats picker and Save button.
        app.staticTexts["AMOUNT"].tap()

        // Title and amount are filled, but neither Bill nor Already Paid is on — the expense
        // is unfiled, and saving it is what used to drop an unpaid bill into Recent Expenses.
        let save = app.buttons["Save Expense"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Save button missing")
        XCTAssertFalse(save.isEnabled,
                       "Save was enabled with neither Bill nor Already Paid set")

        // OptionRow uses Toggle("", isOn:) — no label — so index it.
        // 0 = "Bill — pay later", 1 = "Already Paid". Leave Already Paid OFF: unpaid is the point.
        let billToggle = app.switches.element(boundBy: 0)
        XCTAssertTrue(billToggle.waitForExistence(timeout: 5), "Bill toggle missing")
        billToggle.tap()

        XCTAssertTrue(save.isEnabled, "Save stayed disabled after marking this a bill")

        shoot(app, "02-add-form-bill-on")

        // Flipping Bill on reveals the Repeats picker. Its chips are Buttons, and it must
        // default to One-time — a bill that quietly repeats because of a default is the
        // other half of the bug this change exists to fix.
        let oneTime = app.buttons["One-time"]
        XCTAssertTrue(oneTime.waitForExistence(timeout: 5),
                      "Repeats picker did not appear after enabling Bill")

        // A SwiftUI Button exposes no selected trait, so assert on the caption the picker
        // only renders for a nil rule — that copy IS the "One-time is selected" state.
        let oneTimeCaption = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH %@", "Reminded once, on the due date")
        ).firstMatch
        XCTAssertTrue(oneTimeCaption.waitForExistence(timeout: 3),
                      "Repeats picker did not default to One-time")

        save.tap()

        // ── The expense must land in Upcoming Bills ────────────────────────
        let saved = app.staticTexts["Probe Bill"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "Saved bill never appeared on the dashboard")

        // Bills / Recent sit below the fold — scroll them into frame so the screenshot
        // actually shows which card the bill landed in.
        app.swipeUp()
        app.swipeUp()
        shoot(app, "03-budget-after")

        // WarmBillRow (Upcoming Bills) is the only row that renders an urgency pill.
        // "Due today" next to our bill is therefore proof it rendered as a bill, not an expense.
        XCTAssertTrue(app.staticTexts["Due today"].exists,
                      "Bill did not render in Upcoming Bills — no urgency pill found")
    }
}
