//  NotificationService.swift
//  Homvi
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

final class NotificationService {

    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()
    private init() {}

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

    /// Schedules two notifications per event:
    ///   • Day before at 8pm  — "Tomorrow: <title>"
    ///   • Day of at 8am      — "Today: <title>"
    func scheduleEventReminders(for events: [CalendarEvent]) {
        // Cancel all existing event notifications
        center.getPendingNotificationRequests { pending in
            let ids = pending.map { $0.identifier }
                .filter { $0.hasPrefix(Prefix.eventDue) || $0.hasPrefix(Prefix.eventEarly) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)

            let now      = Date()

            for event in events {
                // Only schedule future events
                guard event.date > now else { continue }

                let timeStr = event.isAllDay
                    ? "All day"
                    : event.date.formatted(.dateTime.hour().minute())

                // ── Day-before notification (8pm the evening before) ─────────
                guard let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: event.date),
                      dayBefore > now else {
                    // Event is tomorrow or sooner — skip the "day before" and
                    // only schedule the "day of" if it's still in the future
                    self.scheduleEventDayOf(event: event, timeStr: timeStr)
                    continue
                }

                let earlyContent       = UNMutableNotificationContent()
                earlyContent.title     = "📅 Tomorrow: \(event.title)"
                earlyContent.body      = event.isAllDay
                    ? "You have an all-day event tomorrow."
                    : "Starts at \(timeStr) tomorrow."
                if !event.notes.isEmpty { earlyContent.subtitle = event.notes }
                earlyContent.sound     = .default

                var earlyComponents    = Calendar.current.dateComponents(
                    [.year, .month, .day], from: dayBefore)
                earlyComponents.hour   = 20
                earlyComponents.minute = 0

                let earlyTrigger = UNCalendarNotificationTrigger(
                    dateMatching: earlyComponents, repeats: false)
                let earlyRequest = UNNotificationRequest(
                    identifier: "\(Prefix.eventEarly)\(event.id.uuidString)",
                    content:    earlyContent,
                    trigger:    earlyTrigger
                )
                self.center.add(earlyRequest) { if let e = $0 { print("NotificationService event early: \(e)") } }

                // ── Day-of notification (8am) ────────────────────────────────
                self.scheduleEventDayOf(event: event, timeStr: timeStr)
            }
        }
    }

    private func scheduleEventDayOf(event: CalendarEvent, timeStr: String) {
        let now = Date()

        let dayOfContent       = UNMutableNotificationContent()
        dayOfContent.title     = "📅 Today: \(event.title)"
        dayOfContent.body      = event.isAllDay
            ? "You have an all-day event today."
            : "Starts at \(timeStr) today."
        if !event.notes.isEmpty { dayOfContent.subtitle = event.notes }
        dayOfContent.sound     = .default

        var dayOfComponents    = Calendar.current.dateComponents(
            [.year, .month, .day], from: event.date)

        if event.isAllDay {
            // Fire at 8am for all-day events
            dayOfComponents.hour   = 8
            dayOfComponents.minute = 0
        } else {
            // Fire at event start time (or 8am if event is earlier)
            let eventHour = Calendar.current.component(.hour, from: event.date)
            dayOfComponents.hour   = max(eventHour, 8)
            dayOfComponents.minute = Calendar.current.component(.minute, from: event.date)
        }

        // Only schedule if the fire time is in the future
        guard let fireDate = Calendar.current.date(from: dayOfComponents),
              fireDate > now else { return }

        let dayOfTrigger = UNCalendarNotificationTrigger(
            dateMatching: dayOfComponents, repeats: false)
        let dayOfRequest = UNNotificationRequest(
            identifier: "\(Prefix.eventDue)\(event.id.uuidString)",
            content:    dayOfContent,
            trigger:    dayOfTrigger
        )
        center.add(dayOfRequest) { if let e = $0 { print("NotificationService event day-of: \(e)") } }
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
                dueContent.body   = "Est. time: \(item.estimatedMinutes) min. Tap to open Homvi."
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

    // MARK: - ── TRIAL ────────────────────────────────────────────────────────

    func scheduleTrialExpiryReminder(trialEndDate: Date) {
        guard let fireDate = Calendar.current.date(
            byAdding: .day, value: -1, to: trialEndDate) else { return }

        let content       = UNMutableNotificationContent()
        content.title     = "⏰ Trial Ends Tomorrow"
        content.body      = "Subscribe to Homvi to keep your home running smoothly."
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
