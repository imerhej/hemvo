//  BillHistoryView.swift
//  Hemvo
//  Shows all paid bills, filterable by week or month. Warm amber/cream palette.

internal import SwiftUI
internal import Combine

struct BillHistoryView: View {

    @ObservedObject var vm: BudgetViewModel
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var householdService: HouseholdService
    @Environment(\.dismiss) var dismiss

    private var canWrite: Bool {
        guard let uid = authVM.userID?.uuidString,
              let member = householdService.household?.members.first(where: { $0.id == uid })
        else { return true }
        return member.role.canWrite
    }

    enum Filter: String, CaseIterable {
        case week  = "This Week"
        case month = "This Month"
        case all   = "All Time"
    }

    @State private var filter: Filter
    @State private var selectedMonth: Date

    init(vm: BudgetViewModel, initialMonth: Date = Date()) {
        self.vm = vm
        _filter = State(initialValue: .month)
        _selectedMonth = State(initialValue: initialMonth)
    }
    @State private var billToEdit: Expense?  = nil
    @State private var billToDelete: Expense? = nil
    @State private var showDeleteAlert       = false
    @State private var selectedCategory: Expense.ExpenseCategory? = nil

    // MARK: - All one-time expenses + paid recurring bills (time filter only)
    // Non-recurring expenses are always included regardless of paid status so they remain
    // accessible here after being toggled from paid → unpaid (otherwise they fall off the
    // dashboard's 5-item recent list with no other path to reach them).
    private var timeFilteredBills: [Expense] {
        let all = vm.expenses.filter { $0.scope == vm.selectedScope && ($0.isPaid || !$0.isRecurring) }
        switch filter {
        case .week:
            let start = Calendar.current.date(from: Calendar.current.dateComponents(
                [.yearForWeekOfYear, .weekOfYear], from: Date()))!
            let end   = Calendar.current.date(byAdding: .day, value: 7, to: start)!
            return all.filter {
                let ref = $0.paidDate ?? $0.date
                return ref >= start && ref < end
            }.sorted { ($0.paidDate ?? $0.date) > ($1.paidDate ?? $1.date) }

        case .month:
            return all.filter {
                let ref = $0.paidDate ?? $0.date
                return Calendar.current.isDate(ref, equalTo: selectedMonth, toGranularity: .month)
            }.sorted { ($0.paidDate ?? $0.date) > ($1.paidDate ?? $1.date) }

        case .all:
            return all.sorted { ($0.paidDate ?? $0.date) > ($1.paidDate ?? $1.date) }
        }
    }

    // Categories present in the current time window (drives the category chips)
    private var availableCategories: [Expense.ExpenseCategory] {
        let cats = Set(timeFilteredBills.map { $0.category })
        return Expense.ExpenseCategory.allCases.filter { cats.contains($0) }
    }

    // Time-filtered bills further narrowed by selected category
    private var paidBills: [Expense] {
        guard let cat = selectedCategory else { return timeFilteredBills }
        return timeFilteredBills.filter { $0.category == cat }
    }

    private var totalPaid: Double { paidBills.reduce(0) { $0 + $1.amount } }

    // Group by month label for .all filter
    private var groupedByMonth: [(String, [Expense])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let groups = Dictionary(grouping: paidBills) { expense -> String in
            formatter.string(from: expense.paidDate ?? expense.date)
        }
        return groups.sorted { a, b in
            let df = DateFormatter(); df.dateFormat = "MMMM yyyy"
            return (df.date(from: a.key) ?? Date()) > (df.date(from: b.key) ?? Date())
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                (Color(hex: "#FAF7F2") ?? .clear).ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Custom header ─────────────────────────
                    historyHeader

                    // ── Filter chips ──────────────────────────
                    filterStrip.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)

                    // ── Month navigator (month filter only) ───
                    if filter == .month {
                        monthNavigator.padding(.horizontal, 20).padding(.bottom, 4)
                    }

                    // ── Category filter ───────────────────────────────
                    // Always show in personal scope; show in household only when 2+ categories exist
                    if vm.selectedScope == .personal ? !availableCategories.isEmpty : availableCategories.count > 1 {
                        categoryFilterStrip.padding(.top, 4).padding(.bottom, 4)
                    }

                    // ── Summary strip ─────────────────────────
                    if !paidBills.isEmpty {
                        summaryStrip.padding(.horizontal, 20).padding(.vertical, 10)
                    }

                    // ── Content ───────────────────────────────
                    if paidBills.isEmpty {
                        emptyState
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 16) {
                                if filter == .all {
                                    ForEach(groupedByMonth, id: \.0) { (month, bills) in
                                        monthGroup(month: month, bills: bills)
                                    }
                                } else {
                                    singleGroup(bills: paidBills)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .onChange(of: filter) { selectedCategory = nil }
            .sheet(item: $billToEdit, onDismiss: { vm.objectWillChange.send() }) { bill in
                EditExpenseView(vm: vm, expense: bill)
            }
            .alert("Delete Bill", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let b = billToDelete { vm.deleteExpense(b) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Remove \"\(billToDelete?.title ?? "this bill")\" from history? This cannot be undone.")
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header
    private var historyHeader: some View {
        ZStack {
            Color.white
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("EXPENSE HISTORY")
                        .font(.system(size: 10, weight: .heavy)).kerning(3)
                        .foregroundColor(Color(hex: "#C8922A") ?? .clear)
                    Text("History")
                        .font(.system(size: 26, weight: .black))
                        .foregroundColor(Color(hex: "#1A1208") ?? .clear)
                }
                Spacer()
                Button { dismiss() } label: {
                    Text("Done")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "#C8922A") ?? .clear)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color(hex: "#F5E4C3") ?? .clear)
                        .cornerRadius(20)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 52)
            .padding(.bottom, 14)
        }
        .frame(height: 120)
        .overlay(alignment: .bottom) {
            (Color(hex: "#E6DDD0") ?? .clear).frame(height: 1)
        }
    }

