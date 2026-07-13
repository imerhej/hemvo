//  Expense.swift
//  Hemvo

internal import Foundation
internal import SwiftUI
internal import CryptoKit

// MARK: - RecurrenceRule
/// How often a bill repeats. `nil` on an Expense means it does not repeat — a one-time
/// bill that is reminded once and then done, which is how every bill behaved before
/// recurring series existed.
enum RecurrenceRule: String, Codable, CaseIterable, Identifiable {
    case weekly  = "weekly"
    case monthly = "monthly"
    case yearly  = "yearly"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly:  return "Weekly"
        case .monthly: return "Monthly"
        case .yearly:  return "Yearly"
        }
    }

    var cadenceDescription: String {
        switch self {
        case .weekly:  return "every week"
        case .monthly: return "every month"
        case .yearly:  return "every year"
        }
    }

    /// Calendar unit one period is measured in.
    var component: Calendar.Component {
        switch self {
        case .weekly:  return .weekOfYear
        case .monthly: return .month
        case .yearly:  return .year
        }
    }
}

// MARK: - BudgetScope
enum BudgetScope: String, Codable, CaseIterable {
    case household = "household"
    case personal  = "personal"

    var displayName: String {
        switch self {
        case .household: return "Household"
        case .personal:  return "Personal"
        }
    }
}

