//  BudgetSharedComponents.swift
//  Hemvo
//  Shared palette, components used by AddExpenseView, EditExpenseView,
//  BillReminderView, and BudgetEditorView.

internal import SwiftUI

// MARK: - Budget Screen Palette
extension Color {
    static let bpBackground = Color(hex: "#F4F6FB") ?? .clear
    static let bpSurface    = Color(hex: "#FFFFFF") ?? .clear
    static let bpNavy       = Color(hex: "#1A237E") ?? .clear
    static let bpNavyLight  = Color(hex: "#E8EAF6") ?? .clear
    static let bpSlate      = Color(hex: "#3949AB") ?? .clear
    static let bpText       = Color(hex: "#0D1133") ?? .clear
    static let bpTextSub    = Color(hex: "#5C6380") ?? .clear
    static let bpDivider    = Color(hex: "#DDE1EE") ?? .clear
}

// MARK: - ScopeBadge
/// "HOUSEHOLD" / "PERSONAL" tag for the sheets opened from the budget dashboard.
///
/// Those sheets inherit `vm.selectedScope` silently and show nothing to say so, which makes a
/// personal-only list look like it's the whole household's money — or like the two have been
/// mixed together, since a household total and a personal total never agree.
struct ScopeBadge: View {
    let scope: BudgetScope
    var tint:  Color = Color.bpNavy

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: scope == .household ? "house.fill" : "person.fill")
                .font(.system(size: 8, weight: .bold))
            Text(scope.displayName.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .kerning(0.8)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}

// MARK: - MoneyText
/// A currency total with the cents set smaller than the dollars — "$4,253.<small>50</small>".
///
/// The summary numbers used to render as `Int(total)`, which *truncates* rather than rounds: a
/// $64.25 total read as "$64", and a -$0.50 remaining balance read as "$0" with no minus sign.
/// Every list the summaries sit above (rows, History) has always shown exact amounts, so the two
/// quietly disagreed. Shrinking the cents keeps the hero number scannable while it stays exact.
///
/// The whole amount is formatted once and the string split, never formatted as two numbers:
/// rounding the dollars and cents separately turns $9.999 into "$9" + ".00".
struct MoneyText: View {
    let amount:     Double
    var size:       CGFloat
    var weight:     Font.Weight = .black
    /// Cents size as a fraction of `size` — small enough to recede, large enough to still read.
    var centsScale: CGFloat = 0.58
    var color:      Color = Color.bpText

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle            = .decimal
        f.usesGroupingSeparator  = true
        f.minimumFractionDigits  = 2
        f.maximumFractionDigits  = 2
        return f
    }()

    /// Negative only once rounded — a -$0.001 rounding crumb must not render as "-$0.00".
    private var isNegative: Bool { (amount * 100).rounded() < 0 }

    private var parts: (dollars: String, cents: String) {
        let magnitude = abs(amount)
        let text = Self.formatter.string(from: NSNumber(value: magnitude))
                   ?? String(format: "%.2f", magnitude)
        let separator = Self.formatter.decimalSeparator ?? "."
        guard let range = text.range(of: separator, options: .backwards) else { return (text, "") }
        return (String(text[..<range.lowerBound]), String(text[range.lowerBound...]))
    }

    var body: some View {
        let (dollars, cents) = parts
        let sign = isNegative ? "-$" : "$"

        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(sign + dollars)
                .font(.system(size: size, weight: weight))
            if !cents.isEmpty {
                Text(cents)
                    .font(.system(size: max(size * centsScale, 9), weight: weight))
            }
        }
        .foregroundColor(color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - BillPerson
/// A household member as a bill card shows them: first name + avatar colour.
struct BillPerson: Equatable {
    let name:  String
    let color: Color

    var initial: String { String(name.prefix(1)).uppercased() }
}

// MARK: - BillPeopleResolver
/// Turns the user IDs stored on an `Expense` (`createdBy`, `paidBy`) into names.
///
/// Built once by the screen that owns the environment objects and passed down, so the cards stay
/// plain value-driven views. The `self*` fields are the fallback: a personal-scope expense — or any
/// expense made before the user joined a household — has a creator who is not in `members`, and
/// those still deserve a byline.
struct BillPeopleResolver {
    var members:      [HouseholdMembership] = []
    var selfID:       String? = nil
    var selfName:     String? = nil
    var selfColorHex: String? = nil

    func person(for userID: String?) -> BillPerson? {
        guard let userID, !userID.isEmpty else { return nil }

        if let member = members.first(where: { $0.id.caseInsensitiveCompare(userID) == .orderedSame }) {
            return BillPerson(
                name:  Self.firstName(member.username),
                color: Color(hex: member.avatarHex) ?? Color.bpSlate
            )
        }

        if let selfID, selfID.caseInsensitiveCompare(userID) == .orderedSame, let selfName {
            return BillPerson(
                name:  Self.firstName(selfName),
                color: Color(hex: selfColorHex ?? "") ?? Color.bpSlate
            )
        }

        return nil
    }

    private static func firstName(_ full: String) -> String {
        let first = full.components(separatedBy: " ").first ?? ""
        return first.isEmpty ? full : first
    }
}

// MARK: - BillMetaPill
/// One metadata capsule on a bill card (due date, cadence, paid date).
///
/// Single-line and intrinsically sized on purpose: these used to sit in an `HStack` that squeezed
/// them past their ideal width, which broke "Weekly" across two lines inside the capsule.
struct BillMetaPill: View {
    var icon:   String? = nil
    let text:   String
    let tint:   Color
    var strong: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: strong ? .heavy : .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.11)))
        .overlay(Capsule().stroke(tint.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - BillByline
/// "Created by Issam · Paid by Sam" footer, with each person's avatar colour as a dot.
struct BillByline: View {
    var creator:    BillPerson? = nil
    var payer:      BillPerson? = nil
    var labelColor: Color = Color.bpTextSub
    var nameColor:  Color = Color.bpText

    var body: some View {
        if creator != nil || payer != nil {
            HStack(spacing: 8) {
                if let creator {
                    person(creator, verb: "Created by")
                }
                if let payer {
                    if creator != nil {
                        Circle()
                            .fill(labelColor.opacity(0.35))
                            .frame(width: 3, height: 3)
                    }
                    person(payer, verb: "Paid by")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func person(_ p: BillPerson, verb: String) -> some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(p.color)
                    .frame(width: 16, height: 16)
                Text(p.initial)
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.white)
            }
            (
                Text("\(verb) ")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(labelColor)
                + Text(p.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(nameColor)
            )
            .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - FieldCard
/// Labelled container used in expense forms
struct FieldCard<Content: View>: View {
    let label: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.bpSlate)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(1.4)
                    .foregroundColor(Color.bpTextSub)
            }
            content()
                .padding(14)
                .background(Color.bpSurface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.bpDivider, lineWidth: 1)
                )
        }
    }
}

// MARK: - ExpenseDateField
/// Date field for the expense forms.
///
/// It deliberately does **not** use an inline `.compact`/`.wheel` DatePicker. That style opens
/// its calendar in a popover, and when the amount keyboard is still up the popover makes UIKit
/// rebuild the keyboard's input views mid-presentation — which walks the responder chain back
/// into SwiftUI and deadlocks against the async renderer (frozen app, no crash log). Guarding the
/// old popover by clearing focus on tap only narrowed the window; a user tapping mid-animation
/// still hit it.
///
/// Instead this is a plain button that resigns the keyboard first, then presents a `.graphical`
/// picker in its own sheet — the same deadlock-proof pattern the Maintenance "Next Due Date"
/// field uses. A modal sheet is a clean presentation that never rebuilds the keyboard in place.
struct ExpenseDateField: View {
    @Binding var date: Date
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.bpSlate)
                Text("DATE")
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(1.4)
                    .foregroundColor(Color.bpTextSub)
            }

            Button {
                // Give up first responder before the sheet animates up, so it never presents
                // over a live keyboard — the exact condition behind the deadlock.
                hideKeyboard()
                showPicker = true
            } label: {
                HStack {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.bpText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.bpTextSub.opacity(0.5))
                }
                .padding(14)
                .background(Color.bpSurface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.bpDivider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Color.bpNavy)
                    .labelsHidden()
                    .padding(.horizontal)
                    .navigationTitle("Select Date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showPicker = false }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color.bpNavy)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - CategoryChipGrid
struct CategoryChipGrid: View {
    @Binding var selected: Expense.ExpenseCategory

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Expense.ExpenseCategory.allCases) { cat in
                let isSelected = selected == cat
                Button { selected = cat } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? cat.displayColor : cat.displayColor.opacity(0.1))
                                .frame(width: 36, height: 36)
                            Image(systemName: cat.iconName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isSelected ? .white : cat.displayColor)
                        }
                        Text(cat.rawValue)
                            .font(.system(size: 9, weight: isSelected ? .heavy : .medium))
                            .foregroundColor(isSelected ? Color.bpNavy : Color.bpTextSub)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? Color.bpNavyLight : Color.bpSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        isSelected ? Color.bpNavy.opacity(0.4) : Color.bpDivider,
                                        lineWidth: isSelected ? 1.5 : 1
                                    )
                            )
                    )
                    .shadow(color: isSelected ? Color.bpNavy.opacity(0.12) : .clear, radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
        }
    }
}