    // MARK: - Filter Strip
    private var filterStrip: some View {
        HStack(spacing: 8) {
            ForEach(Filter.allCases, id: \.self) { f in
                let isSelected = filter == f
                Button { withAnimation(.easeInOut(duration: 0.2)) { filter = f } } label: {
                    Text(f.rawValue)
                        .font(.system(size: 12, weight: isSelected ? .heavy : .medium))
                        .foregroundColor(isSelected ? .white : Color(hex: "#7A6A55") ?? .clear)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            Capsule().fill(isSelected ? Color(hex: "#C8922A") ?? .clear : Color(hex: "#F5E4C3") ?? .clear)
                        )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
            Spacer()
        }
    }

    // MARK: - Category Filter Strip
    private var categoryFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                let allSelected = selectedCategory == nil
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedCategory = nil }
                } label: {
                    Text("All")
                        .font(.system(size: 12, weight: allSelected ? .heavy : .medium))
                        .foregroundColor(allSelected ? .white : Color(hex: "#7A6A55") ?? .clear)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(allSelected ? Color(hex: "#C8922A") ?? .clear : Color(hex: "#F5E4C3") ?? .clear))
                }
                .buttonStyle(.plain)

                ForEach(availableCategories, id: \.self) { cat in
                    let isSelected = selectedCategory == cat
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = isSelected ? nil : cat
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: cat.iconName)
                                .font(.system(size: 10, weight: .bold))
                            Text(cat.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .heavy : .medium))
                        }
                        .foregroundColor(isSelected ? .white : cat.displayColor)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(isSelected ? cat.displayColor : cat.displayColor.opacity(0.12)))
                        .overlay(Capsule().stroke(cat.displayColor.opacity(isSelected ? 0 : 0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Month Navigator
    private var monthNavigator: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "#C8922A") ?? .clear)
                    .frame(width: 32, height: 32)
                    .background(Color(hex: "#F5E4C3") ?? .clear)
                    .clipShape(Circle())
            }
            Spacer()
            Text(selectedMonth.monthYearDisplay)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(hex: "#1A1208") ?? .clear)
            Spacer()
            Button {
                withAnimation {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "#C8922A") ?? .clear)
                    .frame(width: 32, height: 32)
                    .background(Color(hex: "#F5E4C3") ?? .clear)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Summary Strip
    private var summaryStrip: some View {
        HStack(spacing: 10) {
            summaryChip(
                icon:  "checkmark.circle.fill",
                label: "\(paidBills.count) bills paid",
                color: Color(hex: "#3D7A52") ?? .clear
            )
            summaryChip(
                icon:  "dollarsign.circle.fill",
                label: "$\(String(format: "%.2f", totalPaid)) total",
                color: Color(hex: "#C8922A") ?? .clear
            )
            Spacer()
        }
    }

    private func summaryChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundColor(color)
            Text(label).font(.system(size: 12, weight: .bold)).foregroundColor(Color(hex: "#1A1208") ?? .clear)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(color.opacity(0.1))
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(color.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Single Group (week / month view)
    @ViewBuilder
    private func singleGroup(bills: [Expense]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(bills.enumerated()), id: \.element.id) { idx, bill in
                HistoryBillRow(
                    bill:      bill,
                    canEdit:   canWrite,
                    canDelete: canWrite && vm.canDelete(bill),
                    onEdit:    { billToEdit   = bill },
                    onDelete:  { billToDelete = bill; showDeleteAlert = true }
                )
                if idx < bills.count - 1 {
                    (Color(hex: "#E6DDD0") ?? .clear).frame(height: 1).padding(.leading, 56)
                }
            }
        }
        .background(Color.white)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "#E6DDD0") ?? .clear, lineWidth: 1))
    }

    // MARK: - Month Group (all time view)
    @ViewBuilder
    private func monthGroup(month: String, bills: [Expense]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(hex: "#7A6A55") ?? .clear)
                Text(month.uppercased())
                    .font(.system(size: 10, weight: .heavy)).kerning(1.4)
                    .foregroundColor(Color(hex: "#7A6A55") ?? .clear)
                Spacer()
                Text("$\(String(format: "%.2f", bills.reduce(0) { $0 + $1.amount }))")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(Color(hex: "#C8922A") ?? .clear)
            }
            .padding(.leading, 2)

            singleGroup(bills: bills)
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(Color(hex: "#F5E4C3") ?? .clear).frame(width: 90, height: 90)
                Image(systemName: "clock.badge.checkmark.fill")
                    .font(.system(size: 36))
                    .foregroundColor(Color(hex: "#C8922A") ?? .clear)
            }
            VStack(spacing: 8) {
                Text("No Expenses")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1208") ?? .clear)
                Text("Your one-time expenses and paid bills will appear here.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "#7A6A55") ?? .clear)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - HistoryBillRow
struct HistoryBillRow: View {

    let bill:      Expense
    var canEdit:   Bool = true
    var canDelete: Bool = true
    let onEdit:    () -> Void
    let onDelete:  () -> Void

    private var createdByName: String? {
        guard let id = bill.createdBy,
              let member = HouseholdService.shared.household?.members
                  .first(where: { $0.id == id }) else { return nil }
        return member.username.components(separatedBy: " ").first ?? member.username
    }

    private var paidByLabel: String? { bill.formattedPaidDate }

    private var paidByFirstName: String? {
        guard let paidByID = bill.paidBy,
              let member = HouseholdService.shared.household?.members
                  .first(where: { $0.id == paidByID }) else { return nil }
        return member.username.components(separatedBy: " ").first ?? member.username
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Icon — green checkmark when paid, category icon when unpaid
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(bill.isPaid
                              ? (Color(hex: "#3D7A52") ?? .clear).opacity(0.1)
                              : bill.category.displayColor.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: bill.isPaid ? "checkmark.circle.fill" : bill.category.iconName)
                        .font(.system(size: bill.isPaid ? 18 : 14, weight: .semibold))
                        .foregroundColor(bill.isPaid ? Color(hex: "#3D7A52") ?? .clear : bill.category.displayColor)
                }

                // Title
                Text(bill.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(bill.isPaid ? Color(hex: "#7A6A55") ?? .clear : Color(hex: "#1A1208") ?? .clear)
                    .strikethrough(bill.isPaid, color: Color(hex: "#7A6A55") ?? .clear.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Amount + category label
                VStack(alignment: .trailing, spacing: 2) {
                    Text(bill.formattedAmount)
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(bill.isPaid ? Color(hex: "#7A6A55") ?? .clear : Color(hex: "#C0392B") ?? .clear)
                        .strikethrough(bill.isPaid, color: Color(hex: "#7A6A55") ?? .clear.opacity(0.4))
                    Text(bill.category.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "#7A6A55") ?? .clear)
                }

                // ── Action buttons ───────────────────────────────
                VStack(spacing: 6) {
                    if canEdit {
                        Button { onEdit() } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(hex: "#C8922A") ?? .clear)
                                .frame(width: 28, height: 28)
                                .background(Color(hex: "#F5E4C3") ?? .clear)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if canDelete {
                        Button { onDelete() } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.red)
                                .frame(width: 28, height: 28)
                                .background(Color.red.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // ── Pills row (paid date · people) ───────────
            HStack(spacing: 6) {
                if let label = paidByLabel {
                    Label(label, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "#3D7A52") ?? .clear)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background((Color(hex: "#3D7A52") ?? .clear).opacity(0.12))
                        .clipShape(Capsule())
                }
                if let name = paidByFirstName {
                    Label("paid by \(name)", systemImage: "person.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#3D7A52") ?? .clear)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background((Color(hex: "#3D7A52") ?? .clear).opacity(0.08))
                        .clipShape(Capsule())
                }
                if let name = createdByName {
                    Label("by \(name)", systemImage: "person.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#7A6A55") ?? .clear)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background((Color(hex: "#7A6A55") ?? .clear).opacity(0.08))
                        .clipShape(Capsule())
                }
                Spacer()
            }
            .padding(.leading, 50)
            .padding(.top, 6)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.white)
    }
}

#Preview {
    BillHistoryView(vm: BudgetViewModel())
}
