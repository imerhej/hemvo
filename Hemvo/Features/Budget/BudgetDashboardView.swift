//  BudgetDashboardView.swift
//  Hemvo
//  Redesigned with warm amber/cream palette. Paid bills live in BillHistoryView.

internal import SwiftUI
internal import Combine

// MARK: - Warm palette tokens
private extension Color {
    static let wBg       = Color(hex: "#FAF7F2") ?? .clear   // cream background
    static let wAmber    = Color(hex: "#C8922A") ?? .clear   // primary accent
    static let wAmberSoft = Color(hex: "#F5E4C3") ?? .clear  // amber tint
    static let wBrown    = Color(hex: "#1A1208") ?? .clear   // primary text
    static let wMuted    = Color(hex: "#7A6A55") ?? .clear   // secondary text
    static let wDivider  = Color(hex: "#E6DDD0") ?? .clear   // borders
    static let wSurface  = Color(hex: "#FFFFFF") ?? .clear   // card surface
    static let wGreen    = Color(hex: "#3D7A52") ?? .clear   // positive / remaining
}

// MARK: - BudgetDashboardView
struct BudgetDashboardView: View {

    @StateObject private var vm           = BudgetViewModel()
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var householdService: HouseholdService

    @State private var showAddExpense    = false
    @State private var showBillReminder  = false
    @State private var showBudgetEditor  = false
    @State private var showHistory       = false
    @State private var expenseToEdit: Expense? = nil

    private var canWrite: Bool {
        guard let uid = authVM.userID?.uuidString,
              let member = householdService.household?.members.first(where: { $0.id == uid })
        else { return true }
        return member.role.canWrite
    }

    private var isRestricted: Bool { !canWrite }

