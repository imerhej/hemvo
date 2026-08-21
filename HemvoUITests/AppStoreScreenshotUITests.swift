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


    /// Taps the first hittable button matching one of `candidates`, trying an exact
    /// label first and then a substring match. SwiftUI concatenates every Text inside
    /// a Button into one label — a meal row reads "Sheet-Pan Chicken Fajitas, 35 min,
    /// 5 srv" — so substring matching is what actually lands these taps.
    @discardableResult
    private func tapAny(_ app: XCUIApplication, _ candidates: [String], timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for name in candidates {
                let exact = app.buttons[name]
                if exact.exists && exact.isHittable { exact.tap(); return true }
                let fuzzy = app.buttons
                    .matching(NSPredicate(format: "label CONTAINS[c] %@", name))
                    .allElementsBoundByIndex
                    .first { $0.isHittable }
                if let fuzzy { fuzzy.tap(); return true }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    /// Closes the presented sheet and blocks until the tab bar is reachable again.
    /// A sheet left open silently poisons every later capture — the tab taps land on
    /// the sheet instead — so this reports failure rather than pressing on blindly.
    @discardableResult
    private func dismissSheet(_ app: XCUIApplication, _ label: String) -> Bool {
        for attempt in 0..<4 {
            if attempt > 0 { app.swipeDown(velocity: .fast) }
            tapAny(app, ["Close", "Done", "Cancel"], timeout: 3)
            Thread.sleep(forTimeInterval: 2)
            if app.buttons["Home"].isHittable { return true }
        }
        print("SHOT_WARN: could not dismiss the \(label) sheet")
        return false
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

    // MARK: - Extended set
    //
    // A wider pass for refreshing the App Store listing: it covers the screens the
    // original five never showed — Home, the grocery list, a recipe, the week calendar,
    // the personal budget scope, maintenance history and the household roster —
    // alongside refreshed versions of the shipped five.
    //
    // Seed the account first; dates are anchored to CURRENT_DATE, so re-seed on the
    // day you capture:
    //
    //   supabase db query --linked -f scripts/seed-screenshot-data.sql
    //   xcrun simctl status_bar <sim-id> override --time "7:41" \
    //       --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
    //   TEST_RUNNER_SHOT_EMAIL=… TEST_RUNNER_SHOT_PASSWORD=… xcodebuild … \
    //     -only-testing:HemvoUITests/AppStoreScreenshotUITests/testCaptureExtendedScreenshots \
    //     -resultBundlePath /tmp/shots-67.xcresult test
    //
    // Set the status bar clock to match the dashboard greeting for the hour you run in
    // ("Good evening" from 17:00) — Apple's canonical 9:41 contradicts an evening capture.
    //
    // Sheet-presented screens are captured *after* their tab, and the Settings detour is
    // deliberately last: a sheet that fails to close would otherwise swallow the taps
    // meant for every tab that follows.
    @MainActor
    func testCaptureExtendedScreenshots() throws {
        guard let email    = ProcessInfo.processInfo.environment["SHOT_EMAIL"],
              let password = ProcessInfo.processInfo.environment["SHOT_PASSWORD"] else {
            throw XCTSkip("SHOT_EMAIL / SHOT_PASSWORD not set — App Store screenshot capture")
        }

        let app = XCUIApplication()
        signIn(app, email: email, password: password)

        // ── Home ────────────────────────────────────────────────────────────────────
        Thread.sleep(forTimeInterval: 6)
        shoot(app, "01-home")
        // The demo account owns the household, so a trial banner sits below the quick
        // stats. One swipe puts the events / grocery / maintenance sections in frame
        // with the banner scrolled off.
        app.swipeUp()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "02-home-sections")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "03-home-sections-more")

        // ── Meals ───────────────────────────────────────────────────────────────────
        goToTab(app, "Meals")
        shoot(app, "04-meals-week")

        // Recipe detail — the dinner rows carry full ingredient lists.
        if tapAny(app, ["Sheet-Pan Chicken Fajitas", "Lemon Herb Salmon", "Sunday Pot Roast"]) {
            Thread.sleep(forTimeInterval: 3)
            shoot(app, "05-meal-detail")
            app.swipeUp()
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "06-meal-detail-ingredients")
            dismissSheet(app, "meal detail")
        } else {
            print("SHOT_WARN: no meal row was tappable")
        }

        // Grocery list — auto-built from those ingredient lists, plus manual staples.
        goToTab(app, "Meals")
        if tapAny(app, ["Cart", "cart.fill", "cart"]) {
            Thread.sleep(forTimeInterval: 4)
            shoot(app, "07-grocery-list")
            app.swipeUp()
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "08-grocery-list-scrolled")
            dismissSheet(app, "grocery list")
        } else {
            print("SHOT_WARN: grocery cart button not found")
        }

        // ── Budget ──────────────────────────────────────────────────────────────────
        goToTab(app, "Budget")
        shoot(app, "09-budget-overview")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "10-budget-categories")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "11-budget-bills")

        // Personal scope — the same month filtered to just this member's spending.
        goToTab(app, "Budget")
        if tapAny(app, ["Personal"]) {
            Thread.sleep(forTimeInterval: 3)
            shoot(app, "12-budget-personal")
            tapAny(app, ["Household"], timeout: 3)
            Thread.sleep(forTimeInterval: 2)
        } else {
            print("SHOT_WARN: Personal scope toggle not found")
        }

        // ── Schedule ────────────────────────────────────────────────────────────────
        goToTab(app, "Schedule")
        // Until EventKit access is granted the calendar carries a "Connect Apple Calendar"
        // banner across the top of every shot. Granting it clears the banner; a fresh
        // simulator's system calendar is empty, so nothing foreign appears alongside the
        // household's own events.
        if tapAny(app, ["Connect"], timeout: 4) {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for _ in 0..<10 {
                let grant = springboard.buttons["Allow Full Access"]
                let ok    = springboard.buttons["OK"]
                if grant.exists && grant.isHittable { grant.tap(); break }
                if ok.exists && ok.isHittable { ok.tap(); break }
                Thread.sleep(forTimeInterval: 1)
            }
            Thread.sleep(forTimeInterval: 4)
        }
        shoot(app, "13-schedule-month")
        // The view toggle is an icon-only Button, so it surfaces under its SF Symbol name.
        if tapAny(app, ["rectangle.grid.1x2"]) {
            Thread.sleep(forTimeInterval: 3)
            shoot(app, "14-schedule-week")
        } else {
            print("SHOT_WARN: calendar view toggle not found")
        }

        // ── Fix-It ──────────────────────────────────────────────────────────────────
        goToTab(app, "Fix-It")
        shoot(app, "15-fix-it")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "16-fix-it-scrolled")

        goToTab(app, "Fix-It")
        if tapAny(app, ["History"]) {
            Thread.sleep(forTimeInterval: 3)
            shoot(app, "17-fix-it-history")
            dismissSheet(app, "maintenance history")
        } else {
            print("SHOT_WARN: maintenance History button not found")
        }

        // ── Household roster (last: it lives behind a full-height Settings sheet) ────
        goToTab(app, "Home")
        if openDashboardMenu(app) {
            if tapAny(app, ["Household Members"]) {
                Thread.sleep(forTimeInterval: 4)
                shoot(app, "18-household-members")
            } else {
                print("SHOT_WARN: Household Members row not found")
            }
        } else {
            print("SHOT_WARN: dashboard menu button not found")
        }

        print("FINAL_UI_DUMP >>>\n\(app.debugDescription.prefix(8000))\n<<< END")
    }

    /// The dashboard's menu button is an icon-less three-bar stack, so it carries no
    /// label for XCUITest to match. Fall back to the header's top-right corner.
    private func openDashboardMenu(_ app: XCUIApplication) -> Bool {
        if tapAny(app, ["line.3.horizontal", "Menu", "Settings"], timeout: 3) { return true }
        let corner = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.09))
        corner.tap()
        Thread.sleep(forTimeInterval: 2)
        return app.staticTexts["Household Members"].waitForExistence(timeout: 5)
    }

    /// Shared login used by both capture passes.
    @MainActor
    private func signIn(_ app: XCUIApplication, email: String, password: String) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launch()

        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }

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
                          "Tab bar never appeared after login. UI: \(app.debugDescription.prefix(3000))")
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
