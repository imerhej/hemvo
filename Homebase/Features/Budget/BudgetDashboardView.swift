//  BudgetDashboardView.swift
//  HomeBase
//  Redesigned with warm amber/cream palette. Paid bills live in BillHistoryView.

internal import SwiftUI
internal import Combine

// MARK: - Warm palette tokens
private extension Color {
    static let wBg       = Color(hex: "#FAF7F2")!   // cream background
    static let wAmber    = Color(hex: "#C8922A")!   // primary accent
    static let wAmberSoft = Color(hex: "#F5E4C3")!  // amber tint
    static let wBrown    = Color(hex: "#1A1208")!   // primary text
    static let wMuted    = Color(hex: "#7A6A55")!   // secondary text
    static let wDivider  = Color(hex: "#E6DDD0")!   // borders
    static let wSurface  = Color(hex: "#FFFFFF")!   // card surface
    static let wGreen    = Color(hex: "#3D7A52")!   // positive / remaining
}

// MARK: - BudgetDashboardView
struct BudgetDashboardView: View {

    @StateObject private var vm          = BudgetViewModel()
    @State private var showAddExpense    = false
    @State private var showBillReminder  = false
    @State private var showBudgetEditor  = false
    @State private var showHistory       = false
    @State private var expenseToEdit: Expense? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color.wBg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // ── Warm header ──────────────────────
                        headerBar
                        // ── Month selector ───────────────────
                        monthStrip.padding(.horizontal, 20).padding(.top, 18)
                        // ── Hero budget card ─────────────────
                        heroCard.padding(.horizontal, 20).padding(.top, 16)
                        // ── Stats row ────────────────────────
                        statsRow.padding(.horizontal, 20).padding(.top, 16)
                        // ── Categories ───────────────────────
                        categorySection.padding(.horizontal, 20).padding(.top, 20)
                        // ── Upcoming bills ───────────────────
                        billsSection.padding(.horizontal, 20).padding(.top, 20)
                        // ── Recent expenses ──────────────────
                        recentSection.padding(.horizontal, 20).padding(.top, 20)
                            .padding(.bottom, 100)
                    }
                }

                // ── FAB ──────────────────────────────────────
                addFAB.padding(.trailing, 22).padding(.bottom, 32)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showAddExpense,   onDismiss: { vm.objectWillChange.send() }) { AddExpenseView(vm: vm) }
            .sheet(isPresented: $showBillReminder) { BillReminderView(vm: vm) }
            .sheet(isPresented: $showBudgetEditor, onDismiss: { vm.objectWillChange.send() }) { BudgetEditorView(vm: vm) }
            .sheet(isPresented: $showHistory)      { BillHistoryView(vm: vm) }
            .sheet(item: $expenseToEdit,           onDismiss: { vm.objectWillChange.send() }) { EditExpenseView(vm: vm, expense: $0) }
        }
    }

    // MARK: - Header
    private var headerBar: some View {
        ZStack {
            Color.wSurface
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BUDGET")
                        .font(.system(size: 10, weight: .heavy)).kerning(3)
                        .foregroundColor(Color.wAmber)
                    Text("Overview")
                        .font(.system(size: 26, weight: .black))
                        .foregroundColor(Color.wBrown)
                }
                Spacer()
                HStack(spacing: 10) {
                    // History button
                    Button { showHistory = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12, weight: .bold))
                            Text("History")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(Color.wAmber)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.wAmberSoft)
                        .cornerRadius(20)
                    }
                    // Edit limits
                    Button { showBudgetEditor = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.wAmber)
                            .frame(width: 36, height: 36)
                            .background(Color.wAmberSoft)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 52)
            .padding(.bottom, 14)
        }
        .frame(height: 120)
        .overlay(alignment: .bottom) { Color.wDivider.frame(height: 1) }
    }

    // MARK: - Month Strip
    private var monthStrip: some View {
        HStack {
            Button { vm.previousMonth() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.wAmber)
                    .frame(width: 34, height: 34)
                    .background(Color.wAmberSoft)
                    .clipShape(Circle())
            }
            Spacer()
            VStack(spacing: 2) {
                Text(vm.selectedMonth.monthYearDisplay)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.wBrown)
                if Calendar.current.isDate(vm.selectedMonth, equalTo: Date(), toGranularity: .month) {
                    Text("Current Month")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.wMuted)
                }
            }
            Spacer()
            Button { vm.nextMonth() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.wAmber)
                    .frame(width: 34, height: 34)
                    .background(Color.wAmberSoft)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Hero Budget Card
    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(
                    colors: [Color(hex: "#C8922A")!, Color(hex: "#E6A83A")!],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Circle().fill(Color.white.opacity(0.07)).frame(width: 180).offset(x: 110, y: -50)
            Circle().fill(Color.white.opacity(0.05)).frame(width: 110).offset(x: -60, y: 70)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monthly Budget")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        Text("$\(Int(vm.budget.monthlyIncome))")
                            .font(.system(size: 36, weight: .black))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Remaining")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        Text(vm.remainingBudget < 0
                             ? "-$\(Int(abs(vm.remainingBudget)))"
                             : "$\(Int(vm.remainingBudget))")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(vm.remainingBudget < 0
                                             ? Color(hex: "#FF6B6B")! : .white)
                    }
                }

                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.22)).frame(height: 10)
                            Capsule()
                                .fill(vm.spentPercent > 0.9
                                      ? LinearGradient(colors: [Color(hex: "#FF6B6B")!, .orange],
                                                       startPoint: .leading, endPoint: .trailing)
                                      : LinearGradient(colors: [.white, .white.opacity(0.75)],
                                                       startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * vm.spentPercent, height: 10)
                                .animation(.spring(response: 0.6), value: vm.spentPercent)
                        }
                    }
                    .frame(height: 10)

                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 11))
                            Text("$\(Int(vm.totalSpent)) spent")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Text("\(Int(vm.spentPercent * 100))% of budget used")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(22)
        }
        .shadow(color: Color.wAmber.opacity(0.4), radius: 20, y: 8)
    }

    // MARK: - Stats Row
    private var statsRow: some View {
        HStack(spacing: 10) {
            WarmStatTile(value: "$\(Int(vm.totalSpent))",
                         label: "Spent",
                         icon: "arrow.up.circle.fill",
                         iconColor: Color(hex: "#C0392B")!)

            WarmStatTile(value: "\(vm.monthlyExpenses.filter { !$0.isPaid }.count)",
                         label: "Transactions",
                         icon: "list.bullet.rectangle.fill",
                         iconColor: Color.wAmber)

            WarmStatTile(value: "\(vm.upcomingBills.count)",
                         label: "Bills Due",
                         icon: "calendar.badge.exclamationmark",
                         iconColor: Color(hex: "#E67E22")!)

            WarmStatTile(value: "\(vm.budgetCategories.filter { $0.isOverBudget }.count)",
                         label: "Over Limit",
                         icon: "exclamationmark.triangle.fill",
                         iconColor: Color(hex: "#C0392B")!)
        }
    }

    // MARK: - Category Section
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            warmSectionHeader(icon: "chart.bar.fill", title: "Spending by Category") {
                EmptyView()
            }

            if vm.budgetCategories.isEmpty {
                WarmEmptyState(icon: "chart.bar.xaxis", message: "Add an expense and categories appear automatically.")
            } else {
                VStack(spacing: 10) {
                    ForEach(vm.budgetCategories) { cat in
                        WarmCategoryRow(
                            category: cat,
                            onEdit:   { showBudgetEditor = true },
                            onDelete: { vm.deleteCategory(cat) }
                        )
                    }
                }
            }
        }
        .warmCard()
    }

    // MARK: - Bills Section
    private var billsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            warmSectionHeader(icon: "calendar.badge.exclamationmark", title: "Upcoming Bills") {
                Button { showBillReminder = true } label: {
                    Text("Manage")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.wAmber)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.wAmberSoft)
                        .cornerRadius(20)
                }
            }

            if vm.upcomingBills.isEmpty {
                WarmEmptyState(icon: "checkmark.seal.fill", message: "No unpaid bills — all clear!")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(vm.upcomingBills.prefix(4).enumerated()), id: \.element.id) { idx, bill in
                        WarmBillRow(bill: bill) { vm.markBillPaid(bill) }
                        if idx < min(vm.upcomingBills.count, 4) - 1 {
                            Color.wDivider.frame(height: 1).padding(.horizontal, 2)
                        }
                    }
                }
                if vm.upcomingBills.count > 4 {
                    Button { showBillReminder = true } label: {
                        Text("View all \(vm.upcomingBills.count) bills")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color.wAmber)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.wAmberSoft)
                            .cornerRadius(12)
                    }
                }
            }
        }
        .warmCard()
    }

    // MARK: - Recent Expenses Section
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            warmSectionHeader(icon: "creditcard.fill", title: "Recent Expenses") {
                Button { showHistory = true } label: {
                    Text("History")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.wAmber)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.wAmberSoft)
                        .cornerRadius(20)
                }
            }

            // Only show unpaid expenses here; paid ones live in History
            let recent = vm.monthlyExpenses.filter { !$0.isPaid }
            if recent.isEmpty {
                WarmEmptyState(icon: "tray.fill", message: "No unpaid expenses this month.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.prefix(5).enumerated()), id: \.element.id) { idx, expense in
                        ExpenseRow(
                            expense:  expense,
                            onEdit:   { expenseToEdit = expense },
                            onDelete: { vm.deleteExpense(expense) }
                        )
                        if idx < min(recent.count, 5) - 1 {
                            Color.wDivider.frame(height: 1).padding(.leading, 50)
                        }
                    }
                }
            }
        }
        .warmCard()
    }

    // MARK: - FAB
    private var addFAB: some View {
        Button { showAddExpense = true } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 28, height: 28)
                    Image(systemName: "plus").font(.system(size: 14, weight: .black)).foregroundColor(.white)
                }
                Text("Add Expense").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(Capsule().fill(Color.wAmber)
                .shadow(color: Color.wAmber.opacity(0.45), radius: 16, y: 6))
        }
    }

    // MARK: - Section Header Builder
    @ViewBuilder
    private func warmSectionHeader<T: View>(icon: String, title: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(Color.wAmberSoft).frame(width: 28, height: 28)
                Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundColor(Color.wAmber)
            }
            Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(Color.wBrown)
            Spacer()
            trailing()
        }
    }
}

