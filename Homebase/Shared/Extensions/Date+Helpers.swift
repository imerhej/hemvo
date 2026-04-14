//  Date+Helpers.swift
//  HomeBase
//  Convenience formatting and calendar utilities used across the app.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

extension Date {

    // MARK: - Formatted Strings
    /// "Mon, Mar 15"
    var shortDisplayDate: String {
        formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Monday, March 15, 2026"
    var longDisplayDate: String {
        formatted(date: .complete, time: .omitted)
    }

    /// "March 2026"
    var monthYearDisplay: String {
        formatted(.dateTime.month(.wide).year())
    }

    /// "9:30 AM"
    var timeDisplay: String {
        formatted(.dateTime.hour().minute())
    }

    /// "Mar 15, 9:30 AM"
    var shortDateTimeDisplay: String {
        formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    // MARK: - Calendar Helpers
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(self)
    }

    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    var isPast: Bool { self < Date() }
    var isFuture: Bool { self > Date() }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    func isSameMonth(as other: Date) -> Bool {
        Calendar.current.isDate(self, equalTo: other, toGranularity: .month)
    }

    /// Days between self and another date (can be negative)
    func days(until other: Date) -> Int {
        Calendar.current.dateComponents([.day], from: startOfDay, to: other.startOfDay).day ?? 0
    }

    /// Returns a date N days from now
    static func daysFromNow(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: Date()) ?? Date()
    }

    // MARK: - Relative Label
    var relativeLabel: String {
        if isToday     { return "Today" }
        if isTomorrow  { return "Tomorrow" }
        if isYesterday { return "Yesterday" }
        return shortDisplayDate
    }
}
