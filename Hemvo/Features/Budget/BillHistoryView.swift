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

    /// Resolved once per render and handed to every row, so each row doesn't re-scan the household.
    private var people: BillPeopleResolver {
        BillPeopleResolver(
            members:      householdService.household?.members ?? [],
            selfID:       authVM.userID?.uuidString,
            selfName:     authVM.profile?.fullName ?? authVM.profile?.username,
            selfColorHex: authVM.profile?.avatarColor
        )
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
        let all = vm.expenses.filter { $0.scope == vm.selectedScope && ($0.isPaid || !$0.isBill) }
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
                    HStack(spacing: 8) {
                        Text("EXPENSE HISTORY")
                            .font(.system(size: 10, weight: .heavy)).kerning(3)
                            .foregroundColor(Color(hex: "#C8922A") ?? .clear)
                        ScopeBadge(scope: vm.selectedScope, tint: Color(hex: "#C8922A") ?? .clear)
                    }
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
            // "expenses", not "bills paid": this list is one-time expenses *and* paid bills, so
            // calling the count bills made it contradict the bill counts on the reminders sheet.
            summaryChip(
                icon:  "checkmark.circle.fill",
                label: "\(paidBills.count) expense\(paidBills.count == 1 ? "" : "s")",
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
                    people:    people,
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
    var people:    BillPeopleResolver = BillPeopleResolver()
    var canEdit:   Bool = true
    var canDelete: Bool = true
    let onEdit:    () -> Void
    let onDelete:  () -> Void

    private let amber   = Color(hex: "#C8922A") ?? .clear
    private let cream   = Color(hex: "#F5E4C3") ?? .clear
    private let ink     = Color(hex: "#1A1208") ?? .clear
    private let subInk  = Color(hex: "#7A6A55") ?? .clear
    private let green   = Color(hex: "#3D7A52") ?? .clear
    private let unpaid  = Color(hex: "#C0392B") ?? .clear

    private var creator: BillPerson? { people.person(for: bill.createdBy) }
    private var payer:   BillPerson? { bill.isPaid ? people.person(for: bill.paidBy) : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // Icon — green checkmark when paid, category icon when unpaid
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(bill.isPaid ? green.opacity(0.1) : bill.category.displayColor.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: bill.isPaid ? "checkmark.circle.fill" : bill.category.iconName)
                        .font(.system(size: bill.isPaid ? 18 : 14, weight: .semibold))
                        .foregroundColor(bill.isPaid ? green : bill.category.displayColor)
                }

                // Title + category
                VStack(alignment: .leading, spacing: 3) {
                    Text(bill.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(bill.isPaid ? subInk : ink)
                        .lineLimit(1)
                    Text(bill.category.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(subInk)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Amount + actions
                VStack(alignment: .trailing, spacing: 8) {
                    Text(bill.formattedAmount)
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(bill.isPaid ? subInk : unpaid)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if canEdit || canDelete {
                        HStack(spacing: 6) {
                            if canEdit {
                                Button { onEdit() } label: {
                                    iconButton("pencil", tint: amber, fill: cream)
                                }
                                .buttonStyle(.plain)
                            }
                            if canDelete {
                                Button { onDelete() } label: {
                                    iconButton("trash", tint: .red, fill: Color.red.opacity(0.08))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // ── Meta pills + byline ──────────────────────
            // Wrapping layout: an HStack squeezed these until the cadence text broke mid-word.
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 6) {
                    if bill.isPaid {
                        BillMetaPill(
                            icon:   "checkmark.circle.fill",
                            text:   bill.formattedPaidDate ?? "Paid",
                            tint:   green,
                            strong: true
                        )
                    } else {
                        BillMetaPill(
                            icon: "calendar",
                            text: bill.date.formatted(date: .abbreviated, time: .omitted),
                            tint: subInk
                        )
                    }
                    if let rule = bill.recurrence {
                        BillMetaPill(
                            icon: "arrow.triangle.2.circlepath",
                            text: rule.repeatsLabel,
                            tint: amber
                        )
                    }
                }

                BillByline(
                    creator:    creator,
                    payer:      payer,
                    labelColor: subInk,
                    nameColor:  ink
                )
            }
            .padding(.leading, 50)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.white)
    }

    private func iconButton(_ icon: String, tint: Color, fill: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(tint)
            .frame(width: 28, height: 28)
            .background(fill)
            .clipShape(Circle())
    }
}

#Preview {
    BillHistoryView(vm: BudgetViewModel())
}
