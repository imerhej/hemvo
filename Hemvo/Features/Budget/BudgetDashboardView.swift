//  BudgetDashboardView.swift
//  Hemvo
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
                addFAB.padding(.trailing, 16).padding(.bottom, 10)
            }
            .navigationBarHidden(true)
            .task { await vm.loadFromSupabase() }
            .sheet(isPresented: $showAddExpense,   onDismiss: { vm.objectWillChange.send() }) { AddExpenseView(vm: vm) }
            .sheet(isPresented: $showBillReminder) { BillReminderView(vm: vm) }
            .sheet(isPresented: $showBudgetEditor, onDismiss: { vm.objectWillChange.send() }) { BudgetEditorView(vm: vm) }
            .sheet(isPresented: $showHistory)      { BillHistoryView(vm: vm, initialMonth: vm.selectedMonth) }
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
        Button { showBudgetEditor = true } label: {
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
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.6))
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
        .buttonStyle(.plain)
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

            let activeCategories = vm.budgetCategories.filter { $0.spent > 0 }
            if activeCategories.isEmpty {
                WarmEmptyState(icon: "chart.bar.xaxis", message: "Add an expense and categories appear automatically.")
            } else {
                VStack(spacing: 10) {
                    ForEach(activeCategories) { cat in
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
                        WarmBillRow(bill: bill)
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

            // Show only non-recurring expenses and paid bills — unpaid recurring bills belong in Upcoming Bills only
            let recent = vm.monthlyExpenses.filter { !$0.isRecurring || $0.isPaid }
            if recent.isEmpty {
                WarmEmptyState(icon: "tray.fill", message: "No expenses this month.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.prefix(5).enumerated()), id: \.element.id) { idx, expense in
                        ExpenseRow(
                            expense:   expense,
                            canDelete: vm.canDelete(expense),
                            onEdit:    { expenseToEdit = expense },
                            onDelete:  { vm.deleteExpense(expense) }
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
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 22, height: 22)
                    Image(systemName: "plus").font(.system(size: 11, weight: .black)).foregroundColor(.white)
                }
                Text("Add Expense").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Capsule().fill(Color.wAmber)
                .shadow(color: Color.wAmber.opacity(0.35), radius: 6, y: 2))
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
        switch category.name {
        case "Groceries":       return Color(hex: "#3D7A52")!
        case "Utilities":       return Color(hex: "#1565C0")!
        case "Entertainment":   return Color(hex: "#E67E22")!
        case "Transportation":  return Color(hex: "#4E342E")!
        case "Healthcare":      return Color(hex: "#C0392B")!
        case "Dining Out":      return Color(hex: "#FF9800")!
        case "Mortgage / Rent": return Color(hex: "#6A1B9A")!
        case "Insurance":       return Color(hex: "#00838F")!
        case "Credit Card":     return Color(hex: "#1A237E")!
        default:                return Color(hex: "#7A6A55")!
        }
    }

    private var barColor: [Color] {
        if category.isOverBudget {
            return [Color(hex: "#C0392B")!, Color(hex: "#FF6B6B")!]
        } else if category.percentUsed >= 0.9 {
            return [Color(hex: "#C0392B")!, Color(hex: "#E67E22")!]
        } else if category.percentUsed >= 0.7 {
            return [Color(hex: "#E67E22")!, Color(hex: "#F0C040")!]
        } else {
            return [catColor, catColor.opacity(0.6)]
        }
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
                            colors: barColor,
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
    let bill: Expense

    private var daysUntil: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day],
            from: cal.startOfDay(for: Date()),
            to:   cal.startOfDay(for: bill.date)).day ?? 0
    }
    private var urgencyColor: Color {
        daysUntil < 0 ? Color(hex: "#C0392B")! : daysUntil <= 3 ? Color(hex: "#E67E22")! : Color.wAmber
    }
    private var urgencyLabel: String {
        daysUntil < 0  ? "Overdue \(abs(daysUntil))d"  :
        daysUntil == 0 ? "Due today"                    :
        daysUntil == 1 ? "Tomorrow"                     :
                         "In \(daysUntil)d"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(urgencyColor.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: bill.category.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(urgencyColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(bill.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.wBrown)
                HStack(spacing: 5) {
                    Text(urgencyLabel)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(urgencyColor)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(urgencyColor.opacity(0.1))
                        .cornerRadius(20)
                    Text(bill.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.wMuted)
                }
            }
            Spacer()
            Text(bill.formattedAmount)
                .font(.system(size: 15, weight: .black))
                .foregroundColor(Color.wBrown)
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
    let expense:   Expense
    var canDelete: Bool = true
    let onEdit:    () -> Void
    let onDelete:  () -> Void

    @State private var showDeleteAlert = false

    private var isPaid: Bool { expense.isPaid }

    var body: some View {
        HStack(spacing: 12) {
            // Category icon — dimmed when paid
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(isPaid
                          ? Color(hex: "#3D7A52")!.opacity(0.1)
                          : expense.category.displayColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: isPaid ? "checkmark.circle.fill" : expense.category.iconName)
                    .foregroundColor(isPaid ? Color(hex: "#3D7A52")! : expense.category.displayColor)
                    .font(.system(size: 14, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isPaid ? Color.wMuted : Color.wBrown)
                    .strikethrough(isPaid, color: Color.wMuted)

                HStack(spacing: 5) {
                    Text(expense.date.shortDisplayDate)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.wMuted)
                    if isPaid {
                        // Paid badge
                        Text("PAID")
                            .font(.system(size: 8, weight: .heavy)).kerning(0.8)
                            .foregroundColor(Color(hex: "#3D7A52")!)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(hex: "#3D7A52")!.opacity(0.1))
                            .cornerRadius(20)
                    }
                }
            }

            Spacer()

            Text(isPaid ? expense.formattedAmount : "-\(expense.formattedAmount)")
                .font(.system(size: 14, weight: .black))
                .foregroundColor(isPaid ? Color(hex: "#3D7A52")! : Color(hex: "#C0392B")!)
                .strikethrough(isPaid, color: Color.wMuted)

            Button { onEdit() } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.wAmber)
                    .frame(width: 26, height: 26)
                    .background(Color.wAmberSoft)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            if canDelete {
                Button { showDeleteAlert = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                        .frame(width: 26, height: 26)
                        .background(Color.red.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
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
                        .foregroundColor(vm.remainingBudget < 0 ? .red : Color.wGreen)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

// MARK: - BillRowView (kept for compatibility — no Pay button)
struct BillRowView: View {
    let bill:  Expense
    let onPay: () -> Void   // kept in signature so existing call sites compile
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.title).font(.subheadline).bold()
                Text("Due \(bill.date.relativeLabel)")
                    .font(.caption)
                    .foregroundColor(bill.isPaid ? .secondary : .orange)
            }
            Spacer()
            Text(bill.formattedAmount).font(.subheadline).bold()
            // Pay button intentionally removed
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    BudgetDashboardView()
}