// MARK: - Warm Card Modifier
private extension View {
    func warmCard() -> some View {
        self
            .padding(16)
            .background(Color.wSurface)
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.wDivider, lineWidth: 1))
            .shadow(color: Color.wBrown.opacity(0.06), radius: 10, y: 4)
    }
}

// MARK: - WarmStatTile
struct WarmStatTile: View {
    let value:     String
    let label:     String
    let icon:      String
    let iconColor: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(iconColor.opacity(0.1)).frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundColor(iconColor)
            }
            Text(value).font(.system(size: 15, weight: .black)).foregroundColor(Color.wBrown)
            Text(label).font(.system(size: 9, weight: .heavy)).kerning(0.5).foregroundColor(Color.wMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.wSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.wDivider, lineWidth: 1))
        .shadow(color: Color.wBrown.opacity(0.04), radius: 6, y: 2)
    }
}

// MARK: - WarmCategoryRow
struct WarmCategoryRow: View {
    let category: BudgetCategory
    let onEdit:   () -> Void
    let onDelete: () -> Void

    @State private var showDeleteAlert = false

    private var catColor: Color {
        let palette: [Color] = [
            Color(hex: "#C8922A")!, Color(hex: "#1565C0")!, Color(hex: "#C0392B")!,
            Color(hex: "#6A1B9A")!, Color(hex: "#3D7A52")!, Color(hex: "#00838F")!,
            Color(hex: "#4E342E")!
        ]
        return palette[abs(category.name.hashValue) % palette.count]
    }

