//  AddExpenseView.swift
//  Hemvo
//  Add a new expense or recurring bill.

internal import SwiftUI

// MARK: - AddExpenseView
struct AddExpenseView: View {
    @ObservedObject var vm: BudgetViewModel
    @Environment(\.dismiss) var dismiss

    @State private var title       = ""
    @State private var amountText  = ""
    @State private var category    = Expense.ExpenseCategory.groceries
    @State private var date        = Date()
    @State private var isRecurring = false
    @State private var isPaid      = false
    @State private var notes       = ""
    @State private var scope:       BudgetScope = .household
    @FocusState private var amountFocused: Bool

    private enum Field { case title, notes }
    @FocusState private var focus: Field?

    var amount: Double { Double(amountText) ?? 0 }
    var isValid: Bool  { !title.trimmingCharacters(in: .whitespaces).isEmpty && amount > 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bpBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {

                        // ── Amount ───────────────────────────
                        AmountInputCard(amountText: $amountText, focused: $amountFocused)

                        // ── Title ────────────────────────────
                        FieldCard(label: "Title", icon: "tag.fill") {
                            TextField("e.g. Electric Bill", text: $title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.bpText)
                                .focused($focus, equals: .title)
                                .submitLabel(.next)
                                .onSubmit { focus = .notes }
                        }

                        // ── Category ─────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 5) {
                                Image(systemName: "square.grid.2x2.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Color.bpSlate)
                                Text("CATEGORY")
                                    .font(.system(size: 9, weight: .heavy))
                                    .kerning(1.4)
                                    .foregroundColor(Color.bpTextSub)
                            }
                            CategoryChipGrid(selected: $category)
                        }

                        // ── Date ─────────────────────────────
                        FieldCard(label: "Date", icon: "calendar") {
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // ── Options ──────────────────────────
                        VStack(spacing: 0) {
                            OptionRow(
                                icon: "repeat.circle.fill",
                                label: "Recurring Bill",
                                color: Color.bpSlate,
                                isOn: $isRecurring
                            )
                            Color.bpDivider.frame(height: 1).padding(.leading, 52)
                            OptionRow(
                                icon: "checkmark.circle.fill",
                                label: "Already Paid",
                                color: Color(hex: "#2E7D32")!,
                                isOn: $isPaid
                            )
                        }
                        .background(Color.bpSurface)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.bpDivider, lineWidth: 1))

                        // ── Scope ─────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 5) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Color.bpSlate)
                                Text("VISIBILITY")
                                    .font(.system(size: 9, weight: .heavy))
                                    .kerning(1.4)
                                    .foregroundColor(Color.bpTextSub)
                            }
                            HStack(spacing: 8) {
                                ForEach(BudgetScope.allCases, id: \.self) { s in
                                    Button { scope = s } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: s == .household ? "house.fill" : "person.fill")
                                                .font(.system(size: 11, weight: .bold))
                                            Text(s.displayName)
                                                .font(.system(size: 13, weight: .bold))
                                        }
                                        .foregroundColor(scope == s ? .white : Color.bpNavy)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(scope == s ? Color.bpNavy : Color.bpSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.bpNavy.opacity(scope == s ? 0 : 0.3), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .animation(.easeInOut(duration: 0.15), value: scope)
                                }
                            }
                        }

                        // ── Notes ────────────────────────────
                        FieldCard(label: "Notes", icon: "note.text") {
                            TextField("Optional notes…", text: $notes, axis: .vertical)
                                .lineLimit(3...5)
                                .font(.system(size: 14))
                                .foregroundColor(Color.bpText)
                                .focused($focus, equals: .notes)
                                .submitLabel(.done)
                                .onSubmit { focus = nil }
                        }

                        // ── Save Button ──────────────────────
                        Button {
                            guard isValid else { return }
                            vm.addExpense(Expense(
                                title: title.trimmingCharacters(in: .whitespaces),
                                amount: amount, category: category,
                                date: date, isPaid: isPaid,
                                paidDate: isPaid ? Date() : nil,
                                isRecurring: isRecurring, notes: notes,
                                scope: scope
                            ))
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                Text("Save Expense")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(isValid ? Color.bpNavy : Color.bpDivider)
                            .cornerRadius(16)
                            .shadow(color: isValid ? Color.bpNavy.opacity(0.35) : .clear, radius: 10, y: 4)
                            .animation(.easeInOut(duration: 0.15), value: isValid)
                        }
                        .disabled(!isValid)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .onAppear {
                scope = vm.selectedScope
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { amountFocused = true }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
        }
    }
}

#Preview {
    AddExpenseView(vm: BudgetViewModel())
}
