//  MealHistoryView.swift
//  Hemvo
//  Browsable log of past meals, grouped by month, with multi-select delete.

internal import SwiftUI

struct MealHistoryView: View {
    @ObservedObject var mealVM: MealPlanViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMeal: Meal? = nil
    @State private var isEditing = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showDeleteConfirm = false

    private let cream   = Color(hex: "#F5F0E8") ?? .clear
    private let amber   = Color(hex: "#C8922A") ?? .clear
    private let brown   = Color(hex: "#1A1208") ?? .clear
    private let muted   = Color(hex: "#7A6A55") ?? .clear
    private let divider = Color(hex: "#E6DDD0") ?? .clear

    // Group past meals by month (most recent month first)
    private var groupedByMonth: [(key: String, meals: [Meal])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"

        let dict = Dictionary(grouping: mealVM.pastMeals) { meal -> String in
            fmt.string(from: meal.date)
        }

        return dict
            .map { (key: $0.key, meals: $0.value.sorted { $0.date > $1.date }) }
            .sorted { group1, group2 in
                (group1.meals.first?.date ?? .distantPast) > (group2.meals.first?.date ?? .distantPast)
            }
    }

    private var allIDs: Set<UUID> {
        Set(mealVM.pastMeals.map(\.id))
    }

    private var allSelected: Bool {
        !allIDs.isEmpty && selectedIDs == allIDs
    }

    var body: some View {
        ZStack(alignment: .top) {
            cream.ignoresSafeArea()

            VStack(spacing: 0) {
                navBar

                if mealVM.pastMeals.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 20, pinnedViews: .sectionHeaders) {
                            ForEach(groupedByMonth, id: \.key) { group in
                                Section {
                                    monthCard(group.meals)
                                } header: {
                                    monthHeader(group.key)
                                }
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, isEditing ? 100 : 40)
                    }

                    if isEditing {
                        deleteBar
                    }
                }
            }
        }
        .sheet(item: $selectedMeal) { meal in
            MealDetailView(mealID: meal.id, mealVM: mealVM)
        }
        .confirmationDialog(
            "Delete \(selectedIDs.count) meal\(selectedIDs.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func monthCard(_ meals: [Meal]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(meals.enumerated()), id: \.element.id) { idx, meal in
                if isEditing {
                    Button { toggleSelection(meal.id) } label: {
                        historyRow(meal)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { selectedMeal = meal } label: {
                        historyRow(meal)
                    }
                    .buttonStyle(.plain)
                }

                if idx < meals.count - 1 {
                    divider.frame(height: 1).padding(.leading, isEditing ? 68 : 60)
                }
            }
        }
        .background(Color.white)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(divider, lineWidth: 1))
        .shadow(color: brown.opacity(0.04), radius: 6, y: 2)
        .padding(.horizontal, 20)
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MEAL HISTORY")
                    .font(.system(size: 11, weight: .heavy)).kerning(2.5)
                    .foregroundColor(amber)
                Text("\(mealVM.pastMeals.count) past meal\(mealVM.pastMeals.count == 1 ? "" : "s")")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(brown)
            }
            Spacer()

            if isEditing {
                Button {
                    if allSelected {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = allIDs
                    }
                } label: {
                    Text(allSelected ? "Deselect All" : "Select All")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(amber)
                }
                .padding(.trailing, 8)

                Button {
                    isEditing = false
                    selectedIDs.removeAll()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#F5E4C3") ?? .clear)
                            .frame(width: 44, height: 44)
                        Text("Done")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(amber)
                    }
                }
            } else {
                Button {
                    isEditing = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#F5E4C3") ?? .clear)
                            .frame(width: 44, height: 44)
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(amber)
                    }
                }
                .padding(.trailing, 8)

                Button { dismiss() } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#F5E4C3") ?? .clear)
                            .frame(width: 44, height: 44)
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(amber)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(cream)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    // MARK: - Delete bar

    private var deleteBar: some View {
        VStack(spacing: 0) {
            divider.frame(height: 1)
            HStack {
                Text(selectedIDs.isEmpty ? "Select meals to delete" : "\(selectedIDs.count) selected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(selectedIDs.isEmpty ? muted : brown)
                Spacer()
                Button {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selectedIDs.isEmpty ? muted : .red)
                }
                .disabled(selectedIDs.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(cream)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Month header

    private func monthHeader(_ label: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy)).kerning(2)
                .foregroundColor(muted)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(cream)
    }

    // MARK: - History row

    private func historyRow(_ meal: Meal) -> some View {
        HStack(spacing: 14) {
            if isEditing {
                Image(systemName: selectedIDs.contains(meal.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(selectedIDs.contains(meal.id) ? amber : muted.opacity(0.4))
                    .frame(width: 24)
                    .transition(.opacity.combined(with: .scale))
            }

            // Date column
            VStack(spacing: 2) {
                Text(dayNumber(meal.date))
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(brown)
                Text(dayShort(meal.date).uppercased())
                    .font(.system(size: 9, weight: .heavy)).kerning(1)
                    .foregroundColor(muted)
            }
            .frame(width: 36)

            // Meal type accent line
            RoundedRectangle(cornerRadius: 2)
                .fill(mealAccent(meal.mealType))
                .frame(width: 3, height: 36)

            // Name + meta
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(brown)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(meal.mealType.label, systemImage: meal.mealType.iconName)
                    if meal.prepTimeMinutes > 0 {
                        Label("\(meal.prepTimeMinutes) min", systemImage: "clock")
                    }
                    if !meal.ingredients.isEmpty {
                        Label("\(meal.ingredients.count)", systemImage: "list.bullet")
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(muted)
            }

            Spacer()

            if !isEditing {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(muted.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .background(
            selectedIDs.contains(meal.id) ? amber.opacity(0.06) : Color.clear
        )
        .animation(.easeInOut(duration: 0.15), value: selectedIDs.contains(meal.id))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(amber.opacity(0.4))
            Text("No meal history yet")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(brown)
            Text("Meals from previous days will appear here.")
                .font(.system(size: 14))
                .foregroundColor(muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.top, 120)
    }

    // MARK: - Helpers

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func deleteSelected() {
        let toDelete = mealVM.pastMeals.filter { selectedIDs.contains($0.id) }
        for meal in toDelete {
            mealVM.deleteMeal(meal)
        }
        selectedIDs.removeAll()
        if mealVM.pastMeals.isEmpty {
            isEditing = false
        }
    }

    private func dayNumber(_ date: Date) -> String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private func dayShort(_ date: Date) -> String {
        Meal.Weekday.from(
            calendarWeekday: Calendar.current.component(.weekday, from: date)
        ).short
    }
}
