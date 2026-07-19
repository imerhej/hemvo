//  BudgetViewModel.swift
//  Hemvo
//  Manages household budget, expenses, and bill reminders.
//  Supabase `expenses` table schema:
//    id, household_id, title, amount, category, is_bill,
//    is_recurring, due_date, paid_date, notes, created_by, created_at

internal import Foundation
internal import OSLog
internal import Combine
internal import Supabase
internal import UIKit

@MainActor
final class BudgetViewModel: ObservableObject {

    @Published var budget: Budget        = Budget()
    @Published var expenses: [Expense]  = []
    @Published var selectedMonth: Date  = Date()
    @Published var selectedScope: BudgetScope = .household

    // Cached IDs resolved once during loadFromSupabase so every CRUD call is free.
    private var cachedUserID:       UUID?
    private var cachedHouseholdID:  UUID?

    private var deletedExpenseIDs:  Set<UUID> = []
    private var deletedCategoryIDs: Set<UUID> = []

    // Real-time sync — expenses
    private var cancellables:       Set<AnyCancellable> = []
    private var realtimeTask:       Task<Void, Never>?
    private var realtimeDebounce:   Task<Void, Never>?
    private var realtimeChannel:    RealtimeChannelV2?

    // Real-time sync — budget
    private var budgetRealtimeTask:    Task<Void, Never>?
    private var budgetRealtimeChannel: RealtimeChannelV2?

    // MARK: - Role-based write access
    private var hasWriteAccess: Bool {
        guard let uid = cachedUserID else { return false }
        if let role = HouseholdService.shared.household?.members.first(where: { $0.id == uid.uuidString })?.role {
            return role.canWrite
        }
        return true // solo user (no household) — full control
    }

    // MARK: - Ownership checks
    func canDelete(_ expense: Expense) -> Bool {
        hasWriteAccess
    }

    /// Only Owner/Adult can move an expense between household and personal scope.
    func canChangeScope(_ expense: Expense) -> Bool {
        hasWriteAccess
    }

    // MARK: - Computed — Month + Scope Filter
    var monthlyExpenses: [Expense] {
        expenses
            .filter {
                $0.scope == selectedScope &&
                Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
            }
            .sorted { $0.date > $1.date }
    }

    /// Every expense counts the moment it's created — including unpaid bills, which
    /// count toward the month of their due date. Month scoping (not paid status) is
    /// what keeps each month's numbers separate.
    var totalSpent: Double { monthlyExpenses.reduce(0) { $0 + $1.amount } }
    var remainingBudget: Double { budget.monthlyIncome - totalSpent }
    var spentPercent: Double    {
        guard budget.monthlyIncome > 0 else { return 0 }
        return min(totalSpent / budget.monthlyIncome, 1.0)
    }

    /// Money already spent: everything that isn't a bill, plus bills that have been paid.
    /// Keyed on `isBill`, not `isRecurring` — a one-time bill you still owe is not an expense.
    var recentExpenses: [Expense] { expenses.filter { !$0.isBill || $0.isPaid }.sorted { $0.date > $1.date } }
    var upcomingBills:  [Expense] {
        expenses
            .filter {
                $0.scope == selectedScope &&
                $0.isBill && !$0.isPaid &&
                Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
            }
            .sorted { $0.date < $1.date }
    }
    /// Unpaid bills across both scopes for the current user — used by the Dashboard summary tile.
    /// Personal bills from other household members are already excluded by the fetch query + RLS.
    var allUpcomingBills: [Expense] {
        expenses
            .filter {
                $0.isBill && !$0.isPaid &&
                ($0.scope == .household || $0.createdBy == cachedUserID?.uuidString) &&
                Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
            }
            .sorted { $0.date < $1.date }
    }
    var budgetCategories: [BudgetCategory] { budget.categories }

    /// Categories relevant to the selected month: ones with spending dated in that
    /// month, plus fresh categories no expense uses yet. Categories used only in
    /// other months keep their limits but stay out of view, so every month starts
    /// with a clean slate without having to delete historical payments.
    var monthCategories: [BudgetCategory] {
        budget.categories.filter { $0.spent > 0 || !isCategoryInUse($0) }
    }

    func setScope(_ scope: BudgetScope) {
        selectedScope = scope
        updateCategorySpend()
    }

    // MARK: - Expense CRUD
    func addExpense(_ expense: Expense) {
        var stamped = expense
        if stamped.createdBy == nil { stamped.createdBy = cachedUserID?.uuidString }
        if stamped.isPaid {
            if stamped.paidDate == nil { stamped.paidDate = Date() }
            if stamped.paidBy   == nil { stamped.paidBy   = cachedUserID?.uuidString }
        }
        // Only a bill can repeat, and a repeating bill is the first occurrence of its own
        // series: its due date anchors the schedule every later occurrence is computed from.
        if !stamped.isBill { stamped.recurrence = nil }
        if stamped.recurrence != nil {
            if stamped.seriesID     == nil { stamped.seriesID     = stamped.id }
            if stamped.seriesAnchor == nil { stamped.seriesAnchor = stamped.date }
        }
        expenses.append(stamped)
        if stamped.scope == .household { autoCreateCategory(for: stamped.category) }
        updateCategorySpend()
        persist()
        if stamped.isBill && !stamped.isPaid &&
           UserPreferences.shared.notifBills {
            NotificationService.shared.scheduleBillReminder(for: stamped)
        }
        objectWillChange.send()
        Task { await supabaseUpsert(stamped) }
        if stamped.scope == .household {
            Task {
                let creator = HouseholdService.shared.displayName(forUserID: cachedUserID)
                let label = stamped.isBill ? "💸 \(creator) added a bill" : "💰 \(creator) added an expense"
                await PushNotificationService.shared.notifyHouseholdFiltered(
                    permission: \.receiveExpenseAlerts,
                    title: label,
                    body: "\(stamped.title) · \(stamped.formattedAmount)"
                )
            }
        }
    }

