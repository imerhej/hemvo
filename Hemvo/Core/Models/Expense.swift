//  Expense.swift
//  Hemvo

internal import Foundation
internal import SwiftUI

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
    var isRecurring: Bool
    var notes: String
    var scope: BudgetScope
    var createdBy: String?    // UUID string of the user who created this expense
    var paidBy: String?       // UUID string of the user who marked this bill as paid

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        category: ExpenseCategory = .other,
        date: Date = Date(),
        isPaid: Bool = false,
        paidDate: Date? = nil,
        isRecurring: Bool = false,
        notes: String = "",
        scope: BudgetScope = .household,
        createdBy: String? = nil,
        paidBy: String? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.category = category
        self.date = date
        self.isPaid = isPaid
        self.paidDate = paidDate
        self.isRecurring = isRecurring
        self.notes = notes
        self.scope = scope
        self.createdBy = createdBy
        self.paidBy = paidBy
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
