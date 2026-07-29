// DemoDataSeedUITests.swift
// HemvoUITests
//
// Populates a household with realistic demo content through the app's own add flows, so the
// App Store screenshots (and the App Review tester's first login) show Hemvo actually in use
// instead of five empty states.
//
// It WRITES REAL ROWS to whatever account you sign in as, so it is env-gated and skips by
// default. Intended target is the App Review demo household:
//
//   TEST_RUNNER_SEED_DEMO=1 TEST_RUNNER_SHOT_EMAIL=… TEST_RUNNER_SHOT_PASSWORD=… xcodebuild \
//     -project Hemvo.xcodeproj -scheme Hemvo \
//     -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' \
//     -only-testing:HemvoUITests/DemoDataSeedUITests test
//
// Re-running it duplicates rows — seed once per household.

import XCTest

final class DemoDataSeedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSeedDemoData() throws {
        guard ProcessInfo.processInfo.environment["SEED_DEMO"] == "1",
              let email    = ProcessInfo.processInfo.environment["SHOT_EMAIL"],
              let password = ProcessInfo.processInfo.environment["SHOT_PASSWORD"] else {
            throw XCTSkip("SEED_DEMO / SHOT_EMAIL / SHOT_PASSWORD not set — this writes real rows")
        }

        let app         = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launch()

        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        try signIn(app: app, springboard: springboard, email: email, password: password)

        // Seeding is not idempotent — re-running duplicates rows. SEED_PHASES lets a partially
        // completed run be resumed without re-adding what already landed.
        let phases = Set((ProcessInfo.processInfo.environment["SEED_PHASES"]
                          ?? "meals,budget,events,tasks")
                         .split(separator: ",").map(String.init))

