//  BillReminderView.swift
//  Hemvo
//  Redesigned bill reminders — navy/slate palette, all buttons visible.

internal import SwiftUI

// MARK: - BillReminderView
private enum BillSheet: Identifiable {
    case add
    case edit(Expense)
    var id: String {
        switch self {
        case .add:           return "add"
        case .edit(let e):   return e.id.uuidString
        }
    }
}

struct BillReminderView: View {
    @ObservedObject var vm: BudgetViewModel
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var authVM:           AuthViewModel
    @EnvironmentObject private var householdService: HouseholdService

    @State private var activeSheet:    BillSheet? = nil
    @State private var billToDelete:   Expense?   = nil
    @State private var showDeleteAlert = false
    /// The FAB floats over the cards, so it is tucked off-screen while the list is in motion and
    /// slides back once scrolling settles.
    @State private var isScrolling     = false

    private var canWrite: Bool {
        guard let uid = authVM.userID?.uuidString,
              let member = householdService.household?.members.first(where: { $0.id == uid })
        else { return true }
        return member.role.canWrite
    }

    /// Built here rather than inside the card so the card stays a plain value-driven view and the
    /// household lookup happens once per render instead of once per bill.
    private var people: BillPeopleResolver {
        BillPeopleResolver(
            members:      householdService.household?.members ?? [],
            selfID:       authVM.userID?.uuidString,
            selfName:     authVM.profile?.fullName ?? authVM.profile?.username,
            selfColorHex: authVM.profile?.avatarColor
        )
    }

    private var monthBills: [Expense] {
        vm.expenses.filter {
            $0.scope == vm.selectedScope &&
            $0.isBill &&
            Calendar.current.isDate($0.date, equalTo: vm.selectedMonth, toGranularity: .month)
        }
    }
    var totalDue: Double { monthBills.filter { !$0.isPaid }.reduce(0) { $0 + $1.amount } }
    var paidCount: Int   { monthBills.filter {  $0.isPaid }.count }
    var unpaidCount: Int { monthBills.filter { !$0.isPaid }.count }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.bpBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Header ──────────────────────────────
                    billHeader

                    let allBills = vm.expenses
                        .filter {
                            $0.scope == vm.selectedScope &&
                            $0.isBill &&
                            Calendar.current.isDate($0.date, equalTo: vm.selectedMonth, toGranularity: .month)
                        }
                        .sorted { $0.date < $1.date }

