//  MealHistoryView.swift
//  Hemvo
//  Read-only browsable log of past meals, grouped by month.

internal import SwiftUI

struct MealHistoryView: View {
    @ObservedObject var mealVM: MealPlanViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMeal: Meal? = nil

    private let cream   = Color(hex: "#F5F0E8")!
    private let amber   = Color(hex: "#C8922A")!
    private let brown   = Color(hex: "#1A1208")!
    private let muted   = Color(hex: "#7A6A55")!
    private let divider = Color(hex: "#E6DDD0")!

    // Group past meals by month (most recent month first)
    private var groupedByMonth: [(key: String, meals: [Meal])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"

        let dict = Dictionary(grouping: mealVM.pastMeals) { meal -> String in
            fmt.string(from: meal.date)
        }

        // Sort months descending by the actual date of any meal in that group
        return dict
            .map { (key: $0.key, meals: $0.value.sorted { $0.date > $1.date }) }
            .sorted { group1, group2 in
                (group1.meals.first?.date ?? .distantPast) > (group2.meals.first?.date ?? .distantPast)
            }
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
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .sheet(item: $selectedMeal) { meal in
            MealDetailView(mealID: meal.id, mealVM: mealVM)
        }
    }

    private func monthCard(_ meals: [Meal]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(meals.enumerated()), id: \.element.id) { idx, meal in
                Button { selectedMeal = meal } label: {
                    historyRow(meal)
                }
                .buttonStyle(.plain)

                if idx < meals.count - 1 {
                    divider.frame(height: 1).padding(.leading, 60)
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
            Button { dismiss() } label: {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#F5E4C3")!)
                        .frame(width: 44, height: 44)
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(amber)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(cream)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
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

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(muted.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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

    private func dayNumber(_ date: Date) -> String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private func dayShort(_ date: Date) -> String {
        Meal.Weekday.from(
            calendarWeekday: Calendar.current.component(.weekday, from: date)
        ).short
    }
}
