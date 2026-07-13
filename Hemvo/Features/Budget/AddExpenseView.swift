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
    @State private var isBill      = false
    @State private var isPaid      = false
    @State private var notes       = ""
    @State private var scope:       BudgetScope = .household
    /// One-time by default: flipping "Bill" on says nothing about repeating, and a bill that
    /// quietly comes back every month because of a default is worse than one extra tap.
    @State private var recurrence:  RecurrenceRule? = nil
    @FocusState private var amountFocused: Bool

    private enum Field { case title, notes }
    @FocusState private var focus: Field?

    var amount: Double { Double(amountText) ?? 0 }

    /// Every expense must be one of the two things the app knows how to file: money you still
    /// owe (a bill) or money already spent (paid). Neither flag means neither bucket — that
    /// is the state that used to land unpaid bills in Recent Expenses.
    var isClassified: Bool { isBill || isPaid }
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && amount > 0 && isClassified
    }

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
                                icon: "calendar.badge.clock",
                                label: "Bill — pay later",
                                color: Color.bpSlate,
                                isOn: $isBill
                            )
                            Color.bpDivider.frame(height: 1).padding(.leading, 52)
                            OptionRow(
                                icon: "checkmark.circle.fill",
                                label: "Already Paid",
                                color: Color(hex: "#2E7D32") ?? .clear,
                                isOn: $isPaid
                            )
                        }
                        .background(Color.bpSurface)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.bpDivider, lineWidth: 1))

                        // A disabled Save button with no explanation is a dead end — say which
                        // switch is missing and why it matters.
                        if !isClassified {
                            HStack(spacing: 7) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 12))
                                Text("Pick one: a **bill** you still owe, or something **already paid**.")
                                    .font(.system(size: 12, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundColor(Color.bpTextSub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 2)
                        }

                        // ── Repeats ──────────────────────────
                        if isBill {
                            RecurrencePicker(selection: $recurrence)
                        }

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
                                isBill: isBill, notes: notes,
                                scope: scope,
                                recurrence: isBill ? recurrence : nil
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

// MARK: - RecurrencePicker
/// Frequency selector for a bill, shown only once "Recurring Bill" is on.
/// A `nil` selection is a bill that is due once and never repeats — the way every bill
/// behaved before series existed, kept as an explicit choice rather than a silent default.
struct RecurrencePicker: View {
    @Binding var selection: RecurrenceRule?

    private struct Choice: Identifiable {
        let rule: RecurrenceRule?
        var id:    String { rule?.rawValue    ?? "once" }
        var label: String { rule?.displayName ?? "One-time" }
    }

    private var choices: [Choice] {
        [Choice(rule: nil)] + RecurrenceRule.allCases.map { Choice(rule: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.bpSlate)
                Text("REPEATS")
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(1.4)
                    .foregroundColor(Color.bpTextSub)
            }

            HStack(spacing: 6) {
                ForEach(choices) { choice in
                    Button { selection = choice.rule } label: {
                        Text(choice.label)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundColor(selection == choice.rule ? .white : Color.bpNavy)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(selection == choice.rule ? Color.bpNavy : Color.bpSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.bpNavy.opacity(selection == choice.rule ? 0 : 0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: selection)
                }
            }

            Text(selection.map {
                "The next bill is created automatically \($0.cadenceDescription) once this one is paid. You're reminded the day before and the day it's due."
            } ?? "Reminded once, on the due date. This bill won't come back next month.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.bpTextSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    AddExpenseView(vm: BudgetViewModel())
}
