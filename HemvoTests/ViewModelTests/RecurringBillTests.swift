//
//  RecurringBillTests.swift
//  Hemvo
//
//  Covers the two pieces of recurring-bill logic that fail silently rather than loudly:
//  month-end drift in the schedule, and duplicate occurrences across household devices.
//

import Testing
import Foundation
@testable import Hemvo

struct RecurringBillTests {

    private let cal = Calendar.current

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func bill(due: Date,
                      anchor: Date? = nil,
                      rule: RecurrenceRule? = .monthly,
                      seriesID: UUID = UUID()) -> Expense {
        Expense(
            title: "Rent", amount: 1200, category: .mortgage, date: due,
            isRecurring: true, recurrence: rule,
            seriesID: seriesID, seriesAnchor: anchor ?? due
        )
    }

    // MARK: - Schedule

    @Test("Monthly bill advances by one month")
    func monthlyAdvances() {
        let next = bill(due: date(2026, 7, 1)).nextOccurrenceDate()
        #expect(next.map { cal.dateComponents([.year, .month, .day], from: $0) }
                == DateComponents(year: 2026, month: 8, day: 1))
    }

    /// The bug this design exists to prevent: adding one month to Jan 31 gives Feb 28, and
    /// adding a month to *that* gives Mar 28 — rent silently walks off the 31st and never
    /// returns. Counting periods from the anchor instead restores the 31st in March.
    @Test("A month-end bill does not drift off its due day")
    func monthEndDoesNotDrift() {
        let anchor = date(2026, 1, 31)

        // February has no 31st, so the occurrence lands on the 28th…
        let feb = bill(due: anchor, anchor: anchor).nextOccurrenceDate()
        #expect(cal.component(.month, from: feb!) == 2)
        #expect(cal.component(.day,   from: feb!) == 28)

        // …and March must climb back to the 31st, not stay on the 28th.
        let mar = bill(due: feb!, anchor: anchor).nextOccurrenceDate()
        #expect(cal.component(.month, from: mar!) == 3)
        #expect(cal.component(.day,   from: mar!) == 31)
    }

    @Test("Weekly and yearly bills advance by their own unit")
    func weeklyAndYearly() {
        let weekly = bill(due: date(2026, 7, 1), rule: .weekly).nextOccurrenceDate()
        #expect(cal.dateComponents([.year, .month, .day], from: weekly!)
                == DateComponents(year: 2026, month: 7, day: 8))

        let yearly = bill(due: date(2026, 7, 1), rule: .yearly).nextOccurrenceDate()
        #expect(cal.dateComponents([.year, .month, .day], from: yearly!)
                == DateComponents(year: 2027, month: 7, day: 1))
    }

    @Test("A one-time bill has no next occurrence")
    func oneTimeDoesNotRepeat() {
        #expect(bill(due: date(2026, 7, 1), rule: nil).nextOccurrenceDate() == nil)
    }

    /// A series left unpaid for months must still resolve to a *future* date, otherwise the
    /// catch-up sweep can't climb back to the present and the bill stays silent forever.
    @Test("A long-overdue bill still resolves forward, one period at a time")
    func overdueSeriesClimbsForward() {
        let anchor = date(2026, 1, 15)
        var current = bill(due: anchor, anchor: anchor)
        var dates: [Date] = []

        for _ in 0..<5 {
            guard let next = current.nextOccurrenceDate() else { break }
            dates.append(next)
            current = bill(due: next, anchor: anchor)
        }

        #expect(dates.count == 5)
        #expect(cal.dateComponents([.year, .month, .day], from: dates.last!)
                == DateComponents(year: 2026, month: 6, day: 15))
        // Strictly increasing — never returns a date it has already handed out.
        #expect(zip(dates, dates.dropFirst()).allSatisfy { $0 < $1 })
    }

    // MARK: - Occurrence identity

    /// Two members' phones roll the same series forward at the same moment. Random ids would
    /// give the household two rents; deriving the id from (series, due date) makes both
    /// devices mint the identical row so the upsert collapses them into one.
    @Test("The same series and due date always derive the same occurrence id")
    func occurrenceIDIsDeterministic() {
        let series = UUID()
        let due    = date(2026, 8, 1)
        #expect(Expense.occurrenceID(seriesID: series, due: due)
                == Expense.occurrenceID(seriesID: series, due: due))
    }

    @Test("Time of day does not change the occurrence id")
    func occurrenceIDIgnoresTimeOfDay() {
        let series  = UUID()
        let morning = cal.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 9))!
        let evening = cal.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 23))!
        #expect(Expense.occurrenceID(seriesID: series, due: morning)
                == Expense.occurrenceID(seriesID: series, due: evening))
    }

    @Test("Different dates and different series get different occurrence ids")
    func occurrenceIDIsUnique() {
        let series = UUID()
        #expect(Expense.occurrenceID(seriesID: series, due: date(2026, 8, 1))
                != Expense.occurrenceID(seriesID: series, due: date(2026, 9, 1)))
        #expect(Expense.occurrenceID(seriesID: series,  due: date(2026, 8, 1))
                != Expense.occurrenceID(seriesID: UUID(), due: date(2026, 8, 1)))
    }

    @Test("Derived ids are valid RFC 4122 name-based UUIDs")
    func occurrenceIDIsWellFormed() {
        let id = Expense.occurrenceID(seriesID: UUID(), due: date(2026, 8, 1))
        #expect(id.uuidString.count == 36)
        #expect(id != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)))
    }

    // MARK: - Backward compatibility

    /// Every bill that existed before series shipped decodes with recurrence == nil and must
    /// keep its old one-shot behaviour rather than silently starting to repeat.
    @Test("A pre-existing bill decodes as non-repeating")
    func legacyBillDoesNotRepeat() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","title":"Electric","amount":80,"category":"Utilities",
         "date":768000000,"isPaid":false,"isRecurring":true,"notes":"","scope":"household"}
        """
        let decoded = try JSONDecoder().decode(Expense.self, from: Data(legacy.utf8))
        #expect(decoded.isRecurring)
        #expect(decoded.recurrence == nil)
        #expect(decoded.seriesID == nil)
        #expect(decoded.nextOccurrenceDate() == nil)
    }
}
