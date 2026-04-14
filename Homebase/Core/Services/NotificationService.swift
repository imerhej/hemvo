//  NotificationService.swift
//  HomeBase
//  Schedules and manages local push notifications for bills, maintenance, and meals.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

final class NotificationService {

    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()
    private init() {}

    // MARK: - Permission
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            print("NotificationService: permission granted = \(granted)")
            return granted
        } catch {
            print("NotificationService: permission error — \(error)")
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - Bill Reminders
    func scheduleBillReminder(for expense: Expense) {
        guard expense.isRecurring, !expense.isPaid else { return }

        // Don't schedule for past dates
        guard expense.date > Date() else {
            print("NotificationService: skipping past bill '\(expense.title)'")
            return
        }

        // Notification ON the due date at 9am
        let onDueContent         = UNMutableNotificationContent()
        onDueContent.title       = "💸 Bill Due Today"
        onDueContent.body        = "\(expense.title) — \(expense.formattedAmount) is due today."
        onDueContent.sound       = .default
        onDueContent.badge       = 1

        var onDueComponents      = Calendar.current.dateComponents([.year, .month, .day], from: expense.date)
        onDueComponents.hour     = 9
        onDueComponents.minute   = 0

        let onDueTrigger  = UNCalendarNotificationTrigger(dateMatching: onDueComponents, repeats: false)
        let onDueRequest  = UNNotificationRequest(
            identifier: "bill_due_\(expense.id.uuidString)",
            content:    onDueContent,
            trigger:    onDueTrigger
        )
        center.add(onDueRequest) { error in
            if let error { print("NotificationService: bill due error — \(error)") }
            else { print("NotificationService: scheduled 'due today' for '\(expense.title)' on \(expense.date)") }
        }

        // Notification 1 day BEFORE at 9am
        guard let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: expense.date),
              dayBefore > Date() else { return }

        let earlyContent         = UNMutableNotificationContent()
        earlyContent.title       = "⏰ Bill Due Tomorrow"
        earlyContent.body        = "\(expense.title) — \(expense.formattedAmount) is due tomorrow."
        earlyContent.sound       = .default

        var earlyComponents      = Calendar.current.dateComponents([.year, .month, .day], from: dayBefore)
        earlyComponents.hour     = 9
        earlyComponents.minute   = 0

        let earlyTrigger  = UNCalendarNotificationTrigger(dateMatching: earlyComponents, repeats: false)
        let earlyRequest  = UNNotificationRequest(
            identifier: "bill_early_\(expense.id.uuidString)",
            content:    earlyContent,
            trigger:    earlyTrigger
        )
        center.add(earlyRequest) { error in
            if let error { print("NotificationService: bill early error — \(error)") }
            else { print("NotificationService: scheduled 'due tomorrow' for '\(expense.title)'") }
        }
    }

    // MARK: - Reschedule ALL existing bills (call on app launch)
    func rescheduleAllBills(from expenses: [Expense]) {
        // Cancel all existing bill notifications first
        center.getPendingNotificationRequests { pending in
            let billIDs = pending
                .map { $0.identifier }
                .filter { $0.hasPrefix("bill_") }
            self.center.removePendingNotificationRequests(withIdentifiers: billIDs)

            // Re-schedule all unpaid future bills
            for expense in expenses where expense.isRecurring && !expense.isPaid {
                self.scheduleBillReminder(for: expense)
            }
            print("NotificationService: rescheduled \(expenses.filter { $0.isRecurring && !$0.isPaid }.count) bills")
        }
    }

    func cancelBillReminder(for expenseID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            "bill_due_\(expenseID.uuidString)",
            "bill_early_\(expenseID.uuidString)"
        ])
    }

    // MARK: - Maintenance Reminders
    func scheduleMaintenanceReminder(for item: MaintenanceItem) {
        let content         = UNMutableNotificationContent()
        content.title       = "🔧 Maintenance Due"
        content.body        = "\(item.title) is due today. Est. time: \(item.estimatedMinutes) min."
        content.sound       = .default

        var components = Calendar.current.dateComponents(
            [.year, .month, .day], from: item.nextDue
        )
        components.hour   = 8
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "maint_\(item.id.uuidString)",
            content:    content,
            trigger:    trigger
        )
        center.add(request) { error in
            if let error { print("NotificationService: maintenance error — \(error)") }
        }
    }

    func cancelMaintenanceReminder(for itemID: UUID) {
        center.removePendingNotificationRequests(
            withIdentifiers: ["maint_\(itemID.uuidString)"]
        )
    }

    // MARK: - Meal Plan Reminder (daily at 5pm)
    func scheduleDailyMealReminder(hour: Int = 17) {
        let content       = UNMutableNotificationContent()
        content.title     = "🍽️ Dinner Tonight"
        content.body      = "Check tonight's meal plan in HomeBase."
        content.sound     = .default

        var components    = DateComponents()
        components.hour   = hour
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: "hb_dailyMealReminder",
            content:    content,
            trigger:    trigger
        )
        center.add(request) { error in
            if let error { print("NotificationService: meal reminder error — \(error)") }
        }
    }

    func cancelDailyMealReminder() {
        center.removePendingNotificationRequests(withIdentifiers: ["hb_dailyMealReminder"])
    }

    // MARK: - Trial Expiry Reminder
    func scheduleTrialExpiryReminder(trialEndDate: Date) {
        guard let fireDate = Calendar.current.date(
            byAdding: .day, value: -1, to: trialEndDate
        ) else { return }

        let content       = UNMutableNotificationContent()
        content.title     = "⏰ Trial Ends Tomorrow"
        content.body      = "Subscribe to HomeBase to keep your home running smoothly."
        content.sound     = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "hb_trialExpiry",
            content:    content,
            trigger:    trigger
        )
        center.add(request) { error in
            if let error { print("NotificationService: trial expiry error — \(error)") }
        }
    }

    // MARK: - Cancel All
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: - Debug: list all pending
    func listPending() {
        center.getPendingNotificationRequests { requests in
            print("NotificationService: \(requests.count) pending notifications")
            requests.forEach { print("  → \($0.identifier) trigger: \($0.trigger ?? "none" as AnyObject)") }
        }
    }
}