    func updateExpense(_ expense: Expense) {
        var stamped  = expense
        let previous = expenses.first(where: { $0.id == stamped.id })

        if stamped.isPaid {
            if stamped.paidDate == nil { stamped.paidDate = Date() }
            if stamped.paidBy   == nil { stamped.paidBy   = cachedUserID?.uuidString }
        } else {
            // Explicitly clear paid metadata so Supabase stores NULL for paid_date.
            // toExpense() derives isPaid from paidDate != nil, so leaving a stale
            // paidDate would make the row appear paid to every other member on next fetch.
            stamped.paidDate = nil
            stamped.paidBy   = nil
        }

        if !stamped.isBill { stamped.recurrence = nil }
        if stamped.recurrence != nil {
            if stamped.seriesID == nil { stamped.seriesID = stamped.id }
            // Moving a repeating bill's due date re-anchors the schedule: drag rent from the
            // 1st to the 5th and every occurrence from here on should land on the 5th.
            if stamped.seriesAnchor == nil || previous?.date != stamped.date {
                stamped.seriesAnchor = stamped.date
            }
        }

        if let idx = expenses.firstIndex(where: { $0.id == stamped.id }) {
            expenses[idx] = stamped
            // Switching recurrence off has to end the series for every member, not just on
            // this device — otherwise another member's catch-up sweep keeps minting bills.
            if previous?.recurrence != nil, stamped.recurrence == nil {
                stopSeries(stamped)
            }
            if stamped.scope == .household { autoCreateCategory(for: stamped.category) }
            updateCategorySpend()
            persist()
            NotificationService.shared.cancelBillReminder(for: stamped.id)
            if stamped.isBill && !stamped.isPaid &&
               UserPreferences.shared.notifBills {
                NotificationService.shared.scheduleBillReminder(for: stamped)
            }
            objectWillChange.send()
            Task { await supabaseUpdateExpense(stamped) }
        }
    }

    func deleteExpense(_ expense: Expense) {
        guard canDelete(expense) else { return }

        // Deleting the newest occurrence of a series ends the series. Without this the
        // catch-up sweep would see the now-newest occurrence sitting in the past and mint
        // the deleted bill straight back. Deleting an *older* occurrence only removes that
        // row — the schedule keeps running, which is what you want when tidying history.
        if expense.recurrence != nil, isNewestOccurrence(expense) {
            stopSeries(expense)
        }

        deletedExpenseIDs.insert(expense.id)
        persistDeletedIDs()
        expenses.removeAll { $0.id == expense.id }
        updateCategorySpend()

        // If the deleted expense was a household expense, check whether its
        // auto-created category is now empty and remove it too.
        if expense.scope == .household {
            let categoryName = expenseCategoryDisplayName(expense.category)
                .lowercased().trimmingCharacters(in: .whitespaces)
            let stillUsed = expenses.contains {
                $0.scope == .household &&
                expenseCategoryDisplayName($0.category)
                    .lowercased().trimmingCharacters(in: .whitespaces) == categoryName
            }
            if !stillUsed, let cat = budget.categories.first(where: {
                $0.name.lowercased().trimmingCharacters(in: .whitespaces) == categoryName
            }) {
                removeCategory(cat)
            }
        }

        persist()
        NotificationService.shared.cancelBillReminder(for: expense.id)
        objectWillChange.send()
        Task { await supabaseDelete(id: expense.id) }
    }