        if phases.contains("meals")  { seedMeals(app) }
        if phases.contains("budget") { seedBudget(app) }
        if phases.contains("events") { seedEvents(app) }
        if phases.contains("tasks")  { seedTasks(app) }
    }

    // MARK: - Sign in

    private func signIn(app: XCUIApplication,
                        springboard: XCUIApplication,
                        email: String,
                        password: String) throws {
        let homeTab = app.buttons["Home"]
        if homeTab.waitForExistence(timeout: 8) { return }

        let onboardingSignIn = app.buttons["Sign In"]
        XCTAssertTrue(onboardingSignIn.waitForExistence(timeout: 20),
                      "Neither tab bar nor onboarding appeared")
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
                      "Tab bar never appeared after login. UI: \(app.debugDescription.prefix(3000))")

        for _ in 0..<12 {
            let notNow = springboard.buttons["Not Now"]
            if notNow.exists && notNow.isHittable { notNow.tap(); break }
            let appNotNow = app.buttons["Not Now"]
            if appNotNow.exists && appNotNow.isHittable { appNotNow.tap(); break }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        let button = app.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "Tab '\(name)' missing")
        button.tap()
        Thread.sleep(forTimeInterval: 2)
    }

    // MARK: - Meals

    private func seedMeals(_ app: XCUIApplication) {
        tab(app, "Meals")

        let meals = [
            ("Plan breakfast", "Blueberry Pancakes"),
            ("Plan lunch",     "Chicken Caesar Wrap"),
            ("Plan dinner",    "Lemon Herb Salmon")
        ]

        for (entry, name) in meals {
            let addButton = app.buttons[entry]
            guard addButton.waitForExistence(timeout: 10) else {
                XCTFail("'\(entry)' button not found — meal section may already be filled")
                continue
            }
            addButton.tap()

            let nameField = app.textFields["Meal name (e.g. Pasta Primavera)"]
            XCTAssertTrue(nameField.waitForExistence(timeout: 10), "Add Meal sheet did not open")
            nameField.tap()
            nameField.typeText(name)

            let save = app.buttons["Save"]
            XCTAssertTrue(save.waitForExistence(timeout: 5), "Meal Save button missing")
            save.tap()

            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 15),
                          "Meal '\(name)' never appeared in the planner")
        }
    }

    // MARK: - Budget

    /// (title, amount, paid) — paid expenses drive Spending by Category and the spent total;
    /// unpaid ones land in Upcoming Bills. Both cards need content to photograph well.
    private func seedBudget(_ app: XCUIApplication) {
        tab(app, "Budget")

        let expenses: [(String, String, Bool)] = [
            ("Weekly Groceries", "142.60", true),
            ("Electric Bill",    "118.40", false),
            ("Internet",          "79.99", false),
            ("Hardware Store",    "64.25", true)
        ]

        for (title, amount, paid) in expenses {
            let addExpense = app.buttons["Add Expense"]
            XCTAssertTrue(addExpense.waitForExistence(timeout: 15), "Budget dashboard never loaded")
            addExpense.tap()

            let amountField = app.textFields["0.00"]
            XCTAssertTrue(amountField.waitForExistence(timeout: 10), "Amount field missing")
            amountField.tap()
            amountField.typeText(amount)

            let titleField = app.textFields["e.g. Electric Bill"]
            XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Title field missing")
            titleField.tap()
            titleField.typeText(title)

            // Keyboard covers the toggles and Save button.
            app.staticTexts["AMOUNT"].tap()

            // OptionRow uses Toggle("", isOn:) with no label — index it.
            // 0 = "Bill — pay later", 1 = "Already Paid".
            let toggle = app.switches.element(boundBy: paid ? 1 : 0)
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Expense toggle missing")
            toggle.tap()

            let save = app.buttons["Save Expense"]
            XCTAssertTrue(save.waitForExistence(timeout: 5), "Save Expense missing")
            XCTAssertTrue(save.isEnabled, "Save Expense stayed disabled for '\(title)'")
            save.tap()

            XCTAssertTrue(app.buttons["Add Expense"].waitForExistence(timeout: 15),
                          "Add Expense sheet did not close after saving '\(title)'")
            Thread.sleep(forTimeInterval: 1)
        }
    }

    // MARK: - Schedule

    private func seedEvents(_ app: XCUIApplication) {
        tab(app, "Schedule")

        let events = [
            ("Dentist Appointment", "Bright Smile Dental"),
            ("Soccer Practice",     "Riverside Park"),
            ("Family Movie Night",  "Living Room")
        ]

        for (title, location) in events {
            let addEvent = app.buttons["Add Event"]
            XCTAssertTrue(addEvent.waitForExistence(timeout: 15), "Add Event button missing")
            addEvent.tap()

            // The calendar presents NativeAddEventSheet (FamilyCalendarView), not AddEventView —
            // its placeholder is the bare "Title".
            let titleField = app.textFields["Title"]
            XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Add Event sheet did not open")
            titleField.tap()
            titleField.typeText(title)

            let locationField = app.textFields["Location"]
            if locationField.exists {
                locationField.tap()
                locationField.typeText(location)
            }

            let save = app.buttons["Save"]
            XCTAssertTrue(save.waitForExistence(timeout: 5), "Event Save button missing")
            save.tap()

            XCTAssertTrue(app.buttons["Add Event"].waitForExistence(timeout: 15),
                          "Add Event sheet did not close after saving '\(title)'")
            Thread.sleep(forTimeInterval: 1)
        }
    }

    // MARK: - Maintenance

    private func seedTasks(_ app: XCUIApplication) {
        tab(app, "Fix-It")

        let tasks = ["Replace HVAC Filter", "Clean Gutters", "Test Smoke Alarms"]

        for title in tasks {
            let addTask = app.buttons["Add Task"]
            XCTAssertTrue(addTask.waitForExistence(timeout: 15), "Add Task button missing")
            addTask.tap()

            let titleField = app.textFields["e.g. Replace HVAC Filter"]
            XCTAssertTrue(titleField.waitForExistence(timeout: 10), "New Task sheet did not open")
            titleField.tap()
            titleField.typeText(title)

            // Dismiss the keyboard so the bottom Save button is reachable. Do NOT tap the "Done"
            // toolbar item — it is a cancellationAction and throws the sheet away.
            app.staticTexts["TASK NAME"].tap()

            // The sheet's own save button carries the same "Add Task" label as the FAB behind it,
            // but the FAB is covered while the sheet is up, so any *hittable* match is the sheet's.
            // It sits at the bottom of a long scroll view, below frequency/time/date/assignee —
            // scroll until it comes into reach.
            var save: XCUIElement?
            for _ in 0..<6 {
                let saves = app.buttons.matching(NSPredicate(format: "label == 'Add Task'"))
                if let hit = saves.allElementsBoundByIndex.last(where: { $0.isHittable }) {
                    save = hit
                    break
                }
                app.swipeUp()
                Thread.sleep(forTimeInterval: 0.5)
            }
            guard let save else {
                XCTFail("Sheet's Add Task save button not found for '\(title)'")
                continue
            }
            save.tap()

            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 15),
                          "Task '\(title)' never appeared in the list")
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
