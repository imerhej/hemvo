//  BudgetViewModel.swift
//  HomeBase
//  Manages household budget, expenses, and bill reminders.

internal import Foundation
internal import Combine

@MainActor
final class BudgetViewModel: ObservableObject {

    @Published var budget: Budget      = Budget()
    @Published var expenses: [Expense] = []
    @Published var selectedMonth: Date = Date()

    // MARK: - Computed — Month Filter
    var monthlyExpenses: [Expense] {
        expenses
            .filter { Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
            .sorted { $0.date > $1.date }
    }

    var totalSpent: Double      { monthlyExpenses.reduce(0) { $0 + $1.amount } }
    var remainingBudget: Double { budget.monthlyIncome - totalSpent }
    var spentPercent: Double    {
        guard budget.monthlyIncome > 0 else { return 0 }
        return min(totalSpent / budget.monthlyIncome, 1.0)
    }

    var recentExpenses: [Expense] { expenses.sorted { $0.date > $1.date } }
    var upcomingBills:  [Expense] { expenses.filter { $0.isRecurring && !$0.isPaid }.sorted { $0.date < $1.date } }
    var budgetCategories: [BudgetCategory] { budget.categories }

    // MARK: - Expense CRUD
    func addExpense(_ expense: Expense) {
        expenses.append(expense)
        autoCreateCategory(for: expense.category)
        updateCategorySpend()
        persist()
        objectWillChange.send()
    }

    func updateExpense(_ expense: Expense) {
        if let idx = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[idx] = expense
            autoCreateCategory(for: expense.category)
            updateCategorySpend()
            persist()
            objectWillChange.send()
        }
    }

    func deleteExpense(_ expense: Expense) {
        expenses.removeAll { $0.id == expense.id }
        // Recalculate spend — but do NOT remove the category.
        // The category row stays visible in the dashboard with spent = 0,
        // so the user can see the budget limit they set is still in effect.
        updateCategorySpend()
        persist()
        objectWillChange.send()
    }

    func markBillPaid(_ expense: Expense) {
        if let idx = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[idx].isPaid   = true
            expenses[idx].paidDate = Date()
            // Recalculate category spend — paid bills are excluded from totals
            updateCategorySpend()
            persist()
            objectWillChange.send()
        }
    }

    func deleteBills(at offsets: IndexSet) {
        let bills = upcomingBills
        offsets.forEach { deleteExpense(bills[$0]) }
    }

    // MARK: - Auto-create Budget Category
    /// Creates a matching BudgetCategory the first time an expense of that type is added.
    /// Categories are NEVER auto-deleted — they persist even when all expenses in that
    /// category are removed, so the dashboard always shows the full spending picture.
    private func autoCreateCategory(for expCategory: Expense.ExpenseCategory) {
        let name = expenseCategoryDisplayName(expCategory)
        let alreadyExists = budget.categories.contains {
            $0.name.lowercased().trimmingCharacters(in: .whitespaces) ==
            name.lowercased().trimmingCharacters(in: .whitespaces)
        }
        guard !alreadyExists else { return }
        budget.categories.append(BudgetCategory(name: name, limit: 500))
    }

    // MARK: - Budget Settings
    func updateMonthlyIncome(_ amount: Double) {
        budget.monthlyIncome = amount
        persist()
    }

    func addCategory(_ category: BudgetCategory) {
        budget.categories.append(category)
        persist()
        objectWillChange.send()
    }

    func deleteCategory(_ category: BudgetCategory) {
        budget.categories.removeAll { $0.id == category.id }
        persist()
        objectWillChange.send()
    }

    func updateCategoryLimit(id: UUID, limit: Double) {
        if let idx = budget.categories.firstIndex(where: { $0.id == id }) {
            budget.categories[idx].limit = limit
            persist()
        }
    }

    // MARK: - Category Spend Calculator
    /// Recalculates `spent` for every existing budget category.
    /// Paid expenses are excluded — marking a bill paid removes its amount
    /// from the category total so the dashboard stays accurate.
    func updateCategorySpend() {
        for i in budget.categories.indices {
            let catName = budget.categories[i].name
                .lowercased()
                .trimmingCharacters(in: .whitespaces)
            budget.categories[i].spent = expenses
                .filter { expense in
                    !expense.isPaid &&           // ← exclude paid bills
                    expenseCategoryDisplayName(expense.category)
                        .lowercased()
                        .trimmingCharacters(in: .whitespaces) == catName
                }
                .reduce(0) { $0 + $1.amount }
        }
        objectWillChange.send()
    }

    // MARK: - Category Name Mapping
    /// Maps every ExpenseCategory case to its BudgetCategory display name.
    /// Must be kept in sync with Expense.ExpenseCategory.allCases.
    private func expenseCategoryDisplayName(_ cat: Expense.ExpenseCategory) -> String {
        switch cat {
        case .groceries:      return "Groceries"
        case .utilities:      return "Utilities"
        case .entertainment:  return "Entertainment"
        case .transportation: return "Transportation"
        case .healthcare:     return "Healthcare"
        case .dining:         return "Dining Out"
        case .mortgage:       return "Mortgage / Rent"
        case .insurance:      return "Insurance"
        case .creditCard:     return "Credit Card"   // ← added
        case .other:          return "Other"
        }
    }

    // MARK: - Month Navigation
    func previousMonth() {
        selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
    }

    func nextMonth() {
        selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
    }

    // MARK: - Persistence
    private let expenseKey = "hb_expenses"
    private let budgetKey  = "hb_budget"

    init() {
        load()
        updateCategorySpend()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NotificationService.shared.rescheduleAllBills(from: self.expenses)
        }
    }

    private func load() {
        if let d = UserDefaults.standard.data(forKey: expenseKey),
           let decoded = try? JSONDecoder().decode([Expense].self, from: d) {
            expenses = decoded
        }
        if let d = UserDefaults.standard.data(forKey: budgetKey),
           let decoded = try? JSONDecoder().decode(Budget.self, from: d) {
            budget = decoded
        }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(expenses) {
            UserDefaults.standard.set(d, forKey: expenseKey)
        }
        if let d = try? JSONEncoder().encode(budget) {
            UserDefaults.standard.set(d, forKey: budgetKey)
        }
    }
}