    func markBillPaid(_ expense: Expense) {
        if let idx = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[idx].isPaid   = true
            expenses[idx].paidDate = Date()
            expenses[idx].paidBy   = cachedUserID?.uuidString
            let paid = expenses[idx]
            updateCategorySpend()
            persist()
            NotificationService.shared.cancelBillReminder(for: expense.id)
            objectWillChange.send()
            Task { await supabaseMarkPaid(paid) }
            // Paying the newest bill in a series is what rolls it forward: the next
            // occurrence appears immediately, already carrying its own reminders.
            rollSeriesForward(from: paid)
        }
    }

    func deleteBills(at offsets: IndexSet) {
        let bills = upcomingBills
        offsets.forEach { deleteExpense(bills[$0]) }
    }

    // MARK: - Recurring Bill Series

    /// True when no later occurrence of the same series exists. Rolling forward and ending a
    /// series are both only ever driven by the newest occurrence, so paying (or deleting) a
    /// back-dated bill can't mint an occurrence that already exists further ahead.
    private func isNewestOccurrence(_ bill: Expense) -> Bool {
        guard let sid = bill.seriesID else { return true }
        return !expenses.contains { $0.seriesID == sid && $0.date > bill.date }
    }

    /// Whether deleting this bill also ends its repeating schedule — true only for the newest
    /// occurrence. Lets the delete confirmation say which of the two is about to happen
    /// instead of guessing.
    func deletingEndsSeries(_ expense: Expense) -> Bool {
        expense.recurrence != nil && isNewestOccurrence(expense)
    }

    /// Creates the occurrence that follows `bill`, if `bill` is the newest one in its series.
    @discardableResult
    private func rollSeriesForward(from bill: Expense) -> Expense? {
        guard bill.recurrence != nil, hasWriteAccess, isNewestOccurrence(bill),
              let due = bill.nextOccurrenceDate()
        else { return nil }
        return materializeOccurrence(of: bill, on: due)
    }

    /// Clones `bill` onto a later due date, unpaid. Returns nil when that occurrence already
    /// exists locally or was deleted — both make this a no-op, which is what lets the catch-up
    /// sweep run on every fetch and on every member's device without ever duplicating a bill.
    @discardableResult
    private func materializeOccurrence(of bill: Expense, on due: Date) -> Expense? {
        let seriesID = bill.seriesID ?? bill.id
        let id       = Expense.occurrenceID(seriesID: seriesID, due: due)

        guard !deletedExpenseIDs.contains(id),
              !expenses.contains(where: { $0.id == id })
        else { return nil }

        let next = Expense(
            id:          id,
            title:       bill.title,
            amount:      bill.amount,
            category:    bill.category,
            date:        due,
            isPaid:      false,
            paidDate:    nil,
            isBill:      true,
            notes:       bill.notes,
            scope:       bill.scope,
            // The member whose device mints the row has to own it: the INSERT policy on
            // `expenses` checks created_by = auth.uid(), so carrying the original creator
            // over would make the insert fail for every other member in the household.
            createdBy:    cachedUserID?.uuidString ?? bill.createdBy,
            paidBy:       nil,
            recurrence:   bill.recurrence,
            seriesID:     seriesID,
            seriesAnchor: bill.seriesAnchor ?? bill.date
        )

        expenses.append(next)
        persist()
        if UserPreferences.shared.notifBills {
            NotificationService.shared.scheduleBillReminder(for: next)
        }
        objectWillChange.send()
        Task { await supabaseUpsert(next) }
        return next
    }

    /// Mints any occurrences a series has missed, so that every live series always has one
    /// occurrence due today or later.
    ///
    /// Rolling forward on payment alone isn't enough: a bill that goes *unpaid* would never
    /// advance, and never notifying you about the bill you forgot is the whole failure this
    /// feature exists to fix. Runs after every fetch. Idempotent — occurrence ids are derived
    /// from (series, due date), so re-running it, or running it on three phones at once,
    /// converges on the same rows.
    private func catchUpRecurringSeries() {
        guard hasWriteAccess else { return }
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())

        let series = Dictionary(
            grouping: expenses.filter { $0.recurrence != nil && $0.seriesID != nil },
            by: { $0.seriesID! }
        )

        for (_, occurrences) in series {
            guard var newest = occurrences.max(by: { $0.date < $1.date }) else { continue }
            var minted = 0
            while cal.startOfDay(for: newest.date) < today, minted < AppConstants.recurrenceMaxCatchUp {
                guard let due  = newest.nextOccurrenceDate(),
                      let next = materializeOccurrence(of: newest, on: due)
                else { break }
                newest  = next
                minted += 1
            }
        }
    }

    /// Ends a series by clearing `recurrence` on every remaining occurrence, locally and in
    /// Supabase, so no member's catch-up sweep rolls it forward again.
    private func stopSeries(_ bill: Expense) {
        guard let sid = bill.seriesID else { return }
        for i in expenses.indices where expenses[i].seriesID == sid {
            expenses[i].recurrence = nil
        }
        Task { await supabaseStopSeries(seriesID: sid) }
    }

    // MARK: - Auto-create Budget Category
    private func autoCreateCategory(for expCategory: Expense.ExpenseCategory) {
        let name = expenseCategoryDisplayName(expCategory)
        let alreadyExists = budget.categories.contains {
            $0.name.lowercased().trimmingCharacters(in: .whitespaces) ==
            name.lowercased().trimmingCharacters(in: .whitespaces)
        }
        guard !alreadyExists else { return }
        let newCat = BudgetCategory(name: name, limit: 500)
        budget.categories.append(newCat)
        Task { await supabaseUpsertCategory(newCat) }
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
        Task { await supabaseUpsertCategory(category) }
    }

    /// True while any household expense (any month, paid or not) still maps to this
    /// category. Deleting a category in use is pointless — autoCreateCategory would
    /// recreate it from those expenses on the next sync.
    func isCategoryInUse(_ category: BudgetCategory) -> Bool {
        let name = category.name.lowercased().trimmingCharacters(in: .whitespaces)
        return expenses.contains {
            $0.scope == .household &&
            expenseCategoryDisplayName($0.category)
                .lowercased().trimmingCharacters(in: .whitespaces) == name
        }
    }

    func deleteCategory(_ category: BudgetCategory) {
        guard !isCategoryInUse(category) else { return }
        removeCategory(category)
        objectWillChange.send()
    }

    /// Tombstones the ID before removing so a loadBudgetFromSupabase() fetch that
    /// races the async remote delete can't resurrect the category.
    private func removeCategory(_ category: BudgetCategory) {
        deletedCategoryIDs.insert(category.id)
        persistDeletedCategoryIDs()
        budget.categories.removeAll { $0.id == category.id }
        persist()
        Task { await supabaseDeleteCategory(id: category.id) }
    }

    func updateCategoryLimit(id: UUID, limit: Double) {
        if let idx = budget.categories.firstIndex(where: { $0.id == id }) {
            budget.categories[idx].limit = limit
            persist()
            Task { await supabaseUpsertCategory(budget.categories[idx]) }
        }
    }

    /// Applies income + all category limit changes in one shot with a single persist() call.
    /// Use this instead of calling updateMonthlyIncome + updateCategoryLimit in a loop —
    /// each of those calls persist() which JSON-encodes the entire expenses array, so N
    /// categories would trigger N+1 full serializations and block the main thread.
    func updateBudget(income: Double, categoryLimits: [UUID: Double]) {
        budget.monthlyIncome = income
        for i in budget.categories.indices {
            if let limit = categoryLimits[budget.categories[i].id], limit >= 0 {
                budget.categories[i].limit = limit
            }
        }
        updateCategorySpend()
        persist()
        Task { await supabaseSaveBudget() }
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
                    expense.scope == .household &&
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
    private let expenseKey          = "hemvo_expenses"
    private let budgetKey           = "hemvo_budget"
    private let deletedExpenseIDsKey  = "hemvo_deletedExpenseIDs"
    private let deletedCategoryIDsKey = "hemvo_deletedCategoryIDs"
    // Set once this device has either seen remote budget categories or seeded them
    // from the legacy local cache. Guards migrateBudgetToSupabase() so a legitimately
    // empty remote list (every category deleted) is never re-populated from a stale
    // local copy — which used to resurrect deleted categories across the household.
    private let budgetMigratedKey     = "hemvo_budgetMigratedToSupabase"

    init() {
        loadDeletedIDs()
        load()
        updateCategorySpend()
        Task { await loadFromSupabase() }
        // Reload whenever the app returns from background so any changes
        // made by other household members while inactive are picked up immediately.
        NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.loadFromSupabase() }
            }
            .store(in: &cancellables)
    }

    deinit {
        realtimeTask?.cancel()
        realtimeDebounce?.cancel()
        budgetRealtimeTask?.cancel()
        if let ch = realtimeChannel {
            Task { await supabase.realtimeV2.removeChannel(ch) }
        }
        if let ch = budgetRealtimeChannel {
            Task { await supabase.realtimeV2.removeChannel(ch) }
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

    private func loadDeletedIDs() {
        if let d = UserDefaults.standard.data(forKey: deletedExpenseIDsKey),
           let v = try? JSONDecoder().decode([UUID].self, from: d) {
            deletedExpenseIDs = Set(v)
        }
        if let d = UserDefaults.standard.data(forKey: deletedCategoryIDsKey),
           let v = try? JSONDecoder().decode([UUID].self, from: d) {
            deletedCategoryIDs = Set(v)
        }
    }

    private func persistDeletedIDs() {
        if let d = try? JSONEncoder().encode(Array(deletedExpenseIDs)) {
            UserDefaults.standard.set(d, forKey: deletedExpenseIDsKey)
        }
    }

    private func persistDeletedCategoryIDs() {
        if let d = try? JSONEncoder().encode(Array(deletedCategoryIDs)) {
            UserDefaults.standard.set(d, forKey: deletedCategoryIDsKey)
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
        if cachedHouseholdID == nil {
            cachedHouseholdID = UUID(uuidString: HouseholdService.shared.household?.id ?? "")
        }

        // Start the Realtime listeners the first time the household ID is resolved.
        if realtimeTask == nil, cachedHouseholdID != nil {
            startRealtimeSubscription()
        }
        if budgetRealtimeTask == nil, cachedHouseholdID != nil {
            startBudgetRealtimeSubscription()
        }

        // Load budget settings + categories from Supabase before processing expenses
        // so autoCreateCategory sees the full remote list and avoids re-creating
        // categories that already exist with custom limits.
        await loadBudgetFromSupabase()

        do {
            var query = supabase
                .from("expenses")
                .select()

            if let hid = cachedHouseholdID {
                // (household_id=X AND scope=household) OR (created_by=ME AND scope=personal)
                // The scoped arms mean another user's personal expense — which also has household_id=X —
                // is never returned, even before RLS kicks in.
                query = query.or(
                    "and(household_id.eq.\(hid.uuidString.lowercased()),scope.eq.household)," +
                    "and(created_by.eq.\(uid.uuidString.lowercased()),scope.eq.personal)"
                )
            } else {
                query = query.eq("created_by", value: uid.uuidString)
            }

            let rows: [SupabaseExpenseRow] = try await query.execute().value

            // Re-fire delete for tombstoned expenses still present remotely.
            let staleRows = rows.filter { deletedExpenseIDs.contains($0.id) }
            for row in staleRows { Task { await supabaseDelete(id: row.id) } }

            let remoteExpenses = rows.filter { !deletedExpenseIDs.contains($0.id) }.map { $0.toExpense() }

            // Clear tombstones only for IDs confirmed absent from Supabase.
            // Doing this here (not in supabaseDelete) closes a race where a concurrent
            // fetch could grab a row before the delete landed, then resurrect it after
            // the tombstone was prematurely removed.
            let remoteRowIDs = Set(rows.map { $0.id })
            let confirmedGone = deletedExpenseIDs.filter { !remoteRowIDs.contains($0) }
            if !confirmedGone.isEmpty {
                confirmedGone.forEach { deletedExpenseIDs.remove($0) }
                persistDeletedIDs()
            }

            // Merge: remote is authoritative except for a 10-second window after
            // this user marks a bill as paid, where the write may still be in flight.
            // Limiting by paidBy == current user ensures another member's "mark unpaid"
            // edit propagates correctly instead of being silently discarded.
            let localByID = Dictionary(uniqueKeysWithValues: expenses.map { ($0.id, $0) })
            let tenSecondsAgo = Date().addingTimeInterval(-10)
            let merged = remoteExpenses.map { remote -> Expense in
                if let local = localByID[remote.id],
                   local.isPaid, !remote.isPaid,
                   local.paidBy == cachedUserID?.uuidString,
                   let pd = local.paidDate, pd > tenSecondsAgo {
                    return local
                }
                return remote
            }
            let remoteIDs = Set(remoteExpenses.map { $0.id })
            // Only treat locally-stored expenses as "pending sync" when they were created
            // by the current user. An expense from another user that is absent from Supabase
            // was deleted by its creator — keeping it in pendingLocal would resurrect it in
            // every other member's UI and re-insert it into Supabase on the next upsert loop.
            let pendingLocal = expenses.filter { local in
                !remoteIDs.contains(local.id) &&
                !deletedExpenseIDs.contains(local.id) &&
                (local.createdBy == nil || local.createdBy == cachedUserID?.uuidString)
            }
            expenses = merged + pendingLocal
            // Before scheduling reminders, so a series that rolled over while the app was
            // closed has its new occurrence in hand and gets notifications for it.
            catchUpRecurringSeries()
            for e in expenses where e.scope == .household { autoCreateCategory(for: e.category) }
            updateCategorySpend()
            persist()
            if UserPreferences.shared.notifBills {
                NotificationService.shared.rescheduleAllBills(from: expenses)
            }
            for e in pendingLocal { Task { await supabaseUpsert(e) } }
        } catch {
            Logger.budget.error("fetch expenses error: \(error.localizedDescription)")
        }
    }

    private func supabaseUpsert(_ expense: Expense) async {
        // Resolve IDs on first call if loadFromSupabase hasn't run yet.
        if cachedUserID == nil {
            cachedUserID = await AuthService.shared.currentUserID()
        }
        if cachedHouseholdID == nil {
            cachedHouseholdID = (try? await AuthService.shared.loadProfile())?.householdId
                ?? UUID(uuidString: HouseholdService.shared.household?.id ?? "")
        }
        guard let uid = cachedUserID else { return }

        let row = SupabaseExpenseRow(from: expense, userId: uid, householdId: cachedHouseholdID)
        do {
            try await supabase
                .from("expenses")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            Logger.budget.error("upsert expense error: \(error.localizedDescription)")
        }
    }

    // Targeted UPDATE for just the two paid fields — avoids the INSERT RLS check
    // (created_by = auth.uid()) that a full upsert triggers even on the conflict/update path.
    // Any household member is allowed to UPDATE per the expenses_update policy.
    private func supabaseMarkPaid(_ expense: Expense) async {
        if cachedUserID == nil {
            cachedUserID = await AuthService.shared.currentUserID()
        }
        guard let uid = cachedUserID, let paidDate = expense.paidDate else { return }

        struct PaidFields: Encodable {
            let paidDate: Date
            let paidBy: UUID
            enum CodingKeys: String, CodingKey {
                case paidDate = "paid_date"
                case paidBy   = "paid_by"
            }
        }

        do {
            try await supabase
                .from("expenses")
                .update(PaidFields(paidDate: Calendar.current.startOfDay(for: paidDate), paidBy: uid))
                .eq("id", value: expense.id.uuidString)
                .execute()
        } catch {
            Logger.budget.error("mark paid error: \(error.localizedDescription)")
        }
    }

    // Clears `recurrence` on every occurrence of a series in one statement. Uses UPDATE
    // (allowed for any household member) rather than a per-row upsert, which would trip
    // the INSERT RLS check on rows created by someone else.
    private func supabaseStopSeries(seriesID: UUID) async {
        struct StopFields: Encodable {
            enum CodingKeys: String, CodingKey { case recurrence }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeNil(forKey: .recurrence)
            }
        }
        do {
            try await supabase
                .from("expenses")
                .update(StopFields())
                .eq("series_id", value: seriesID.uuidString)
                .execute()
        } catch {
            Logger.budget.error("stop series error: \(error.localizedDescription)")
        }
    }

    // Full-field UPDATE (not upsert) for edits to existing expenses.
    // Using .update() bypasses the INSERT RLS check (created_by = auth.uid())
    // that a full upsert triggers, so any household member can edit any expense.
    private func supabaseUpdateExpense(_ expense: Expense) async {
        if cachedUserID == nil {
            cachedUserID = await AuthService.shared.currentUserID()
        }
        guard cachedUserID != nil else { return }

        struct EditFields: Encodable {
            let title:        String
            let amount:       Double
            let category:     String
            let isRecurring:  Bool
            let isBill:       Bool
            let dueDate:      Date
            let paidDate:     Date?
            let paidBy:       UUID?
            let notes:        String
            let scope:        String
            let recurrence:   String?
            let seriesID:     UUID?
            let seriesAnchor: Date?
            enum CodingKeys: String, CodingKey {
                case title
                case amount
                case category
                case isRecurring  = "is_recurring"
                case isBill       = "is_bill"
                case dueDate      = "due_date"
                case paidDate     = "paid_date"
                case paidBy       = "paid_by"
                case notes
                case scope
                case recurrence
                case seriesID     = "series_id"
                case seriesAnchor = "series_anchor"
            }
            // Swift's synthesised Encodable uses encodeIfPresent for optionals,
            // which omits nil keys from the JSON body. PostgREST treats omitted
            // fields as "don't update", so paid_date would never be cleared.
            // Explicit encodeNil ensures the column is set to NULL in Supabase.
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(title,       forKey: .title)
                try c.encode(amount,      forKey: .amount)
                try c.encode(category,    forKey: .category)
                try c.encode(isRecurring, forKey: .isRecurring)
                try c.encode(isBill,      forKey: .isBill)
                try c.encode(dueDate,     forKey: .dueDate)
                try c.encode(notes,       forKey: .notes)
                try c.encode(scope,       forKey: .scope)
                if let pd = paidDate     { try c.encode(pd, forKey: .paidDate) }
                else                     { try c.encodeNil(forKey: .paidDate)  }
                if let pb = paidBy       { try c.encode(pb, forKey: .paidBy)   }
                else                     { try c.encodeNil(forKey: .paidBy)    }
                if let r  = recurrence   { try c.encode(r,  forKey: .recurrence) }
                else                     { try c.encodeNil(forKey: .recurrence)  }
                if let s  = seriesID     { try c.encode(s,  forKey: .seriesID) }
                else                     { try c.encodeNil(forKey: .seriesID)  }
                if let a  = seriesAnchor { try c.encode(a,  forKey: .seriesAnchor) }
                else                     { try c.encodeNil(forKey: .seriesAnchor)  }
            }
        }

        let fields = EditFields(
            title:        expense.title,
            amount:       expense.amount,
            category:     expense.category.rawValue,
            isRecurring:  expense.isRecurring,
            isBill:       expense.isBill,
            dueDate:      Calendar.current.startOfDay(for: expense.date),
            paidDate:     expense.paidDate.map { Calendar.current.startOfDay(for: $0) },
            paidBy:       expense.paidBy.flatMap { UUID(uuidString: $0) },
            notes:        expense.notes,
            scope:        expense.scope.rawValue,
            recurrence:   expense.recurrence?.rawValue,
            seriesID:     expense.seriesID,
            seriesAnchor: expense.seriesAnchor.map { Calendar.current.startOfDay(for: $0) }
        )

        do {
            try await supabase
                .from("expenses")
                .update(fields)
                .eq("id", value: expense.id.uuidString)
                .execute()
        } catch {
            Logger.budget.error("update expense error: \(error.localizedDescription)")
        }
    }

    // MARK: - Realtime

    private func startRealtimeSubscription() {
        guard let hid = cachedHouseholdID else { return }

        // Unique suffix avoids getting a cached already-subscribed channel back if the
        // previous ViewModel's async removeChannel() call hasn't finished yet.
        let channel = supabase.realtimeV2.channel("expenses:\(hid.uuidString):\(UUID().uuidString)")
        realtimeChannel = channel

        realtimeTask = Task { [weak self, channel] in
            // Register the listener BEFORE subscribing (required by the SDK).
            // UUID.rawValue = uuidString (uppercase). The Realtime server does a
            // case-sensitive string match against the CDC payload, which delivers
            // UUIDs in lowercase. Pass an explicit lowercase string so events match.
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "expenses",
                filter: .eq("household_id", value: hid.uuidString.lowercased())
            )

            do {
                try await channel.subscribeWithError()
            } catch {
                Logger.realtime.error("expenses subscribe error: \(error.localizedDescription)")
                // Clear so the next loadFromSupabase() can retry.
                await MainActor.run { [weak self] in self?.realtimeTask = nil }
                return
            }

            for await _ in changes {
                guard !Task.isCancelled, let self else { break }
                self.scheduleRealtimeReload()
            }

            // Channel cleanup is handled by removeChannel() in deinit.
            // If the subscription dropped naturally (not cancelled by deinit),
            // clear the reference so the next foreground-refresh can restart it.
            if !Task.isCancelled {
                await MainActor.run { [weak self] in self?.realtimeTask = nil }
            }
        }
    }

    // Debounce rapid bursts (e.g. a bulk edit) into a single reload.
    private func scheduleRealtimeReload() {
        realtimeDebounce?.cancel()
        realtimeDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.loadFromSupabase()
        }
    }

    private func supabaseDelete(id: UUID) async {
        do {
            // `.select()` makes PostgREST return the deleted rows.
            // An empty result means RLS blocked the delete — keep the tombstone
            // so the next loadFromSupabase() retries rather than re-adding the row.
            // Tombstone cleanup happens in loadFromSupabase() once absence is confirmed,
            // not here — removing it immediately would create a race where a concurrent
            // fetch resurrects the expense before this delete is visible to that fetch.
            let deleted: [SupabaseExpenseRow] = try await supabase
                .from("expenses")
                .delete()
                .eq("id", value: id.uuidString)
                .select()
                .execute()
                .value
            if deleted.isEmpty {
                Logger.budget.warning("delete may have been blocked by RLS")
            }
        } catch {
            Logger.budget.error("delete expense error: \(error.localizedDescription)")
        }
    }

    // MARK: - Budget Supabase sync

    private func loadBudgetFromSupabase() async {
        guard let hid = cachedHouseholdID else { return }
        do {
            async let settingsReq: [SupabaseBudgetSettingsRow] = supabase
                .from("budget_settings")
                .select()
                .eq("household_id", value: hid.uuidString)
                .execute()
                .value
            async let categoriesReq: [SupabaseBudgetCategoryRow] = supabase
                .from("budget_categories")
                .select()
                .eq("household_id", value: hid.uuidString)
                .execute()
                .value
            let (settings, remoteCategories) = try await (settingsReq, categoriesReq)

            if let s = settings.first {
                budget.monthlyIncome = s.monthlyIncome
            }

            // Clear tombstones only for IDs confirmed absent from Supabase, and
            // re-fire the delete for tombstoned rows still present — this fetch may
            // have raced ahead of a deleteCategory() whose remote delete is in flight.
            let remoteCategoryIDs = Set(remoteCategories.map { $0.id })
            let confirmedGone = deletedCategoryIDs.filter { !remoteCategoryIDs.contains($0) }
            if !confirmedGone.isEmpty {
                confirmedGone.forEach { deletedCategoryIDs.remove($0) }
                persistDeletedCategoryIDs()
            }
            let staleCategories = remoteCategories.filter { deletedCategoryIDs.contains($0.id) }
            for row in staleCategories { Task { await supabaseDeleteCategory(id: row.id) } }

            let liveCategories = remoteCategories.filter { !deletedCategoryIDs.contains($0.id) }
            let budgetSynced   = UserDefaults.standard.bool(forKey: budgetMigratedKey)
            if !remoteCategories.isEmpty {
                // Remote is authoritative; carry over in-memory spent amounts so the
                // progress bars don't flicker before updateCategorySpend() runs.
                // Replacing the whole array also drops any local category another member
                // deleted (now absent from remote).
                let spentByName = budget.categories.reduce(into: [String: Double]()) {
                    $0[$1.name.lowercased()] = $1.spent
                }
                budget.categories = liveCategories.map { row in
                    row.toBudgetCategory(spent: spentByName[row.name.lowercased()] ?? 0)
                }
                UserDefaults.standard.set(true, forKey: budgetMigratedKey)
            } else if !budgetSynced && !budget.categories.isEmpty {
                // True first launch after the Supabase-budget feature shipped: seed the
                // remote from the legacy local UserDefaults cache, exactly once. The flag
                // is set inside migrateBudgetToSupabase() only on success, so a failed
                // migrate is retried on the next load rather than clearing unsynced data.
                await migrateBudgetToSupabase()
            } else {
                // Remote is legitimately empty — every category was deleted (by any
                // member). Clear the stale local copies to match instead of re-uploading
                // them, which used to resurrect deleted categories on other devices.
                // Categories still backing an expense are re-created by the
                // autoCreateCategory sweep that runs after the expense fetch below.
                budget.categories.removeAll()
            }
        } catch {
            Logger.budget.error("loadBudget error: \(error.localizedDescription)")
        }
    }

    /// Pushes existing UserDefaults budget data to Supabase on first launch.
    private func migrateBudgetToSupabase() async {
        guard let hid = cachedHouseholdID else { return }
        do {
            let settingsRow = SupabaseBudgetSettingsRow(
                householdId: hid, monthlyIncome: budget.monthlyIncome)
            try await supabase
                .from("budget_settings")
                .upsert(settingsRow, onConflict: "household_id")
                .execute()

            let rows = budget.categories.map {
                SupabaseBudgetCategoryRow(id: $0.id, householdId: hid,
                                          name: $0.name, limitAmount: $0.limit)
            }
            if !rows.isEmpty {
                try await supabase
                    .from("budget_categories")
                    .upsert(rows, onConflict: "id")
                    .execute()
            }
            // Only now that the seed landed — a failed migrate leaves the flag unset so
            // the next load retries instead of clearing the still-unsynced local data.
            UserDefaults.standard.set(true, forKey: budgetMigratedKey)
            Logger.budget.debug("budget migrated from UserDefaults")
        } catch {
            Logger.budget.error("migrateBudget error: \(error.localizedDescription)")
        }
    }

    /// Saves monthly income + all category limits to Supabase in one shot.
    private func supabaseSaveBudget() async {
        guard let hid = cachedHouseholdID else { return }
        do {
            let settingsRow = SupabaseBudgetSettingsRow(
                householdId: hid, monthlyIncome: budget.monthlyIncome)
            try await supabase
                .from("budget_settings")
                .upsert(settingsRow, onConflict: "household_id")
                .execute()

            let rows = budget.categories.map {
                SupabaseBudgetCategoryRow(id: $0.id, householdId: hid,
                                          name: $0.name, limitAmount: $0.limit)
            }
            if !rows.isEmpty {
                try await supabase
                    .from("budget_categories")
                    .upsert(rows, onConflict: "id")
                    .execute()
            }
        } catch {
            Logger.budget.error("saveBudget error: \(error.localizedDescription)")
        }
    }

    private func supabaseUpsertCategory(_ category: BudgetCategory) async {
        guard let hid = cachedHouseholdID else { return }
        let row = SupabaseBudgetCategoryRow(
            id: category.id, householdId: hid,
            name: category.name, limitAmount: category.limit)
        do {
            try await supabase
                .from("budget_categories")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            Logger.budget.error("upsert category error: \(error.localizedDescription)")
        }
    }

    private func supabaseDeleteCategory(id: UUID) async {
        do {
            try await supabase
                .from("budget_categories")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            Logger.budget.error("delete category error: \(error.localizedDescription)")
        }
    }

    // MARK: - Budget Realtime

    private func startBudgetRealtimeSubscription() {
        guard let hid = cachedHouseholdID else { return }
        let channel = supabase.realtimeV2.channel(
            "budget_categories:\(hid.uuidString):\(UUID().uuidString)")
        budgetRealtimeChannel = channel

        budgetRealtimeTask = Task { [weak self, channel] in
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "budget_categories",
                filter: .eq("household_id", value: hid.uuidString.lowercased())
            )
            do {
                try await channel.subscribeWithError()
            } catch {
                Logger.realtime.error("budget_categories subscribe error: \(error.localizedDescription)")
                await MainActor.run { [weak self] in self?.budgetRealtimeTask = nil }
                return
            }
            for await _ in changes {
                guard !Task.isCancelled, let self else { break }
                self.scheduleRealtimeReload()
            }
            if !Task.isCancelled {
                await MainActor.run { [weak self] in self?.budgetRealtimeTask = nil }
            }
        }
    }
}

