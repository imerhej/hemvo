//  BillReminderView.swift
//  HomeBase
//  Redesigned bill reminders — navy/slate palette, all buttons visible.

internal import SwiftUI

// MARK: - BillReminderView
struct BillReminderView: View {
    @ObservedObject var vm: BudgetViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showAdd         = false
    @State private var billToDelete: Expense? = nil
    @State private var showDeleteAlert = false

    var totalDue: Double {
        vm.upcomingBills.filter { !$0.isPaid }.reduce(0) { $0 + $1.amount }
    }
    var paidCount: Int   { vm.upcomingBills.filter {  $0.isPaid }.count }
    var unpaidCount: Int { vm.upcomingBills.filter { !$0.isPaid }.count }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.bpBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Header ──────────────────────────────
                    billHeader

                    if vm.upcomingBills.isEmpty && vm.expenses.filter({ $0.isRecurring }).isEmpty {
                        emptyState
                    } else {
                        // Show ALL recurring bills — paid and unpaid
                        let allBills = vm.expenses
                            .filter { $0.isRecurring }
                            .sorted { $0.date < $1.date }

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 14) {
                                // ── Summary card ────────────
                                summaryCard
                                    .padding(.horizontal, 20)

                                // ── Unpaid ───────────────────
                                let unpaid = allBills.filter { !$0.isPaid }
                                if !unpaid.isEmpty {
                                    sectionLabel("UNPAID · \(unpaid.count)", color: Color.bpNavy)
                                        .padding(.horizontal, 20)
                                    ForEach(unpaid) { bill in
                                        BillCard(
                                            bill:     bill,
                                            onPay:    { vm.markBillPaid(bill) },
                                            onDelete: { billToDelete = bill; showDeleteAlert = true }
                                        )
                                        .padding(.horizontal, 20)
                                    }
                                }

                                // ── Paid ─────────────────────
                                let paid = allBills.filter { $0.isPaid }
                                if !paid.isEmpty {
                                    sectionLabel("PAID · \(paid.count)", color: Color(hex: "#2E7D32")!)
                                        .padding(.horizontal, 20)
                                    ForEach(paid) { bill in
                                        BillCard(
                                            bill:     bill,
                                            onPay:    { vm.markBillPaid(bill) },
                                            onDelete: { billToDelete = bill; showDeleteAlert = true }
                                        )
                                        .padding(.horizontal, 20)
                                    }
                                }
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 110)
                        }
                    }
                }

                // ── Floating Add Bill button ─────────────────
                addBillFAB
                    .padding(.bottom, 32)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showAdd) { AddExpenseView(vm: vm) }
            .alert("Delete Bill", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let b = billToDelete { vm.deleteExpense(b) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Remove \"\(billToDelete?.title ?? "this bill")\"?")
            }
        }
    }

    // MARK: - Header
    private var billHeader: some View {
        ZStack {
            Color.bpSurface
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BILL REMINDERS")
                        .font(.system(size: 10, weight: .heavy))
                        .kerning(3)
                        .foregroundColor(Color.bpNavy)
                    Text("\(vm.upcomingBills.count) bill\(vm.upcomingBills.count == 1 ? "" : "s")")
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(Color.bpText)
                }
                Spacer()
                Button { dismiss() } label: {
                    Text("Done")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.bpNavy)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.bpNavyLight)
                        .cornerRadius(20)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 52)
            .padding(.bottom, 14)
        }
        .frame(height: 120)
        .overlay(alignment: .bottom) {
            Color.bpDivider.frame(height: 1)
        }
    }

    // MARK: - Summary Card
    private var summaryCard: some View {
        HStack(spacing: 0) {
            // Total due
            VStack(spacing: 4) {
                Text("$\(String(format: "%.2f", totalDue))")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(unpaidCount > 0 ? Color.bpNavy : Color(hex: "#2E7D32")!)
                Text("TOTAL DUE")
                    .font(.system(size: 8, weight: .heavy))
                    .kerning(1.2)
                    .foregroundColor(Color.bpTextSub)
            }
            .frame(maxWidth: .infinity)

            Color.bpDivider.frame(width: 1, height: 36)

            // Unpaid
            VStack(spacing: 4) {
                Text("\(unpaidCount)")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(unpaidCount > 0 ? .red : Color.bpTextSub)
                Text("UNPAID")
                    .font(.system(size: 8, weight: .heavy))
                    .kerning(1.2)
                    .foregroundColor(Color.bpTextSub)
            }
            .frame(maxWidth: .infinity)

            Color.bpDivider.frame(width: 1, height: 36)

            // Paid
            VStack(spacing: 4) {
                Text("\(paidCount)")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(Color(hex: "#2E7D32")!)
                Text("PAID")
                    .font(.system(size: 8, weight: .heavy))
                    .kerning(1.2)
                    .foregroundColor(Color.bpTextSub)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 18)
        .background(Color.bpSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.bpDivider, lineWidth: 1))
        .shadow(color: Color.bpText.opacity(0.04), radius: 8, y: 3)
    }

    // MARK: - Section Label
    private func sectionLabel(_ text: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Rectangle()
                .fill(color)
                .frame(width: 3, height: 12)
                .cornerRadius(2)
            Text(text)
                .font(.system(size: 10, weight: .heavy))
                .kerning(1.5)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - FAB
    private var addBillFAB: some View {
        Button { showAdd = true } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 28, height: 28)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                }
                Text("Add Bill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color.bpNavy)
                    .shadow(color: Color.bpNavy.opacity(0.45), radius: 16, y: 6)
            )
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.bpNavyLight)
                    .frame(width: 90, height: 90)
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 36))
                    .foregroundColor(Color.bpNavy)
            }
            VStack(spacing: 6) {
                Text("No Bills Added")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.bpText)
                Text("Tap + to add recurring bills and\nget reminded before they're due.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.bpTextSub)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - BillCard
struct BillCard: View {
    let bill:     Expense
    let onPay:    () -> Void
    let onDelete: () -> Void

    var daysUntilDue: Int {
        let cal      = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let dueStart   = cal.startOfDay(for: bill.date)
        return cal.dateComponents([.day], from: todayStart, to: dueStart).day ?? 0
    }

    var urgencyColor: Color {
        if bill.isPaid        { return Color(hex: "#2E7D32")! }
        if daysUntilDue < 0  { return .red }
        if daysUntilDue <= 3 { return .orange }
        return Color.bpNavy
    }

    var urgencyLabel: String {
        if bill.isPaid        { return "Paid" }
        if daysUntilDue < 0  { return "Overdue by \(abs(daysUntilDue))d" }
        if daysUntilDue == 0 { return "Due today" }
        if daysUntilDue == 1 { return "Due tomorrow" }
        return "Due in \(daysUntilDue)d"
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Info row ─────────────────────────────────
            HStack(spacing: 14) {
                // Category icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(urgencyColor.opacity(0.1))
                        .frame(width: 46, height: 46)
                    Image(systemName: bill.category.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(urgencyColor)
                }

                // Title + status
                VStack(alignment: .leading, spacing: 4) {
                    // Strikethrough on title when paid
                    Text(bill.title)
                        .font(.system(size: 15, weight: .bold))
                        .strikethrough(bill.isPaid, color: Color.bpTextSub)
                        .foregroundColor(bill.isPaid ? Color.bpTextSub : Color.bpText)

                    if bill.isPaid, let paidStr = bill.formattedPaidDate {
                        // Show paid date instead of due status
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: "#2E7D32")!)
                            Text(paidStr)
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(Color(hex: "#2E7D32")!)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: "#2E7D32")!.opacity(0.1))
                                .cornerRadius(20)
                            Text("·")
                                .foregroundColor(Color.bpTextSub)
                            // Original due date (struck through)
                            Text(bill.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 11, weight: .medium))
                                .strikethrough(true, color: Color.bpTextSub)
                                .foregroundColor(Color.bpTextSub.opacity(0.6))
                        }
                    } else {
                        HStack(spacing: 5) {
                            Text(urgencyLabel)
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(urgencyColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(urgencyColor.opacity(0.1))
                                .cornerRadius(20)
                            Text("·")
                                .foregroundColor(Color.bpTextSub)
                            Text(bill.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.bpTextSub)
                        }
                    }
                }

                Spacer()

                // Amount
                VStack(alignment: .trailing, spacing: 2) {
                    Text(bill.formattedAmount)
                        .font(.system(size: 17, weight: .black))
                        .strikethrough(bill.isPaid, color: Color.bpTextSub)
                        .foregroundColor(bill.isPaid ? Color.bpTextSub : Color.bpText)
                    Text(bill.category.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color.bpTextSub)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // ── Divider ──────────────────────────────────
            Color.bpDivider.frame(height: 1).padding(.horizontal, 16)

            // ── Action buttons ───────────────────────────
            HStack(spacing: 10) {
                // Mark as Paid — always visible, grayed when already paid
                Button { onPay() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: bill.isPaid ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 13, weight: .bold))
                        Text(bill.isPaid ? "Paid" : "Mark Paid")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(bill.isPaid ? Color(hex: "#2E7D32")! : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        bill.isPaid
                            ? Color(hex: "#2E7D32")!.opacity(0.1)
                            : Color(hex: "#2E7D32")!
                    )
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                bill.isPaid ? Color(hex: "#2E7D32")!.opacity(0.3) : Color.clear,
                                lineWidth: 1
                            )
                    )
                }
                .disabled(bill.isPaid)

                // Edit — always visible
                // (Opens AddExpenseView pre-filled — wire via EditExpenseView in parent if needed)
                // Delete — always visible, outlined red
                Button { onDelete() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Delete")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.bpSurface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(urgencyColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.bpText.opacity(0.05), radius: 8, y: 3)
    }
}

#Preview {
    BillReminderView(vm: BudgetViewModel())
}
