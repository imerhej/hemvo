//  NotificationService.swift
//  Hemvo
//
//  Schedules local notifications for:
//    • Bills — day-before + day-of (existing)
//    • Meals — evening reminder for tomorrow's meals (8pm)
//    • Calendar events — day-before at 8pm + day-of at 8am
//    • Maintenance — day-before at 8pm + day-of at 8am
//
//  App badge is intentionally never set (.badge removed from auth options,
//  badge = 0 cleared on every launch).

internal import Foundation
internal import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    // Show banner + play sound even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // ── Identifier prefixes (used to cancel by category) ────────────────────
    private enum Prefix {
        static let billDue      = "hb_bill_due_"
        static let billEarly    = "hb_bill_early_"
        static let mealTomorrow = "hb_meal_tmrw_"
        static let eventDue     = "hb_event_due_"
        static let eventEarly   = "hb_event_early_"
        static let maintDue     = "hb_maint_due_"
        static let maintEarly   = "hb_maint_early_"
        static let trial        = "hb_trial_expiry"
    }

    // MARK: - Permission
    // Note: .badge is intentionally excluded so the app icon never shows a badge number.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - Badge
    /// Call on every app launch and foreground to keep badge count at zero.
    func clearBadge() {
        Task { @MainActor in
            // iOS 16+: set via UNUserNotificationCenter
            if #available(iOS 16.0, *) {
                try? await center.setBadgeCount(0)
            }
        }
        // Belt-and-suspenders: also clear delivered notifications
        center.removeAllDeliveredNotifications()
    }

    // MARK: - ── MEALS ────────────────────────────────────────────────────────

    /// Schedules one notification per weekday that has meals planned,
    /// firing the EVENING BEFORE at 8pm so the user knows what's coming.
    /// Call whenever the meal plan changes.
    func scheduleMealReminders(meals: [Meal]) {
        // Cancel all existing meal notifications first
        center.getPendingNotificationRequests { pending in
            let ids = pending.map { $0.identifier }.filter { $0.hasPrefix(Prefix.mealTomorrow) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)

            // Group meals by weekday
            let grouped = Dictionary(grouping: meals, by: { $0.day })

            for (weekday, dayMeals) in grouped where !dayMeals.isEmpty {
                // Build a natural-language meal summary
                let names = dayMeals
                    .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }
                    .map { $0.name }
                let summary: String
                switch names.count {
                case 1: summary = names[0]
                case 2: summary = "\(names[0]) and \(names[1])"
                default:
                    let all = names.dropLast().joined(separator: ", ")
                    summary = "\(all) and \(names.last!)"
                }

                let content       = UNMutableNotificationContent()
                content.title     = "🍽️ Tomorrow's Meals"
                content.body      = "\(weekday.label): \(summary)"
                content.sound     = .default
                // No badge

                // Fire every week on the DAY BEFORE this weekday at 8pm.
                // Weekday in DateComponents: 1=Sun, 2=Mon… 7=Sat
                // Our Weekday enum: 1=Mon…7=Sun
                // Day-before: subtract 1, wrapping Sunday(7) → Saturday(6)
                let todayWD    = weekday.rawValue == 1 ? 7 : weekday.rawValue - 1
                // Convert our enum value back to Calendar weekday component
                // Our 1=Mon → Calendar 2, Our 7=Sun → Calendar 1
                let calWD = todayWD == 7 ? 1 : todayWD + 1

                var components          = DateComponents()
                components.weekday      = calWD
                components.hour         = 20
                components.minute       = 0

                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "\(Prefix.mealTomorrow)\(weekday.rawValue)",
                    content:    content,
                    trigger:    trigger
                )
                self.center.add(request) { error in
                    if let error { print("NotificationService meals: \(error)") }
                }
            }
        }
    }

    func cancelMealReminders() {
        center.getPendingNotificationRequests { pending in
            let ids = pending.map { $0.identifier }.filter { $0.hasPrefix(Prefix.mealTomorrow) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - ── CALENDAR EVENTS ──────────────────────────────────────────────

    /// Schedules up to two notifications per event:
    ///   • At event time       — "Starting now: <title>"
    ///   • Before event time   — based on alertOption (5 min, 15 min, 30 min, 1 hr, 1 day)
    /// Events with alertOption == "None" are skipped entirely.
    func scheduleEventReminders(for events: [CalendarEvent]) {
        center.getPendingNotificationRequests { pending in
            let ids = pending.map { $0.identifier }
                .filter { $0.hasPrefix(Prefix.eventDue) || $0.hasPrefix(Prefix.eventEarly) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)

            let now = Date()
            let cal = Calendar.current

            for event in events {
                guard event.alertOption != "None", event.date > now else { continue }

                // ── Notification AT event time ───────────────────────────────
                let atContent       = UNMutableNotificationContent()
                atContent.title     = "📅 \(event.title)"
                atContent.body      = event.isAllDay
                    ? "Your all-day event is today."
                    : "Your event is starting now."
                if !event.notes.isEmpty { atContent.subtitle = event.notes }
                atContent.sound     = .default

                var atComponents: DateComponents
                if event.isAllDay {
                    atComponents        = cal.dateComponents([.year, .month, .day], from: event.date)
                    atComponents.hour   = 8
                    atComponents.minute = 0
                } else {
                    atComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: event.date)
                }

                if let atFireDate = cal.date(from: atComponents), atFireDate > now {
                    let trigger = UNCalendarNotificationTrigger(dateMatching: atComponents, repeats: false)
                    let request = UNNotificationRequest(
                        identifier: "\(Prefix.eventDue)\(event.id.uuidString)",
                        content:    atContent,
                        trigger:    trigger
                    )
                    self.center.add(request) { if let e = $0 { print("NotificationService event at-time: \(e)") } }
                }

                // ── Notification BEFORE event time (based on alertOption) ────
                let beforeFireDate: Date?
                let beforeBody: String
                let timeStr = event.date.formatted(.dateTime.hour().minute())

                if event.isAllDay {
                    // For all-day events the only meaningful "before" is 1 day prior at 8pm
                    if event.alertOption == "1 day before",
                       let dayBefore = cal.date(byAdding: .day, value: -1, to: event.date) {
                        var comp        = cal.dateComponents([.year, .month, .day], from: dayBefore)
                        comp.hour       = 20
                        comp.minute     = 0
                        beforeFireDate  = cal.date(from: comp)
                        beforeBody      = "You have an all-day event tomorrow."
                    } else {
                        beforeFireDate = nil
                        beforeBody     = ""
                    }
                } else if let offset = self.alertOffset(for: event.alertOption) {
                    beforeFireDate = event.date.addingTimeInterval(-offset)
                    beforeBody     = "\(event.alertOption) – starts at \(timeStr)."
                } else {
                    beforeFireDate = nil
                    beforeBody     = ""
                }

                if let fireDate = beforeFireDate, fireDate > now {
                    let earlyContent       = UNMutableNotificationContent()
                    earlyContent.title     = "📅 \(event.title)"
                    earlyContent.body      = beforeBody
                    if !event.notes.isEmpty { earlyContent.subtitle = event.notes }
                    earlyContent.sound     = .default

                    let earlyComponents = cal.dateComponents(
                        [.year, .month, .day, .hour, .minute], from: fireDate)
                    let earlyTrigger = UNCalendarNotificationTrigger(
                        dateMatching: earlyComponents, repeats: false)
                    let earlyRequest = UNNotificationRequest(
                        identifier: "\(Prefix.eventEarly)\(event.id.uuidString)",
                        content:    earlyContent,
                        trigger:    earlyTrigger
                    )
                    self.center.add(earlyRequest) { if let e = $0 { print("NotificationService event before: \(e)") } }
                }
            }
        }
    }

    private func alertOffset(for option: String) -> TimeInterval? {
        switch option {
        case "5 minutes before":  return 5  * 60
        case "15 minutes before": return 15 * 60
        case "30 minutes before": return 30 * 60
        case "1 hour before":     return 60 * 60
        case "1 day before":      return 24 * 60 * 60
        default:                  return nil
        }
    }

    func cancelEventReminders(for eventID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            "\(Prefix.eventDue)\(eventID.uuidString)",
            "\(Prefix.eventEarly)\(eventID.uuidString)"
        ])
    }

    // MARK: - ── MAINTENANCE ──────────────────────────────────────────────────

    /// Schedules two notifications per active maintenance task:
    ///   • Day before at 8pm  — "Tomorrow: <task>"
    ///   • Day of at 8am      — "Due Today: <task>"
    func scheduleMaintenanceReminders(for items: [MaintenanceItem]) {
        // Cancel all existing maintenance notifications
        center.getPendingNotificationRequests { pending in
            let ids = pending.map { $0.identifier }
                .filter { $0.hasPrefix(Prefix.maintDue) || $0.hasPrefix(Prefix.maintEarly) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)

            let now = Date()

            for item in items {
                guard item.nextDue > now else { continue }

                // ── Day-before at 8pm ────────────────────────────────────────
                if let dayBefore = Calendar.current.date(
                    byAdding: .day, value: -1, to: item.nextDue),
                   dayBefore > now {
                    let earlyContent       = UNMutableNotificationContent()
                    earlyContent.title     = "🔧 Tomorrow: \(item.title)"
                    earlyContent.body      = "Maintenance task due tomorrow. Est. \(item.estimatedMinutes) min."
                    earlyContent.sound     = .default

                    var earlyComp          = Calendar.current.dateComponents(
                        [.year, .month, .day], from: dayBefore)
                    earlyComp.hour         = 20
                    earlyComp.minute       = 0

                    let earlyTrigger = UNCalendarNotificationTrigger(
                        dateMatching: earlyComp, repeats: false)
                    let earlyRequest = UNNotificationRequest(
                        identifier: "\(Prefix.maintEarly)\(item.id.uuidString)",
                        content:    earlyContent,
                        trigger:    earlyTrigger
                    )
                    self.center.add(earlyRequest) { if let e = $0 { print("NotificationService maint early: \(e)") } }
                }

                // ── Day-of at 8am ────────────────────────────────────────────
                var dueComp       = Calendar.current.dateComponents(
                    [.year, .month, .day], from: item.nextDue)
                dueComp.hour      = 8
                dueComp.minute    = 0

                guard let fireDate = Calendar.current.date(from: dueComp),
                      fireDate > now else { continue }

                let dueContent    = UNMutableNotificationContent()
                dueContent.title  = "🔧 Due Today: \(item.title)"
                dueContent.body   = "Est. time: \(item.estimatedMinutes) min. Tap to open Hemvo."
                dueContent.sound  = .default

                let dueTrigger = UNCalendarNotificationTrigger(
                    dateMatching: dueComp, repeats: false)
                let dueRequest = UNNotificationRequest(
                    identifier: "\(Prefix.maintDue)\(item.id.uuidString)",
                    content:    dueContent,
                    trigger:    dueTrigger
                )
                self.center.add(dueRequest) { if let e = $0 { print("NotificationService maint due: \(e)") } }
            }
        }
    }

    func cancelMaintenanceReminder(for itemID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            "\(Prefix.maintDue)\(itemID.uuidString)",
            "\(Prefix.maintEarly)\(itemID.uuidString)"
        ])
    }

    // MARK: - ── BILLS ────────────────────────────────────────────────────────

    func scheduleBillReminder(for expense: Expense) {
        guard expense.isRecurring, !expense.isPaid, expense.date > Date() else { return }

        // Day-of at 9am
        let onDueContent       = UNMutableNotificationContent()
        onDueContent.title     = "💸 Bill Due Today"
        onDueContent.body      = "\(expense.title) — \(expense.formattedAmount) is due today."
        onDueContent.sound     = .default

        var onDueComp          = Calendar.current.dateComponents(
            [.year, .month, .day], from: expense.date)
        onDueComp.hour         = 9
        onDueComp.minute       = 0

        let onDueTrigger  = UNCalendarNotificationTrigger(dateMatching: onDueComp, repeats: false)
        let onDueRequest  = UNNotificationRequest(
            identifier: "\(Prefix.billDue)\(expense.id.uuidString)",
            content:    onDueContent,
            trigger:    onDueTrigger
        )
        center.add(onDueRequest) { if let e = $0 { print("NotificationService bill due: \(e)") } }

        // Day-before at 9am
        guard let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: expense.date),
              dayBefore > Date() else { return }

        let earlyContent       = UNMutableNotificationContent()
        earlyContent.title     = "⏰ Bill Due Tomorrow"
        earlyContent.body      = "\(expense.title) — \(expense.formattedAmount) is due tomorrow."
        earlyContent.sound     = .default

        var earlyComp          = Calendar.current.dateComponents(
            [.year, .month, .day], from: dayBefore)
        earlyComp.hour         = 9
        earlyComp.minute       = 0

        let earlyTrigger  = UNCalendarNotificationTrigger(dateMatching: earlyComp, repeats: false)
        let earlyRequest  = UNNotificationRequest(
            identifier: "\(Prefix.billEarly)\(expense.id.uuidString)",
            content:    earlyContent,
            trigger:    earlyTrigger
        )
        center.add(earlyRequest) { if let e = $0 { print("NotificationService bill early: \(e)") } }
    }

    func rescheduleAllBills(from expenses: [Expense]) {
        center.getPendingNotificationRequests { pending in
            let ids = pending.map { $0.identifier }
                .filter { $0.hasPrefix(Prefix.billDue) || $0.hasPrefix(Prefix.billEarly) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
            for expense in expenses where expense.isRecurring && !expense.isPaid {
                self.scheduleBillReminder(for: expense)
            }
        }
    }

    func cancelBillReminder(for expenseID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            "\(Prefix.billDue)\(expenseID.uuidString)",
            "\(Prefix.billEarly)\(expenseID.uuidString)"
        ])
    }

    func cancelAllBillReminders() {
        center.getPendingNotificationRequests { pending in
            let ids = pending.map { $0.identifier }
                .filter { $0.hasPrefix(Prefix.billDue) || $0.hasPrefix(Prefix.billEarly) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func cancelAllEventReminders() {
        center.getPendingNotificationRequests { pending in
            let ids = pending.map { $0.identifier }
                .filter { $0.hasPrefix(Prefix.eventDue) || $0.hasPrefix(Prefix.eventEarly) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func cancelAllMaintenanceReminders() {
        center.getPendingNotificationRequests { pending in
            let ids = pending.map { $0.identifier }
                .filter { $0.hasPrefix(Prefix.maintDue) || $0.hasPrefix(Prefix.maintEarly) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - ── SECURITY ─────────────────────────────────────────────────────

    /// Fires an immediate local notification confirming a password change.
    func sendPasswordChangedNotification() {
        let content       = UNMutableNotificationContent()
        content.title     = "Password Changed"
        content.body      = "Your Hemvo password was updated successfully."
        content.sound     = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "hb_password_changed_\(Date().timeIntervalSince1970)",
            content:    content,
            trigger:    trigger
        )
        // @MainActor satisfies UNUserNotificationCenter's main-thread requirement;
        // the separate Task means the caller is never blocked waiting for it.
        Task { @MainActor [self] in
            try? await self.center.add(request)
        }
    }

    // MARK: - ── TRIAL ────────────────────────────────────────────────────────

    func scheduleTrialExpiryReminder(trialEndDate: Date) {
        guard let fireDate = Calendar.current.date(
            byAdding: .day, value: -1, to: trialEndDate) else { return }

        let content       = UNMutableNotificationContent()
        content.title     = "⏰ Trial Ends Tomorrow"
        content.body      = "Subscribe to Hemvo to keep your home running smoothly."
        content.sound     = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: Prefix.trial, content: content, trigger: trigger)
        center.add(request) { if let e = $0 { print("NotificationService trial: \(e)") } }
    }

    // MARK: - ── UTILITIES ────────────────────────────────────────────────────

    // Kept for compatibility with existing call sites
    func scheduleMaintenanceReminder(for item: MaintenanceItem) {
        scheduleMaintenanceReminders(for: [item])
    }

    func scheduleDailyMealReminder(hour: Int = 17) {
        // Replaced by scheduleMealReminders(meals:) — no-op kept for compatibility
    }

    func cancelDailyMealReminder() {
        cancelMealReminders()
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func listPending() {
        center.getPendingNotificationRequests { requests in
            print("NotificationService: \(requests.count) pending")
            requests.forEach { print("  → \($0.identifier)") }
        }
    }
}