// MARK: - Expense
struct Expense: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var amount: Double
    var category: ExpenseCategory
    var date: Date
    var isPaid: Bool
    var paidDate: Date?

    /// Whether this is money you still owe: it has a due date and has to be marked paid.
    /// A bill lives in Upcoming Bills until then; an expense (`false`) is money already
    /// spent and goes straight to Recent Expenses.
    ///
    /// Deliberately independent of `recurrence` — "is this a bill" and "does it repeat" are
    /// two different questions, and a one-time bill (`isBill`, no `recurrence`) is a perfectly
    /// ordinary thing that had no way to be expressed while a single flag meant both.
    var isBill: Bool

    var notes: String
    var scope: BudgetScope
    var createdBy: String?    // UUID string of the user who created this expense
    var paidBy: String?       // UUID string of the user who marked this bill as paid

    /// How often this bill repeats. `nil` means it never does — it is due once and then done.
    var recurrence: RecurrenceRule?
    /// Groups every occurrence of the same repeating bill.
    var seriesID: UUID?
    /// The series' original due date. Future occurrences are computed from this rather
    /// than from the previous occurrence — see `nextOccurrenceDate()`.
    var seriesAnchor: Date?

    /// Whether paying this bill mints the next occurrence. Purely a function of `recurrence`:
    /// there is no such thing as a repeating bill with no cadence, so this is derived rather
    /// than stored — a stored copy could drift out of step with the rule, and used to.
    var isRecurring: Bool { recurrence != nil }

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        category: ExpenseCategory = .other,
        date: Date = Date(),
        isPaid: Bool = false,
        paidDate: Date? = nil,
        isBill: Bool = false,
        notes: String = "",
        scope: BudgetScope = .household,
        createdBy: String? = nil,
        paidBy: String? = nil,
        recurrence: RecurrenceRule? = nil,
        seriesID: UUID? = nil,
        seriesAnchor: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.category = category
        self.date = date
        self.isPaid = isPaid
        self.paidDate = paidDate
        self.isBill = isBill
        self.notes = notes
        self.scope = scope
        self.createdBy = createdBy
        self.paidBy = paidBy
        self.recurrence = recurrence
        self.seriesID = seriesID
        self.seriesAnchor = seriesAnchor
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, title, amount, category, date, isPaid, paidDate
        case isBill, notes, scope, createdBy, paidBy
        case recurrence, seriesID, seriesAnchor
    }

    /// Only `isRecurring` ever existed in cached rows, where it meant *both* "is a bill" and
    /// "repeats". Read it as the bill flag — that was always its dominant meaning — and let
    /// `recurrence`, the only field that ever recorded a cadence, decide whether it repeats.
    private enum LegacyCodingKeys: String, CodingKey { case isRecurring }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try  c.decode(UUID.self,   forKey: .id)
        title        = try  c.decode(String.self, forKey: .title)
        amount       = try  c.decode(Double.self, forKey: .amount)
        category     = (try? c.decode(ExpenseCategory.self, forKey: .category)) ?? .other
        date         = try  c.decode(Date.self,   forKey: .date)
        isPaid       = (try? c.decode(Bool.self,   forKey: .isPaid)) ?? false
        paidDate     = try? c.decode(Date.self,   forKey: .paidDate)
        notes        = (try? c.decode(String.self, forKey: .notes)) ?? ""
        scope        = (try? c.decode(BudgetScope.self, forKey: .scope)) ?? .household
        createdBy    = try? c.decode(String.self, forKey: .createdBy)
        paidBy       = try? c.decode(String.self, forKey: .paidBy)
        recurrence   = try? c.decode(RecurrenceRule.self, forKey: .recurrence)
        seriesID     = try? c.decode(UUID.self,   forKey: .seriesID)
        seriesAnchor = try? c.decode(Date.self,   forKey: .seriesAnchor)

        if let stored = try? c.decode(Bool.self, forKey: .isBill) {
            isBill = stored
        } else {
            let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self)
            isBill = (try? legacy?.decode(Bool.self, forKey: .isRecurring)) ?? false
        }
    }

    // MARK: - Recurrence

    /// The next due date strictly after this occurrence's own date.
    ///
    /// Always measured as `anchor + N periods`, never as `self.date + 1 period`. Adding a
    /// month to Jan 31 gives Feb 28, and adding a month to *that* gives Mar 28 — a monthly
    /// bill would silently walk off the 31st and never come back. Counting periods from the
    /// anchor instead puts month N on the 31st whenever the month is long enough.
    func nextOccurrenceDate() -> Date? {
        guard let rule = recurrence else { return nil }
        let cal     = Calendar.current
        let anchor  = seriesAnchor ?? date
        let current = cal.startOfDay(for: date)

        for step in 1...AppConstants.recurrenceMaxLookaheadSteps {
            guard let candidate = cal.date(byAdding: rule.component, value: step, to: anchor)
            else { return nil }
            if cal.startOfDay(for: candidate) > current { return candidate }
        }
        return nil
    }

    /// Occurrence IDs are derived from (series, due date) instead of being random, so two
    /// household members rolling the same series forward at the same moment mint the *same*
    /// row id and the upsert collapses them into one bill rather than creating duplicate rent.
    static func occurrenceID(seriesID: UUID, due: Date) -> UUID {
        let c   = Calendar.current.dateComponents([.year, .month, .day], from: due)
        let key = "\(seriesID.uuidString)|\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"

        // MD5 is used purely as a name-to-UUID derivation (RFC 4122 v3), not for security:
        // it is the one hash that yields exactly the 16 bytes a UUID needs.
        var bytes = Array(Insecure.MD5.hash(data: Data(key.utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x30   // version 3
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant

        return UUID(uuid: (bytes[0],  bytes[1],  bytes[2],  bytes[3],
                           bytes[4],  bytes[5],  bytes[6],  bytes[7],
                           bytes[8],  bytes[9],  bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    var formattedAmount: String {
        String(format: "$%.2f", amount)
    }

    /// Formatted paid date, e.g. "Paid Apr 10"
    var formattedPaidDate: String? {
        guard let d = paidDate else { return nil }
        return "Paid " + d.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - ExpenseCategory
    enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
        case utilities      = "Utilities"
        case groceries      = "Groceries"
        case mortgage       = "Mortgage / Rent"
        case entertainment  = "Entertainment"
        case transportation = "Transportation"
        case healthcare     = "Healthcare"
        case insurance      = "Insurance"
        case dining         = "Dining Out"
        case creditCard     = "Credit Card"
        case other          = "Other"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .utilities:      return "bolt.fill"
            case .groceries:      return "cart.fill"
            case .mortgage:       return "house.fill"
            case .entertainment:  return "tv.fill"
            case .transportation: return "car.fill"
            case .healthcare:     return "cross.case.fill"
            case .insurance:      return "shield.fill"
            case .dining:         return "fork.knife"
            case .creditCard:     return "creditcard.fill"
            case .other:          return "ellipsis.circle.fill"
            }
        }

        var displayColor: Color {
            switch self {
            case .utilities:      return .blue
            case .groceries:      return .green
            case .mortgage:       return .purple
            case .entertainment:  return .orange
            case .transportation: return Color(hex: "#795548") ?? .brown
            case .healthcare:     return .red
            case .insurance:      return .teal
            case .dining:         return Color(hex: "#FF9800") ?? .orange
            case .creditCard:     return Color(hex: "#1A237E") ?? .indigo
            case .other:          return .gray
            }
        }
    }
}

// MARK: - Budget
struct Budget: Codable, Equatable {
    var monthlyIncome: Double
    var categories: [BudgetCategory]

    init(monthlyIncome: Double = 5000, categories: [BudgetCategory] = BudgetCategory.defaults) {
        self.monthlyIncome = monthlyIncome
        self.categories    = categories
    }
}

// MARK: - BudgetCategory
struct BudgetCategory: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var limit: Double
    var spent: Double

    var remaining: Double    { limit - spent }
    var percentUsed: Double  { guard limit > 0 else { return 0 }; return min(spent / limit, 1.0) }
    var isOverBudget: Bool   { spent > limit }

    enum CodingKeys: String, CodingKey { case id, name, limit, spent }

    init(id: UUID = UUID(), name: String, limit: Double, spent: Double = 0) {
        self.id = id; self.name = name; self.limit = limit; self.spent = spent
    }

    // `spent` defaults to 0 so older UserDefaults data that pre-dates this field
    // decodes successfully instead of throwing and wiping the whole saved budget.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decode(UUID.self,   forKey: .id)
        name  = try c.decode(String.self, forKey: .name)
        limit = try c.decode(Double.self, forKey: .limit)
        spent = (try? c.decode(Double.self, forKey: .spent)) ?? 0
    }

    static var defaults: [BudgetCategory] { [] }
}
