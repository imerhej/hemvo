//
//  BudgetViewModelTests.swift
//  Hemvo
//
//  Created by Issam Merhej on 3/15/26.
//

import Testing
import Foundation
@testable import Hemvo

@MainActor
struct BudgetViewModelTests {

    /// Builds a VM with injected state, bypassing UserDefaults/Supabase.
    private func makeVM(expenses: [Expense],
                        categories: [BudgetCategory]) -> BudgetViewModel {
        let vm = BudgetViewModel()
        vm.budget = Budget(monthlyIncome: 5000, categories: categories)
        vm.expenses = expenses
        vm.updateCategorySpend()
        return vm
    }

    // A bill counts toward category spend the moment it's created — in the month
    // of its due date, before it's paid — while still listed under Upcoming Bills.
    @Test func unpaidRecurringBillCountsAsCategorySpendImmediately() {
        let bill = Expense(title: "Electricity", amount: 70,
                           category: .utilities, date: Date(),
                           isRecurring: true)
        let vm = makeVM(expenses: [bill],
                        categories: [BudgetCategory(name: "Utilities", limit: 500)])

        #expect(vm.budgetCategories.first?.spent == 70)
        #expect(vm.totalSpent == 70)
        #expect(vm.upcomingBills.count == 1)
    }

    // Month scoping is what keeps months separate: a bill due this month must not
    // bleed into the next month's category spend.
    @Test func unpaidBillDoesNotLeakIntoNextMonth() {
        let bill = Expense(title: "Electricity", amount: 70,
                           category: .utilities, date: Date(),
                           isRecurring: true)
        let vm = makeVM(expenses: [bill],
                        categories: [BudgetCategory(name: "Utilities", limit: 500)])

        vm.nextMonth()
        #expect(vm.budgetCategories.first?.spent == 0)
        #expect(vm.totalSpent == 0)
    }

    @Test func paidRecurringBillCountsAsCategorySpend() {
        let bill = Expense(title: "Electricity", amount: 70,
                           category: .utilities, date: Date(),
                           isPaid: true, paidDate: Date(),
                           isRecurring: true)
        let vm = makeVM(expenses: [bill],
                        categories: [BudgetCategory(name: "Utilities", limit: 500)])

        #expect(vm.budgetCategories.first?.spent == 70)
        #expect(vm.totalSpent == 70)
        #expect(vm.upcomingBills.isEmpty)
    }

    @Test func nonRecurringExpenseCountsAsCategorySpend() {
        let expense = Expense(title: "Weekly shop", amount: 120,
                              category: .groceries, date: Date())
        let vm = makeVM(expenses: [expense],
                        categories: [BudgetCategory(name: "Groceries", limit: 500)])

        #expect(vm.budgetCategories.first?.spent == 120)
        #expect(vm.totalSpent == 120)
    }

    // Each month has its own category spend — last month's expenses must not
    // leak into the next month when navigating.
    @Test func categorySpendResetsWhenMonthChanges() {
        let expense = Expense(title: "Weekly shop", amount: 120,
                              category: .groceries, date: Date())
        let vm = makeVM(expenses: [expense],
                        categories: [BudgetCategory(name: "Groceries", limit: 500)])
        #expect(vm.budgetCategories.first?.spent == 120)

        vm.nextMonth()
        #expect(vm.budgetCategories.first?.spent == 0)
        #expect(vm.totalSpent == 0)

        vm.previousMonth()
        #expect(vm.budgetCategories.first?.spent == 120)
        #expect(vm.totalSpent == 120)
    }

    // The budget editor shows a fresh slate each month: categories used only in
    // other months are hidden (their limits kept), while this month's categories
    // and never-used ones remain visible.
    @Test func monthCategoriesAreScopedToSelectedMonth() {
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        let junePayment = Expense(title: "Rent", amount: 900,
                                  category: .mortgage, date: lastMonth,
                                  isPaid: true, paidDate: lastMonth)
        let julyExpense = Expense(title: "Weekly shop", amount: 120,
                                  category: .groceries, date: Date())
        let vm = makeVM(
            expenses: [junePayment, julyExpense],
            categories: [BudgetCategory(name: "Mortgage / Rent", limit: 1000),
                         BudgetCategory(name: "Groceries", limit: 500),
                         BudgetCategory(name: "Savings", limit: 200)]   // never used
        )

        let visible = vm.monthCategories.map(\.name)
        #expect(visible == ["Groceries", "Savings"])

        // Last month still shows its own category with its own spend.
        vm.previousMonth()
        #expect(vm.monthCategories.map(\.name) == ["Mortgage / Rent", "Savings"])
        #expect(vm.monthCategories.first?.spent == 900)
    }

    @Test func deleteCategoryRemovesUnusedCategory() {
        let vm = makeVM(expenses: [],
                        categories: [BudgetCategory(name: "Groceries", limit: 500)])

        vm.deleteCategory(vm.budgetCategories[0])
        #expect(vm.budgetCategories.isEmpty)
    }

    // A category referenced by any expense — even one from a past month or an
    // unpaid bill — must refuse deletion, because autoCreateCategory would
    // silently recreate it on the next Supabase sync.
    @Test func deleteCategoryRefusedWhileExpensesStillUseIt() {
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        let old = Expense(title: "Old shop", amount: 50,
                          category: .groceries, date: lastMonth)
        let vm = makeVM(expenses: [old],
                        categories: [BudgetCategory(name: "Groceries", limit: 500)])

        #expect(vm.isCategoryInUse(vm.budgetCategories[0]))
        vm.deleteCategory(vm.budgetCategories[0])
        #expect(vm.budgetCategories.count == 1)
    }

    @Test func personalExpensesDoNotMarkCategoryInUse() {
        let personal = Expense(title: "Coffee", amount: 6,
                               category: .dining, date: Date(),
                               scope: .personal)
        let vm = makeVM(expenses: [personal],
                        categories: [BudgetCategory(name: "Dining Out", limit: 200)])

        #expect(!vm.isCategoryInUse(vm.budgetCategories[0]))
    }

    @Test func personalExpensesDoNotCountTowardHouseholdCategories() {
        let personal = Expense(title: "Coffee", amount: 6,
                               category: .dining, date: Date(),
                               scope: .personal)
        let vm = makeVM(expenses: [personal],
                        categories: [BudgetCategory(name: "Dining Out", limit: 200)])

        #expect(vm.budgetCategories.first?.spent == 0)
    }
}
