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