                    if allBills.isEmpty {
                        emptyState
                    } else {

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
                                            bill:      bill,
                                            people:    people,
                                            canDelete: vm.canDelete(bill),
                                            canEdit:   canWrite,
                                            onPay:     { vm.markBillPaid(bill) },
                                            onEdit:    { activeSheet  = .edit(bill) },
                                            onDelete:  { billToDelete = bill; showDeleteAlert = true }
                                        )
                                        .padding(.horizontal, 20)
                                    }
                                }

                                // ── Paid ─────────────────────
                                let paid = allBills.filter { $0.isPaid }
                                if !paid.isEmpty {
                                    sectionLabel("PAID · \(paid.count)", color: Color(hex: "#2E7D32") ?? .clear)
                                        .padding(.horizontal, 20)
                                    ForEach(paid) { bill in
                                        BillCard(
                                            bill:      bill,
                                            people:    people,
                                            canDelete: vm.canDelete(bill),
                                            canEdit:   canWrite,
                                            onPay:     { vm.markBillPaid(bill) },
                                            onEdit:    { activeSheet  = .edit(bill) },
                                            onDelete:  { billToDelete = bill; showDeleteAlert = true }
                                        )
                                        .padding(.horizontal, 20)
                                    }
                                }
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 110)
                        }
                        // .idle covers the finger lifting and the deceleration ending; .animating is
                        // a programmatic scroll, during which the button has nothing to get out of.
                        .onScrollPhaseChange { _, phase in
                            let moving = (phase != .idle && phase != .animating)
                            guard moving != isScrolling else { return }
                            withAnimation(.easeInOut(duration: 0.22)) { isScrolling = moving }
                        }
                    }
                }

                // ── Floating Add Bill button ─────────────────
                if canWrite {
                    addBillFAB
                        .padding(.bottom, 32)
                        .offset(y: isScrolling ? 140 : 0)
                        .opacity(isScrolling ? 0 : 1)
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .add:
                    AddExpenseView(vm: vm)
                case .edit(let bill):
                    EditExpenseView(vm: vm, expense: bill)
                }
            }
            .alert("Delete Bill", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let b = billToDelete { vm.deleteExpense(b) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                let name = billToDelete?.title ?? "this bill"
                if let bill = billToDelete, let rule = bill.recurrence, vm.deletingEndsSeries(bill) {
                    Text("Remove \"\(name)\" and stop it repeating \(rule.cadenceDescription)? Bills you've already paid stay in your history.")
                } else {
                    Text("Remove \"\(name)\"?")
                }
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
                    Text("\(monthBills.count) bill\(monthBills.count == 1 ? "" : "s")")
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
                    .foregroundColor(unpaidCount > 0 ? Color.bpNavy : Color(hex: "#2E7D32") ?? .clear)
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
                    .foregroundColor(Color(hex: "#2E7D32") ?? .clear)
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
        Button { activeSheet = .add } label: {
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
    let bill:      Expense
    var people:    BillPeopleResolver = BillPeopleResolver()
    var canDelete: Bool = true
    var canEdit:   Bool = true
    let onPay:     () -> Void
    let onEdit:    () -> Void
    let onDelete:  () -> Void

    @State private var showPayConfirm = false

    private let paidGreen = Color(hex: "#2E7D32") ?? .clear

    private var creator: BillPerson? { people.person(for: bill.createdBy) }
    private var payer:   BillPerson? { bill.isPaid ? people.person(for: bill.paidBy) : nil }

    var daysUntilDue: Int {
        let cal      = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let dueStart   = cal.startOfDay(for: bill.date)
        return cal.dateComponents([.day], from: todayStart, to: dueStart).day ?? 0
    }

    var urgencyColor: Color {
        if bill.isPaid       { return paidGreen }
        if daysUntilDue < 0  { return .red }
        if daysUntilDue <= 3 { return .orange }
        return Color.bpNavy
    }

    var urgencyLabel: String {
        if bill.isPaid       { return "Paid" }
        if daysUntilDue < 0  { return "Overdue by \(abs(daysUntilDue))d" }
        if daysUntilDue == 0 { return "Due today" }
        if daysUntilDue == 1 { return "Due tomorrow" }
        return "Due in \(daysUntilDue)d"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Info row ─────────────────────────────────
            HStack(alignment: .top, spacing: 13) {
                // Category icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(urgencyColor.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: bill.category.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(urgencyColor)
                }

                // Title + category
                VStack(alignment: .leading, spacing: 3) {
                    Text(bill.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(bill.isPaid ? Color.bpTextSub : Color.bpText)
                        .lineLimit(1)
                    Text(bill.category.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.bpTextSub)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Amount
                Text(bill.formattedAmount)
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(bill.isPaid ? Color.bpTextSub : Color.bpText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // ── Meta pills (status · due date · cadence) ─
            // FlowLayout, not an HStack: four capsules never fit one line on a narrow phone, and an
            // HStack answers that by compressing them until the text wraps mid-word inside the pill.
            FlowLayout(spacing: 6) {
                if bill.isPaid {
                    BillMetaPill(
                        icon:   "checkmark.circle.fill",
                        text:   bill.formattedPaidDate ?? "Paid",
                        tint:   paidGreen,
                        strong: true
                    )
                } else {
                    BillMetaPill(text: urgencyLabel, tint: urgencyColor, strong: true)
                    BillMetaPill(
                        icon: "calendar",
                        text: bill.date.formatted(date: .abbreviated, time: .omitted),
                        tint: Color.bpTextSub
                    )
                }
                if let rule = bill.recurrence {
                    BillMetaPill(
                        icon: "arrow.triangle.2.circlepath",
                        text: rule.repeatsLabel,
                        tint: Color.bpNavy
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // ── Byline ───────────────────────────────────
            BillByline(creator: creator, payer: payer)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            // ── Divider ──────────────────────────────────
            Color.bpDivider
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            // ── Action buttons ───────────────────────────
            HStack(spacing: 10) {
                // Mark as Paid — visible to everyone
                Button { showPayConfirm = true } label: {
                    actionLabel(
                        icon:  bill.isPaid ? "checkmark.circle.fill" : "checkmark.circle",
                        title: bill.isPaid ? "Paid" : "Mark Paid",
                        tint:  bill.isPaid ? paidGreen : .white,
                        fill:  bill.isPaid ? paidGreen.opacity(0.1) : paidGreen,
                        stroke: bill.isPaid ? paidGreen.opacity(0.3) : .clear
                    )
                }
                .disabled(bill.isPaid)

                // Edit — hidden for Teen role
                if canEdit {
                    Button { onEdit() } label: {
                        actionLabel(
                            icon:   "pencil",
                            title:  "Edit",
                            tint:   Color.bpNavy,
                            fill:   Color.bpNavyLight,
                            stroke: Color.bpNavy.opacity(0.2)
                        )
                    }
                }

                // Delete — creator only
                if canDelete {
                    Button { onDelete() } label: {
                        actionLabel(
                            icon:   "trash.fill",
                            title:  "Delete",
                            tint:   .red,
                            fill:   Color.red.opacity(0.08),
                            stroke: Color.red.opacity(0.2)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.bpSurface)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(urgencyColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.bpText.opacity(0.05), radius: 8, y: 3)
        .alert("Mark as Paid?", isPresented: $showPayConfirm) {
            Button("Mark Paid", role: .none) { onPay() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Confirm that \"\(bill.title)\" (\(bill.formattedAmount)) has been paid.")
        }
    }

    // MARK: - Action button label
    private func actionLabel(
        icon:   String,
        title:  String,
        tint:   Color,
        fill:   Color,
        stroke: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundColor(tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(fill)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(stroke, lineWidth: 1))
    }
}

#Preview {
    BillReminderView(vm: BudgetViewModel())
}
