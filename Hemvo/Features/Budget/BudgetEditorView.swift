//  BudgetEditorView.swift
//  Hemvo
//  Redesigned: slate/navy palette, clear layout, visible Save button.

internal import SwiftUI
internal import Combine

// MARK: - BudgetEditorView
struct BudgetEditorView: View {
    @ObservedObject var vm: BudgetViewModel
    @Environment(\.dismiss) var dismiss

    @State private var incomeText: String = ""
    @State private var categoryLimits: [String: String] = [:]
    @State private var showSavedToast  = false
    @State private var shakeTrigger: CGFloat = 0
    @FocusState private var incomeFocused: Bool

    private let presets = [2000, 3000, 4000, 5000, 7500, 10000]

    // MARK: - Computed
    var income: Double          { Double(incomeText) ?? 0 }
    var totalAllocated: Double  {
        vm.monthCategories.reduce(0) { sum, cat in
            sum + (Double(categoryLimits[cat.name] ?? "") ?? cat.limit)
        }
    }
    var unallocated: Double     { income - totalAllocated }
    var isOverBudget: Bool      { unallocated < 0 }
    var allocationPct: Double   { income > 0 ? min(totalAllocated / income, 1.0) : 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bpBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // ── Income Hero ──────────────────────
                        incomeSection

                        // ── Allocation bar ───────────────────
                        if income > 0 { allocationBar }

                        // ── Category Limits ──────────────────
                        categorySection

                        // ── Save Button ──────────────────────
                        saveButton
                            .padding(.bottom, 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                // ── Toast ────────────────────────────────────
                if showSavedToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(hex: "#4A9E6B") ?? .clear)
                            Text("Budget saved!")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color.bpText)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(Color.bpSurface)
                        .cornerRadius(30)
                        .shadow(color: Color.bpText.opacity(0.12), radius: 16, y: 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 48)
                    }
                }
            }
            .navigationTitle("Edit Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
            .onAppear {
                prefill()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { incomeFocused = true }
            }
            .onChange(of: vm.budget.categories.count) { _, _ in
                for cat in vm.monthCategories where categoryLimits[cat.name] == nil {
                    categoryLimits[cat.name] = String(Int(cat.limit))
                }
            }
            .onTapGesture { incomeFocused = false }
        }
    }

    // MARK: - Income Section
    private var incomeSection: some View {
        VStack(spacing: 14) {
            // Label
            HStack(spacing: 5) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.bpSlate)
                Text("MONTHLY BUDGET")
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(1.4)
                    .foregroundColor(Color.bpTextSub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Large input
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(Color.bpNavy)
                TextField("0", text: $incomeText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 46, weight: .black))
                    .foregroundColor(Color.bpText)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .focused($incomeFocused)
                    .onChange(of: incomeText) { _, new in
                        let f = new.filter { $0.isNumber || $0 == "." }
                        if f != new { incomeText = f }
                    }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.bpSurface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        incomeFocused ? Color.bpNavy : Color.bpDivider,
                        lineWidth: incomeFocused ? 2 : 1
                    )
                    .animation(.easeInOut(duration: 0.15), value: incomeFocused)
            )
            .shadow(color: incomeFocused ? Color.bpNavy.opacity(0.1) : .clear, radius: 8, y: 3)
            .shake(trigger: shakeTrigger)

            // Preset chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { p in
                        let isSelected = Int(income) == p
                        Button { incomeText = "\(p)" } label: {
                            Text(p >= 1000 ? "$\(p / 1000)k" : "$\(p)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(isSelected ? .white : Color.bpNavy)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected ? Color.bpNavy : Color.bpNavyLight)
                                .cornerRadius(20)
                        }
                        .animation(.easeInOut(duration: 0.12), value: isSelected)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.bpSurface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.bpDivider, lineWidth: 1))
        .shadow(color: Color.bpText.opacity(0.04), radius: 8, y: 3)
    }

    // MARK: - Allocation Bar
    private var allocationBar: some View {
        VStack(spacing: 10) {
            // Stats row
            HStack(spacing: 8) {
                BudgetStatChip(
                    label: "Budget",
                    value: "$\(Int(income))",
                    color: Color.bpNavy
                )
                BudgetStatChip(
                    label: "Allocated",
                    value: "$\(Int(totalAllocated))",
                    color: Color.bpSlate
                )
                BudgetStatChip(
                    label: isOverBudget ? "Over by" : "Free",
                    value: "$\(Int(abs(unallocated)))",
                    color: isOverBudget ? .red : Color(hex: "#2E7D32") ?? .clear
                )
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.bpNavyLight)
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOverBudget ? Color.red : Color.bpNavy)
                        .frame(width: geo.size.width * allocationPct, height: 10)
                        .animation(.spring(response: 0.4), value: allocationPct)
                }
            }
            .frame(height: 10)

            if isOverBudget {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Text("Category limits exceed budget by $\(Int(abs(unallocated)))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.red.opacity(0.07))
                .cornerRadius(10)
            }
        }
        .padding(16)
        .background(Color.bpSurface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.bpDivider, lineWidth: 1))
    }

    // MARK: - Category Section
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.bpSlate)
                Text("CATEGORY LIMITS")
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(1.4)
                    .foregroundColor(Color.bpTextSub)
            }

            VStack(spacing: 1) {
                // Scoped to the selected month — categories used only in other
                // months keep their limits but don't clutter this month's editor.
                ForEach(Array(vm.monthCategories.enumerated()), id: \.element.id) { idx, cat in
                    let limitStr = Binding<String>(
                        get: { categoryLimits[cat.name] ?? String(Int(cat.limit)) },
                        set: { categoryLimits[cat.name] = $0 }
                    )
                    let limit    = Double(limitStr.wrappedValue) ?? cat.limit
                    let pct      = income > 0 ? min(limit / income, 1.0) : 0
                    let catColor = categoryColor(cat.name)

                    BudgetEditorCategoryRow(
                        cat:      cat,
                        limitStr: limitStr,
                        limit:    limit,
                        pct:      pct,
                        catColor: catColor,
                        iconName: categoryIcon(cat.name),
                        isInUse:  vm.isCategoryInUse(cat),
                        onDelete: { vm.deleteCategory(cat) }
                    )

                    if idx < vm.monthCategories.count - 1 {
                        Color.bpDivider.frame(height: 1).padding(.leading, 62)
                    }
                }
            }
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.bpDivider, lineWidth: 1))
            .shadow(color: Color.bpText.opacity(0.04), radius: 6, y: 2)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.bpDivider, lineWidth: 1))
            .shadow(color: Color.bpText.opacity(0.04), radius: 6, y: 2)
        }
    }

    // MARK: - Save Button
    private var saveButton: some View {
        Button { save() } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                Text("Save Budget")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(income > 0 ? Color.bpNavy : Color.bpDivider)
            .cornerRadius(16)
            .shadow(color: income > 0 ? Color.bpNavy.opacity(0.35) : .clear, radius: 10, y: 4)
            .animation(.easeInOut(duration: 0.15), value: income > 0)
        }
        .disabled(income <= 0)
    }

    // MARK: - Helpers
    private func categoryColor(_ name: String) -> Color {
        switch name {
        case "Groceries":      return Color(hex: "#2E7D32") ?? .clear
        case "Utilities":      return Color(hex: "#1565C0") ?? .clear
        case "Entertainment":  return Color(hex: "#E65100") ?? .clear
        case "Transportation": return Color(hex: "#4E342E") ?? .clear
        case "Healthcare":     return Color(hex: "#B71C1C") ?? .clear
        case "Dining Out":     return Color(hex: "#F57F17") ?? .clear
        case "Mortgage / Rent":return Color(hex: "#4A148C") ?? .clear
        case "Insurance":      return Color(hex: "#006064") ?? .clear
        case "Credit Card":    return Color(hex: "#1A237E") ?? .clear
        default:               return Color.bpSlate
        }
    }

    private func categoryIcon(_ name: String) -> String {
        switch name {
        case "Groceries":      return "cart.fill"
        case "Utilities":      return "bolt.fill"
        case "Entertainment":  return "tv.fill"
        case "Transportation": return "car.fill"
        case "Healthcare":     return "cross.case.fill"
        case "Dining Out":     return "fork.knife"
        case "Mortgage / Rent":return "house.fill"
        case "Insurance":      return "shield.fill"
        case "Credit Card":    return "creditcard.fill"
        default:               return "tag.fill"
        }
    }

    private func prefill() {
        incomeText = String(format: "%.0f", vm.budget.monthlyIncome)
        for cat in vm.monthCategories {
            categoryLimits[cat.name] = String(Int(cat.limit))
        }
    }

    private func save() {
        guard let inc = Double(incomeText), inc > 0 else {
            withAnimation { shakeTrigger += 1 }
            return
        }
        // Only the month's visible categories are saved — hidden ones keep their limits.
        var limits: [UUID: Double] = [:]
        for cat in vm.monthCategories {
            let s = categoryLimits[cat.name] ?? String(Int(cat.limit))
            if let lim = Double(s) {
                limits[cat.id] = lim
            }
        }
        vm.updateBudget(income: inc, categoryLimits: limits)
        withAnimation(.spring()) { showSavedToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation { showSavedToast = false }
            dismiss()
        }
    }
}