// MARK: - AmountInputCard
struct AmountInputCard: View {
    @Binding var amountText: String
    @FocusState.Binding var focused: Bool
    var accentColor: Color = Color.bpNavy

    var body: some View {
        VStack(spacing: 4) {
            Text("AMOUNT")
                .font(.system(size: 9, weight: .heavy))
                .kerning(1.4)
                .foregroundColor(Color.bpTextSub)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(accentColor)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 44, weight: .black))
                    .foregroundColor(Color.bpText)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .focused($focused)
                    .onChange(of: amountText) { _, new in
                        let filtered = new.filter { $0.isNumber || $0 == "." }
                        if filtered != new { amountText = filtered }
                    }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.bpSurface)
            .cornerRadius(16)
            // The border must not animate on `focused`. Losing focus is what dismisses the
            // keyboard, and an implicit animation running at that moment puts SwiftUI's async
            // renderer inside CoreAnimation while the main thread is walking the responder
            // chain back into the view graph to rebuild the keyboard's input views — the two
            // take those locks in opposite orders and the app deadlocks. Snapping the border
            // keeps the renderer off that thread when focus changes.
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(focused ? accentColor : Color.bpDivider, lineWidth: focused ? 2 : 1)
            )
            .shadow(color: focused ? accentColor.opacity(0.12) : .clear, radius: 8, y: 3)
        }
    }
}

// MARK: - OptionRow
struct OptionRow: View {
    let icon:  String
    let label: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.bpText)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

// MARK: - BudgetStatChip
struct BudgetStatChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .black))
                .foregroundColor(color)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .kerning(0.8)
                .foregroundColor(Color.bpTextSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }
}

// MARK: - SummaryPill (kept for BudgetDashboard compatibility)
struct SummaryPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline).bold().foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }
}