// MARK: - Supabase row mapping — budget

private struct SupabaseBudgetSettingsRow: Codable {
    let householdId:   UUID
    var monthlyIncome: Double
    enum CodingKeys: String, CodingKey {
        case householdId   = "household_id"
        case monthlyIncome = "monthly_income"
    }
}

private struct SupabaseBudgetCategoryRow: Codable {
    let id:          UUID
    let householdId: UUID
    var name:        String
    var limitAmount: Double
    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case name
        case limitAmount = "limit_amount"
    }
    func toBudgetCategory(spent: Double = 0) -> BudgetCategory {
        BudgetCategory(id: id, name: name, limit: limitAmount, spent: spent)
    }
}

// MARK: - Supabase row mapping — expenses
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
    var paidBy:      UUID?
    var notes:       String
    var scope:       String
    let createdBy:   UUID
    var recurrence:   String?
    var seriesId:     UUID?
    var seriesAnchor: Date?

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
        case paidBy      = "paid_by"
        case notes
        case scope
        case createdBy    = "created_by"
        case recurrence
        case seriesId     = "series_id"
        case seriesAnchor = "series_anchor"
    }

    // Custom Codable decode so that rows fetched before the scope migration was applied
    // (which lack the `scope` column in the response) fall back to "household" instead
    // of throwing keyNotFound and aborting the entire load.
    init(from decoder: Decoder) throws {
        let c       = try decoder.container(keyedBy: CodingKeys.self)
        id          = try  c.decode(UUID.self,   forKey: .id)
        householdId = try? c.decode(UUID.self,   forKey: .householdId)
        title       = try  c.decode(String.self, forKey: .title)
        amount      = try  c.decode(Double.self, forKey: .amount)
        category    = try? c.decode(String.self, forKey: .category)
        isBill      = try  c.decode(Bool.self,   forKey: .isBill)
        isRecurring = try  c.decode(Bool.self,   forKey: .isRecurring)
        dueDate     = try? c.decode(Date.self,   forKey: .dueDate)
        paidDate    = try? c.decode(Date.self,   forKey: .paidDate)
        paidBy      = try? c.decode(UUID.self,   forKey: .paidBy)
        notes       = (try? c.decode(String.self, forKey: .notes)) ?? ""
        scope       = (try? c.decode(String.self, forKey: .scope)) ?? "household"
        createdBy   = try  c.decode(UUID.self,   forKey: .createdBy)
        // Optional like `scope` above: rows fetched before the recurring-series migration
        // lack these columns entirely, and must decode as a plain one-off bill rather than
        // throwing keyNotFound and aborting the whole load.
        recurrence   = try? c.decode(String.self, forKey: .recurrence)
        seriesId     = try? c.decode(UUID.self,   forKey: .seriesId)
        seriesAnchor = try? c.decode(Date.self,   forKey: .seriesAnchor)
    }

    init(from expense: Expense, userId: UUID, householdId: UUID?) {
        id               = expense.id
        createdBy        = expense.createdBy.flatMap { UUID(uuidString: $0) } ?? userId
        self.householdId = householdId
        title            = expense.title
        amount           = expense.amount
        category         = expense.category.rawValue
        isBill           = expense.isBill
        isRecurring      = expense.isRecurring
        dueDate          = Calendar.current.startOfDay(for: expense.date)
        paidDate         = expense.paidDate.map { Calendar.current.startOfDay(for: $0) }
        paidBy           = expense.paidBy.flatMap { UUID(uuidString: $0) }
        notes            = expense.notes
        scope            = expense.scope.rawValue
        recurrence       = expense.recurrence?.rawValue
        seriesId         = expense.seriesID
        seriesAnchor     = expense.seriesAnchor.map { Calendar.current.startOfDay(for: $0) }
    }

    func toExpense() -> Expense {
        Expense(
            id:           id,
            title:        title,
            amount:       amount,
            category:     category.flatMap(Expense.ExpenseCategory.init(rawValue:)) ?? .other,
            date:         dueDate ?? Date(),
            isPaid:       paidDate != nil,
            paidDate:     paidDate,
            // Rows written by the old app set is_bill and is_recurring to the same value, so
            // either one being true means "bill". Whether it actually repeats is decided by
            // `recurrence` alone — the only column that ever carried a cadence.
            isBill:       isBill || isRecurring,
            notes:        notes,
            scope:        BudgetScope(rawValue: scope) ?? .household,
            createdBy:    createdBy.uuidString,
            paidBy:       paidBy?.uuidString,
            recurrence:   recurrence.flatMap(RecurrenceRule.init(rawValue:)),
            seriesID:     seriesId,
            seriesAnchor: seriesAnchor
        )
    }
}