// MARK: - BudgetEditorCategoryRow
struct BudgetEditorCategoryRow: View {
    let cat:      BudgetCategory
    let limitStr: Binding<String>
    let limit:    Double
    let pct:      Double
    let catColor: Color
    let iconName: String
    /// Whether any expense or bill (any month) still uses this category —
    /// deletion is blocked while true, since sync would recreate the category.
    let isInUse:  Bool
    let onDelete: () -> Void

    @State private var showDeleteAlert = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(catColor.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(catColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(cat.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.bpText)
                    if cat.spent > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundColor(catColor)
                            Text("$\(Int(cat.spent)) spent")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(catColor)
                        }
                    } else {
                        Text("No spending yet")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.bpTextSub)
                    }
                }

                Spacer()

                // Limit input
                HStack(spacing: 3) {
                    Text("$")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.bpTextSub)
                    TextField("0", text: limitStr)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color.bpNavy)
                        .frame(width: 68)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.bpNavyLight)
                        .cornerRadius(8)
                }

                // Delete button — grayed while expenses/bills still use the category
                Button {
                    if isInUse {
                        showDeleteAlert = true
                    } else {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isInUse ? Color.bpTextSub.opacity(0.4) : .red)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isInUse ? Color.bpDivider : Color.red.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(catColor.opacity(0.12))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(catColor)
                        .frame(width: geo.size.width * pct, height: 5)
                        .animation(.spring(response: 0.3), value: pct)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.bpSurface)
        .alert("Cannot Delete", isPresented: $showDeleteAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\"\(cat.name)\" is still used by expenses or bills — including ones from other months. Delete those first.")
        }
    }
}

#Preview {
    BudgetEditorView(vm: BudgetViewModel())
}