    private var catIcon: String {
        switch category.name {
        case "Groceries":       return "cart.fill"
        case "Utilities":       return "bolt.fill"
        case "Entertainment":   return "tv.fill"
        case "Transportation":  return "car.fill"
        case "Healthcare":      return "cross.case.fill"
        case "Dining Out":      return "fork.knife"
        case "Mortgage / Rent": return "house.fill"
        case "Insurance":       return "shield.fill"
        case "Credit Card":     return "creditcard.fill"
        default:                return "dollarsign.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(catColor.opacity(0.12)).frame(width: 38, height: 38)
                    Image(systemName: catIcon).font(.system(size: 14, weight: .semibold)).foregroundColor(catColor)
                }
                // Name + spend
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name).font(.system(size: 14, weight: .bold)).foregroundColor(Color.wBrown)
                    HStack(spacing: 4) {
                        if category.spent > 0 {
                            Text("$\(Int(category.spent)) of $\(Int(category.limit))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(category.isOverBudget ? Color(hex: "#C0392B")! : Color.wMuted)
                        } else {
                            Text("No spending yet")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.wMuted.opacity(0.7))
                        }
                    }
                }
                Spacer()
                // Limit + actions
                VStack(alignment: .trailing, spacing: 4) {
                    Text("$\(Int(category.limit))")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(category.isOverBudget ? Color(hex: "#C0392B")! : Color.wBrown)
                    Text("limit").font(.system(size: 9, weight: .medium)).foregroundColor(Color.wMuted)
                }

                // Edit
                Button { onEdit() } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.wAmber)
                        .frame(width: 28, height: 28)
                        .background(Color.wAmberSoft)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Delete
                Button {
                    category.spent > 0 ? (showDeleteAlert = true) : onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(category.spent > 0 ? Color.wMuted.opacity(0.4) : .red)
                        .frame(width: 28, height: 28)
                        .background(category.spent > 0 ? Color.wDivider : Color.red.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.wDivider).frame(height: 7)
                    Capsule()
                        .fill(LinearGradient(
                            colors: category.isOverBudget
                                ? [Color(hex: "#C0392B")!, Color(hex: "#FF6B6B")!]
                                : [catColor, catColor.opacity(0.5)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * category.percentUsed, height: 7)
                        .animation(.spring(response: 0.5), value: category.percentUsed)
                }
            }
            .frame(height: 7)
        }
        .padding(12)
        .background(catColor.opacity(0.03))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.wDivider, lineWidth: 1))
        .alert("Cannot Delete", isPresented: $showDeleteAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\"\(category.name)\" has $\(Int(category.spent)) in spending. Remove all expenses in this category first.")
        }
    }
}

