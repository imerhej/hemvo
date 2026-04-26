//  BillHistoryView.swift
//  Homvi
//  Shows all paid bills, filterable by week or month. Warm amber/cream palette.

internal import SwiftUI
internal import Combine

struct BillHistoryView: View {

    @ObservedObject var vm: BudgetViewModel
    @Environment(\.dismiss) var dismiss

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

    // MARK: - Filtered paid expenses (recurring AND one-time)
    private var paidBills: [Expense] {
        let all = vm.expenses.filter { $0.isPaid }
        switch filter {
        case .week:
            let start = Calendar.current.date(from: Calendar.current.dateComponents(
                [.yearForWeekOfYear, .weekOfYear], from: Date()))!
            let end   = Calendar.current.date(byAdding: .day, value: 7, to: start)!
            return all.filter {
                let paid = $0.paidDate ?? $0.date
                return paid >= start && paid < end
            }.sorted { ($0.paidDate ?? $0.date) > ($1.paidDate ?? $1.date) }

        case .month:
            return all.filter {
                let paid = $0.paidDate ?? $0.date
                return Calendar.current.isDate(paid, equalTo: selectedMonth, toGranularity: .month)
            }.sorted { ($0.paidDate ?? $0.date) > ($1.paidDate ?? $1.date) }

        case .all:
            return all.sorted { ($0.paidDate ?? $0.date) > ($1.paidDate ?? $1.date) }
        }
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
                Color(hex: "#FAF7F2")!.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Custom header ─────────────────────────
                    historyHeader

                    // ── Filter chips ──────────────────────────
                    filterStrip.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)

                    // ── Month navigator (month filter only) ───
                    if filter == .month {
                        monthNavigator.padding(.horizontal, 20).padding(.bottom, 4)
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
                                    ForEach(groupedByMonth, id: \.0) { month, bills in
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
                    Text("PAYMENT HISTORY")
                        .font(.system(size: 10, weight: .heavy)).kerning(3)
                        .foregroundColor(Color(hex: "#C8922A")!)
                    Text("Paid Bills")
                        .font(.system(size: 26, weight: .black))
                        .foregroundColor(Color(hex: "#1A1208")!)
                }
                Spacer()
                Button { dismiss() } label: {
                    Text("Done")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "#C8922A")!)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color(hex: "#F5E4C3")!)
                        .cornerRadius(20)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 52)
            .padding(.bottom, 14)
        }
        .frame(height: 120)
        .overlay(alignment: .bottom) {
            Color(hex: "#E6DDD0")!.frame(height: 1)
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
                        .foregroundColor(isSelected ? .white : Color(hex: "#7A6A55")!)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            Capsule().fill(isSelected ? Color(hex: "#C8922A")! : Color(hex: "#F5E4C3")!)
                        )
                        .shadow(color: isSelected ? Color(hex: "#C8922A")!.opacity(0.3) : .clear,
                                radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
            Spacer()
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
                    .foregroundColor(Color(hex: "#C8922A")!)
                    .frame(width: 32, height: 32)
                    .background(Color(hex: "#F5E4C3")!)
                    .clipShape(Circle())
            }
            Spacer()
            Text(selectedMonth.monthYearDisplay)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(hex: "#1A1208")!)
            Spacer()
            Button {
                withAnimation {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "#C8922A")!)
                    .frame(width: 32, height: 32)
                    .background(Color(hex: "#F5E4C3")!)
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
                color: Color(hex: "#3D7A52")!
            )
            summaryChip(
                icon:  "dollarsign.circle.fill",
                label: "$\(String(format: "%.2f", totalPaid)) total",
                color: Color(hex: "#C8922A")!
            )
            Spacer()
        }
    }

    private func summaryChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundColor(color)
            Text(label).font(.system(size: 12, weight: .bold)).foregroundColor(Color(hex: "#1A1208")!)
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
                    bill:     bill,
                    onEdit:   { billToEdit   = bill },
                    onDelete: { billToDelete = bill; showDeleteAlert = true }
                )
                if idx < bills.count - 1 {
                    Color(hex: "#E6DDD0")!.frame(height: 1).padding(.leading, 56)
                }
            }
        }
        .background(Color.white)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "#E6DDD0")!, lineWidth: 1))
        .shadow(color: Color(hex: "#1A1208")!.opacity(0.05), radius: 8, y: 3)
    }

    // MARK: - Month Group (all time view)
    @ViewBuilder
    private func monthGroup(month: String, bills: [Expense]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(hex: "#7A6A55")!)
                Text(month.uppercased())
                    .font(.system(size: 10, weight: .heavy)).kerning(1.4)
                    .foregroundColor(Color(hex: "#7A6A55")!)
                Spacer()
                Text("$\(String(format: "%.2f", bills.reduce(0) { $0 + $1.amount }))")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(Color(hex: "#C8922A")!)
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
                Circle().fill(Color(hex: "#F5E4C3")!).frame(width: 90, height: 90)
                Image(systemName: "clock.badge.checkmark.fill")
                    .font(.system(size: 36))
                    .foregroundColor(Color(hex: "#C8922A")!)
            }
            VStack(spacing: 8) {
                Text("No Paid Bills")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1208")!)
                Text("Bills you mark as paid will\nappear here for your records.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "#7A6A55")!)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - HistoryBillRow
struct HistoryBillRow: View {

    let bill:     Expense
    let onEdit:   () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Green checkmark icon
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(hex: "#3D7A52")!.opacity(0.1))
                    .frame(width: 38, height: 38)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(hex: "#3D7A52")!)
            }

            // Title + paid date + category
            VStack(alignment: .leading, spacing: 4) {
                Text(bill.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1208")!)
                    .strikethrough(true, color: Color(hex: "#7A6A55")!.opacity(0.5))

                HStack(spacing: 6) {
                    if let paidStr = bill.formattedPaidDate {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: "#3D7A52")!)
                            Text(paidStr)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(hex: "#3D7A52")!)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color(hex: "#3D7A52")!.opacity(0.1))
                        .cornerRadius(20)
                    }
                    Text(bill.category.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "#7A6A55")!)
                }
            }

            Spacer()

            // Amount + PAID badge
            VStack(alignment: .trailing, spacing: 4) {
                Text(bill.formattedAmount)
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(Color(hex: "#7A6A55")!)
                    .strikethrough(true, color: Color(hex: "#7A6A55")!.opacity(0.4))
                Text("PAID")
                    .font(.system(size: 8, weight: .heavy)).kerning(1)
                    .foregroundColor(Color(hex: "#3D7A52")!)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color(hex: "#3D7A52")!.opacity(0.1))
                    .cornerRadius(20)
            }

            // ── Action buttons ───────────────────────────────
            VStack(spacing: 6) {
                // Edit
                Button { onEdit() } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "#C8922A")!)
                        .frame(width: 28, height: 28)
                        .background(Color(hex: "#F5E4C3")!)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Delete
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
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.white)
    }
}

#Preview {
    BillHistoryView(vm: BudgetViewModel())
}