    var body: some View {
        Group {
            if isRestricted {
                restrictedView
            } else {
                NavigationStack {
                    ZStack(alignment: .bottomTrailing) {
                        Color.wBg.ignoresSafeArea()

                        VStack(spacing: 0) {
                            headerBar
                            scopePicker.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)

                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 0) {
                                    monthStrip.padding(.horizontal, 20).padding(.top, 14)

                                    if vm.selectedScope == .household {
                                        heroCard.padding(.horizontal, 20).padding(.top, 16)
                                        statsRow.padding(.horizontal, 20).padding(.top, 16)
                                        categorySection.padding(.horizontal, 20).padding(.top, 20)
                                    } else {
                                        personalSpendingCard.padding(.horizontal, 20).padding(.top, 16)
                                        personalStatsRow.padding(.horizontal, 20).padding(.top, 16)
                                    }

                                    billsSection.padding(.horizontal, 20).padding(.top, 20)
                                    recentSection.padding(.horizontal, 20).padding(.top, 20)
                                        .padding(.bottom, 100)
                                }
                                .frame(maxWidth: 680)
                                .frame(maxWidth: .infinity)
                            }
                        }

                        addFAB.padding(.trailing, 16).padding(.bottom, 10)
                    }
                    .navigationBarHidden(true)
                    .sheet(isPresented: $showAddExpense,   onDismiss: { vm.objectWillChange.send() }) { AddExpenseView(vm: vm) }
                    .sheet(isPresented: $showBillReminder) { BillReminderView(vm: vm) }
                    .sheet(isPresented: $showBudgetEditor, onDismiss: { vm.objectWillChange.send() }) { BudgetEditorView(vm: vm) }
                    .sheet(isPresented: $showHistory)      { BillHistoryView(vm: vm, initialMonth: vm.selectedMonth) }
                    .sheet(item: $expenseToEdit,           onDismiss: { vm.objectWillChange.send() }) { EditExpenseView(vm: vm, expense: $0) }
                }
            }
        }
        .task {
            await householdService.refreshMembers()
            guard !isRestricted else { return }
            await vm.loadFromSupabase()
        }
    }

    private var restrictedView: some View {
        ZStack {
            Color.wBg.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                ZStack {
                    Circle().fill(Color.wAmberSoft).frame(width: 100, height: 100)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Color.wAmber)
                }
                VStack(spacing: 8) {
                    Text("Budget Restricted")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color.wBrown)
                    Text("Budget information is only available to\nowners and adults in the household.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.wMuted)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(.horizontal, 32)
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

    // MARK: - Scope Picker
    private var scopePicker: some View {
        HStack(spacing: 0) {
            ForEach(BudgetScope.allCases, id: \.self) { scope in
                Button { vm.setScope(scope) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: scope == .household ? "house.fill" : "person.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(scope.displayName)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(vm.selectedScope == scope ? .white : Color.wAmber)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(vm.selectedScope == scope ? Color.wAmber : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.18), value: vm.selectedScope)
            }
        }
        .padding(4)
        .background(Color.wAmberSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.wAmber.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Personal Spending Card
    private var personalSpendingCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(
                    colors: [Color(hex: "#4A3728") ?? .clear, Color(hex: "#6B5240") ?? .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Circle().fill(Color.white.opacity(0.07)).frame(width: 180).offset(x: 110, y: -50)
            Circle().fill(Color.white.opacity(0.05)).frame(width: 110).offset(x: -60, y: 70)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personal Spending")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        Text("$\(Int(vm.totalSpent))")
                            .font(.system(size: 36, weight: .black))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.4))
                        Text("Your expenses only")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 11))
                        Text("\(vm.monthlyExpenses.filter { !$0.isRecurring || $0.isPaid }.count) transactions this month")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.85))
                    Spacer()
                }
            }
            .padding(22)
        }
    }

    // MARK: - Personal Stats Row
    private var personalStatsRow: some View {
        HStack(spacing: 10) {
            WarmStatTile(value: "$\(Int(vm.totalSpent))",
                         label: "Spent",
                         icon: "arrow.up.circle.fill",
                         iconColor: Color(hex: "#C0392B") ?? .clear)

            WarmStatTile(value: "\(vm.monthlyExpenses.filter { !$0.isRecurring || $0.isPaid }.count)",
                         label: "Transactions",
                         icon: "list.bullet.rectangle.fill",
                         iconColor: Color.wAmber)

            WarmStatTile(value: "\(vm.upcomingBills.count)",
                         label: "Bills Due",
                         icon: "calendar.badge.exclamationmark",
                         iconColor: Color(hex: "#E67E22") ?? .clear)
        }
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
        Button { if canWrite { showBudgetEditor = true } } label: {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(
                    colors: [Color(hex: "#C8922A") ?? .clear, Color(hex: "#E6A83A") ?? .clear],
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
                                             ? Color(hex: "#FF6B6B") ?? .clear : .white)
                    }
                    if canWrite {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.22)).frame(height: 10)
                            Capsule()
                                .fill(vm.spentPercent > 0.9
                                      ? LinearGradient(colors: [Color(hex: "#FF6B6B") ?? .clear, .orange],
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
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats Row
    private var statsRow: some View {
        HStack(spacing: 10) {
            WarmStatTile(value: "$\(Int(vm.totalSpent))",
                         label: "Spent",
                         icon: "arrow.up.circle.fill",
                         iconColor: Color(hex: "#C0392B") ?? .clear)

            WarmStatTile(value: "\(vm.monthlyExpenses.filter { !$0.isRecurring || $0.isPaid }.count)",
                         label: "Transactions",
                         icon: "list.bullet.rectangle.fill",
                         iconColor: Color.wAmber)

            WarmStatTile(value: "\(vm.upcomingBills.count)",
                         label: "Bills Due",
                         icon: "calendar.badge.exclamationmark",
                         iconColor: Color(hex: "#E67E22") ?? .clear)

            WarmStatTile(value: "\(vm.budgetCategories.filter { $0.isOverBudget }.count)",
                         label: "Over Limit",
                         icon: "exclamationmark.triangle.fill",
                         iconColor: Color(hex: "#C0392B") ?? .clear)
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
                            canWrite: canWrite,
                            isInUse:  vm.isCategoryInUse(cat),
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
                if canWrite {
                    Button { showBillReminder = true } label: {
                        Text("Manage")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color.wAmber)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.wAmberSoft)
                            .cornerRadius(20)
                    }
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
            let recent = vm.monthlyExpenses
                .filter { !$0.isRecurring || $0.isPaid }
                .sorted { $0.date > $1.date }
            if recent.isEmpty {
                WarmEmptyState(icon: "tray.fill", message: "No expenses this month.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.prefix(3).enumerated()), id: \.element.id) { idx, expense in
                        ExpenseRow(
                            expense:   expense,
                            canEdit:   canWrite,
                            canDelete: canWrite && vm.canDelete(expense),
                            onEdit:    { expenseToEdit = expense },
                            onDelete:  { vm.deleteExpense(expense) }
                        )
                        if idx < min(recent.count, 3) - 1 {
                            Color.wDivider.frame(height: 1).padding(.leading, 50)
                        }
                    }
                }
                if recent.count > 3 {
                    Button { showHistory = true } label: {
                        Text("View all \(recent.count) expenses")
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
            .background(Capsule().fill(Color.wAmber))
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
    }
}

// MARK: - WarmCategoryRow
struct WarmCategoryRow: View {
    let category:  BudgetCategory
    var canWrite:  Bool = true
    /// Whether any expense or bill (any month) still uses this category —
    /// deletion is blocked while true, since sync would recreate the category.
    var isInUse:   Bool = true
    let onEdit:    () -> Void
    let onDelete:  () -> Void

    @State private var showDeleteAlert = false

    private var catColor: Color {
        switch category.name {
        case "Groceries":       return Color(hex: "#3D7A52") ?? .clear
        case "Utilities":       return Color(hex: "#1565C0") ?? .clear
        case "Entertainment":   return Color(hex: "#E67E22") ?? .clear
        case "Transportation":  return Color(hex: "#4E342E") ?? .clear
        case "Healthcare":      return Color(hex: "#C0392B") ?? .clear
        case "Dining Out":      return Color(hex: "#FF9800") ?? .clear
        case "Mortgage / Rent": return Color(hex: "#6A1B9A") ?? .clear
        case "Insurance":       return Color(hex: "#00838F") ?? .clear
        case "Credit Card":     return Color(hex: "#1A237E") ?? .clear
        default:                return Color(hex: "#7A6A55") ?? .clear
        }
    }

    private var barColor: [Color] {
        if category.isOverBudget {
            return [Color(hex: "#C0392B") ?? .clear, Color(hex: "#FF6B6B") ?? .clear]
        } else if category.percentUsed >= 0.9 {
            return [Color(hex: "#C0392B") ?? .clear, Color(hex: "#E67E22") ?? .clear]
        } else if category.percentUsed >= 0.7 {
            return [Color(hex: "#E67E22") ?? .clear, Color(hex: "#F0C040") ?? .clear]
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
                                .foregroundColor(category.isOverBudget ? Color(hex: "#C0392B") ?? .clear : Color.wMuted)
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
                        .foregroundColor(category.isOverBudget ? Color(hex: "#C0392B") ?? .clear : Color.wBrown)
                    Text("limit").font(.system(size: 9, weight: .medium)).foregroundColor(Color.wMuted)
                }

                if canWrite {
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
                        isInUse ? (showDeleteAlert = true) : onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isInUse ? Color.wMuted.opacity(0.4) : .red)
                            .frame(width: 28, height: 28)
                            .background(isInUse ? Color.wDivider : Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
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
            Text("\"\(category.name)\" is still used by expenses or bills — including ones from other months. Delete those first.")
        }
    }
}

// MARK: - WarmBillRow
struct WarmBillRow: View {
    let bill: Expense

    private var createdByName: String? {
        guard let id = bill.createdBy,
              let member = HouseholdService.shared.household?.members
                  .first(where: { $0.id == id }) else { return nil }
        return member.username.components(separatedBy: " ").first ?? member.username
    }

    private var daysUntil: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day],
            from: cal.startOfDay(for: Date()),
            to:   cal.startOfDay(for: bill.date)).day ?? 0
    }
    private var urgencyColor: Color {
        daysUntil < 0 ? Color(hex: "#C0392B") ?? .clear : daysUntil <= 3 ? Color(hex: "#E67E22") ?? .clear : Color.wAmber
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
                    if let name = createdByName {
                        HStack(spacing: 3) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 9))
                            Text("by \(name)")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(Color.wMuted)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.wMuted.opacity(0.1))
                        .cornerRadius(20)
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
    var canEdit:   Bool = true
    var canDelete: Bool = true
    let onEdit:    () -> Void
    let onDelete:  () -> Void

    @State private var showDeleteAlert = false

    private var isPaid: Bool { expense.isPaid }

    private var createdByName: String? {
        guard let id = expense.createdBy,
              let member = HouseholdService.shared.household?.members
                  .first(where: { $0.id == id }) else { return nil }
        return member.username.components(separatedBy: " ").first ?? member.username
    }

    private var paidByFirstName: String? {
        guard let paidByID = expense.paidBy,
              let member = HouseholdService.shared.household?.members
                  .first(where: { $0.id == paidByID }) else { return nil }
        return member.username.components(separatedBy: " ").first ?? member.username
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Category icon — dimmed when paid
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isPaid
                              ? (Color(hex: "#3D7A52") ?? .clear).opacity(0.1)
                              : expense.category.displayColor.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: isPaid ? "checkmark.circle.fill" : expense.category.iconName)
                        .foregroundColor(isPaid ? Color(hex: "#3D7A52") ?? .clear : expense.category.displayColor)
                        .font(.system(size: 14, weight: .semibold))
                }

                Text(expense.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isPaid ? Color.wMuted : Color.wBrown)
                    .strikethrough(isPaid, color: Color.wMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Amount + category label
                VStack(alignment: .trailing, spacing: 2) {
                    Text(expense.formattedAmount)
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(isPaid ? Color(hex: "#3D7A52") ?? .clear : Color(hex: "#C0392B") ?? .clear)
                        .strikethrough(isPaid, color: Color.wMuted)
                    Text(expense.category.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.wMuted)
                }

                if canEdit {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.wAmber)
                            .frame(width: 26, height: 26)
                            .background(Color.wAmberSoft)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

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

            // ── Pills row (date · paid status · people) ──
            HStack(spacing: 6) {
                if isPaid {
                    if let label = expense.formattedPaidDate {
                        Label(label, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "#2E7D32") ?? .clear)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background((Color(hex: "#2E7D32") ?? .clear).opacity(0.12))
                            .clipShape(Capsule())
                    }
                    if let name = paidByFirstName {
                        Label("paid by \(name)", systemImage: "person.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#2E7D32") ?? .clear)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background((Color(hex: "#2E7D32") ?? .clear).opacity(0.08))
                            .clipShape(Capsule())
                    }
                } else {
                    Text(expense.date.shortDisplayDate)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.wMuted)
                }
                if let name = createdByName {
                    Label("by \(name)", systemImage: "person.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.wMuted)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.wMuted.opacity(0.08))
                        .clipShape(Capsule())
                }
                Spacer()
            }
            .padding(.leading, 50)
            .padding(.top, 6)
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
        .environmentObject(AuthViewModel())
        .environmentObject(HouseholdService.shared)
}