// MARK: - WarmBillRow
struct WarmBillRow: View {
    let bill:  Expense
    let onPay: () -> Void

    private var daysUntil: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: bill.date).day ?? 0
    }
    private var urgencyColor: Color {
        daysUntil < 0 ? Color(hex: "#C0392B")! : daysUntil <= 3 ? Color(hex: "#E67E22")! : Color.wAmber
    }
    private var urgencyLabel: String {
        daysUntil < 0 ? "Overdue \(abs(daysUntil))d" : daysUntil == 0 ? "Due today" : daysUntil == 1 ? "Tomorrow" : "In \(daysUntil)d"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(urgencyColor.opacity(0.1)).frame(width: 36, height: 36)
                Image(systemName: bill.category.iconName)
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(urgencyColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(bill.title).font(.system(size: 14, weight: .bold)).foregroundColor(Color.wBrown)
                HStack(spacing: 5) {
                    Text(urgencyLabel)
                        .font(.system(size: 10, weight: .heavy)).foregroundColor(urgencyColor)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(urgencyColor.opacity(0.1)).cornerRadius(20)
                    Text(bill.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10, weight: .medium)).foregroundColor(Color.wMuted)
                }
            }
            Spacer()
            Text(bill.formattedAmount)
                .font(.system(size: 15, weight: .black)).foregroundColor(Color.wBrown)
            Button { onPay() } label: {
                Text("Pay")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.wAmber)
                    .cornerRadius(20)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - WarmEmptyState
struct WarmEmptyState: View {
    let icon:    String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Color.wAmber.opacity(0.5))
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.wMuted)
                .multilineTextAlignment(.leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.wAmberSoft.opacity(0.5))
        .cornerRadius(12)
    }
}

// MARK: - ExpenseRow (warm-styled)
struct ExpenseRow: View {
    let expense:  Expense
    let onEdit:   () -> Void
    let onDelete: () -> Void

    @State private var showDeleteAlert = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(expense.category.displayColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: expense.category.iconName)
                    .foregroundColor(expense.category.displayColor)
                    .font(.system(size: 14, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title).font(.system(size: 14, weight: .bold)).foregroundColor(Color.wBrown)
                Text(expense.date.shortDisplayDate)
                    .font(.system(size: 11, weight: .medium)).foregroundColor(Color.wMuted)
            }
            Spacer()
            Text("-\(expense.formattedAmount)")
                .font(.system(size: 14, weight: .black)).foregroundColor(Color(hex: "#C0392B")!)
            Button { onEdit() } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.wAmber)
                    .frame(width: 26, height: 26).background(Color.wAmberSoft).clipShape(Circle())
            }
            .buttonStyle(.plain)
            Button { showDeleteAlert = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
                    .frame(width: 26, height: 26).background(Color.red.opacity(0.08)).clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 9)
        .alert("Delete Expense", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Remove \"\(expense.title)\"?") }
    }
}

// MARK: - BudgetOverviewCard (kept for compatibility)
struct BudgetOverviewCard: View {
    @ObservedObject var vm: BudgetViewModel
    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly Budget").font(.subheadline).foregroundColor(.secondary)
                    Text("$\(String(format: "%.2f", vm.budget.monthlyIncome))").font(.title).bold()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Remaining").font(.subheadline).foregroundColor(.secondary)
                    Text("$\(String(format: "%.2f", vm.remainingBudget))")
                        .font(.title2).bold()
                        .foregroundColor(vm.remainingBudget < 0 ? .red : .homeBaseGreen)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

// MARK: - BillRowView (kept for compatibility)
struct BillRowView: View {
    let bill: Expense
    let onPay: () -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.title).font(.subheadline).bold()
                Text("Due \(bill.date.relativeLabel)").font(.caption).foregroundColor(.orange)
            }
            Spacer()
            Text(bill.formattedAmount).font(.subheadline).bold()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    BudgetDashboardView()
}
