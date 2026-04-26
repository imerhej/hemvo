//  BudgetViewModel.swift
//  Homvi
//  Manages household budget, expenses, and bill reminders.
//  Supabase `expenses` table schema:
//    id, household_id, title, amount, category, is_bill,
//    is_recurring, due_date, paid_date, notes, created_by, created_at

internal import Foundation
internal import Combine
internal import Supabase

@MainActor
final class BudgetViewModel: ObservableObject {

    @Published var budget: Budget      = Budget()
    @Published var expenses: [Expense] = []
    @Published var selectedMonth: Date = Date()

    // Cached IDs resolved once during loadFromSupabase so every CRUD call is free.
    private var cachedUserID:      UUID?
    private var cachedHouseholdID: UUID?

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

    var recentExpenses: [Expense] { expenses.filter { !$0.isRecurring || $0.isPaid }.sorted { $0.date > $1.date } }
    var upcomingBills:  [Expense] {
        expenses
            .filter {
                $0.isRecurring && !$0.isPaid &&
                Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
            }
            .sorted { $0.date < $1.date }
    }
    var budgetCategories: [BudgetCategory] { budget.categories }

    // MARK: - Expense CRUD
    func addExpense(_ expense: Expense) {
        expenses.append(expense)
        autoCreateCategory(for: expense.category)
        updateCategorySpend()
        persist()
        if expense.isRecurring && !expense.isPaid &&
           UserDefaults.standard.bool(forKey: "notif_bills") {
            NotificationService.shared.scheduleBillReminder(for: expense)
        }
        objectWillChange.send()
        Task { await supabaseUpsert(expense) }
    }

    func updateExpense(_ expense: Expense) {
        if let idx = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[idx] = expense
            autoCreateCategory(for: expense.category)
            updateCategorySpend()
            persist()
            NotificationService.shared.cancelBillReminder(for: expense.id)
            if expense.isRecurring && !expense.isPaid &&
               UserDefaults.standard.bool(forKey: "notif_bills") {
                NotificationService.shared.scheduleBillReminder(for: expense)
            }
            objectWillChange.send()
            Task { await supabaseUpsert(expense) }
        }
    }

    func deleteExpense(_ expense: Expense) {
        expenses.removeAll { $0.id == expense.id }
        updateCategorySpend()
        persist()
        NotificationService.shared.cancelBillReminder(for: expense.id)
        objectWillChange.send()
        Task { await supabaseDelete(id: expense.id) }
    }

    func markBillPaid(_ expense: Expense) {
        if let idx = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[idx].isPaid   = true
            expenses[idx].paidDate = Date()
            updateCategorySpend()
            persist()
            NotificationService.shared.cancelBillReminder(for: expense.id)
            objectWillChange.send()
            Task { await supabaseUpsert(expenses[idx]) }
        }
    }

    func deleteBills(at offsets: IndexSet) {
        let bills = upcomingBills
        offsets.forEach { deleteExpense(bills[$0]) }
    }

    // MARK: - Auto-create Budget Category
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
    func updateCategorySpend() {
        let cal = Calendar.current
        for i in budget.categories.indices {
            let catName = budget.categories[i].name
                .lowercased()
                .trimmingCharacters(in: .whitespaces)
            budget.categories[i].spent = expenses
                .filter { expense in
                    cal.isDate(expense.date, equalTo: selectedMonth, toGranularity: .month) &&
                    expenseCategoryDisplayName(expense.category)
                        .lowercased()
                        .trimmingCharacters(in: .whitespaces) == catName
                }
                .reduce(0) { $0 + $1.amount }
        }
        objectWillChange.send()
    }

    // MARK: - Category Name Mapping
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
        case .creditCard:     return "Credit Card"
        case .other:          return "Other"
        }
    }

    // MARK: - Month Navigation
    func previousMonth() {
        selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        updateCategorySpend()
    }

    func nextMonth() {
        selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
        updateCategorySpend()
    }

    // MARK: - Persistence (UserDefaults cache)
    private let expenseKey = "hb_expenses"
    private let budgetKey  = "hb_budget"

    init() {
        load()
        updateCategorySpend()
        Task { await loadFromSupabase() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if UserDefaults.standard.bool(forKey: "notif_bills") {
                NotificationService.shared.rescheduleAllBills(from: self.expenses)
            }
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

    // MARK: - Supabase Sync

    /// Fetches all expenses for the current user's household from Supabase,
    /// caches the user/household IDs for subsequent writes, and updates local state.
    func loadFromSupabase() async {
        guard let uid = await AuthService.shared.currentUserID() else { return }
        cachedUserID = uid

        // Resolve household UUID from the Supabase profile (not the local string ID).
        if let profile = try? await AuthService.shared.loadProfile() {
            cachedHouseholdID = profile.householdId
        }

        do {
            var query = supabase
                .from("expenses")
                .select()

            if let hid = cachedHouseholdID {
                query = query.eq("household_id", value: hid.uuidString)
            } else {
                query = query.eq("created_by", value: uid.uuidString)
            }

            let rows: [SupabaseExpenseRow] = try await query.execute().value
            expenses = rows.map { $0.toExpense() }
            updateCategorySpend()
            persist()
        } catch {
            print("[Supabase] fetch expenses error: \(error)")
        }
    }

    private func supabaseUpsert(_ expense: Expense) async {
        // Resolve IDs on first call if loadFromSupabase hasn't run yet.
        if cachedUserID == nil {
            cachedUserID = await AuthService.shared.currentUserID()
        }
        if cachedHouseholdID == nil, let profile = try? await AuthService.shared.loadProfile() {
            cachedHouseholdID = profile.householdId
        }
        guard let uid = cachedUserID else { return }

        let row = SupabaseExpenseRow(from: expense, userId: uid, householdId: cachedHouseholdID)
        do {
            try await supabase
                .from("expenses")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            print("[Supabase] upsert expense error: \(error)")
        }
    }

    private func supabaseDelete(id: UUID) async {
        do {
            try await supabase
                .from("expenses")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            print("[Supabase] delete expense error: \(error)")
        }
    }
}

// MARK: - Supabase row mapping
/// Column names match the `expenses` table in Supabase exactly.
private struct SupabaseExpenseRow: Codable {
    let id:          UUID
    let householdId: UUID?
    var title:       String
    var amount:      Double
    var category:    String?
    var isBill:      Bool
    var isRecurring: Bool
    var dueDate:     Date?
    var paidDate:    Date?
    var notes:       String
    let createdBy:   UUID

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case title
        case amount
        case category
        case isBill      = "is_bill"
        case isRecurring = "is_recurring"
        case dueDate     = "due_date"
        case paidDate    = "paid_date"
        case notes
        case createdBy   = "created_by"
    }

    init(from expense: Expense, userId: UUID, householdId: UUID?) {
        id             = expense.id
        createdBy      = userId
        self.householdId = householdId
        title          = expense.title
        amount         = expense.amount
        category       = expense.category.rawValue
        isBill         = expense.isRecurring
        isRecurring    = expense.isRecurring
        dueDate        = expense.date
        paidDate       = expense.paidDate
        notes          = expense.notes
    }

    func toExpense() -> Expense {
        Expense(
            id:          id,
            title:       title,
            amount:      amount,
            category:    category.flatMap(Expense.ExpenseCategory.init(rawValue:)) ?? .other,
            date:        dueDate ?? Date(),
            isPaid:      paidDate != nil,
            paidDate:    paidDate,
            isRecurring: isRecurring || isBill,
            notes:       notes
        )
    }
}
