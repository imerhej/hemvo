//  MealPlannerView.swift
//  Hemvo
//  Rebuilt from screenshot: warm cream bg, amber header, horizontal date strip,
//  colour-coded dashed meal cards, weekly summary, grocery FAB circle.

internal import SwiftUI
internal import Combine

// MARK: - Palette
private let mpCream   = Color(hex: "#F5F0E8")!   // page background
private let mpAmber   = Color(hex: "#C8922A")!   // amber text / accents
private let mpBrown   = Color(hex: "#1A1208")!   // primary text
private let mpMuted   = Color(hex: "#7A6A55")!   // secondary text
private let mpDivider = Color(hex: "#E6DDD0")!   // borders

// Meal type tint colours (matching screenshot) — internal so MealHistoryView can reuse them
func mealBg(_ type: Meal.MealType) -> Color {
    switch type {
    case .breakfast: return Color(hex: "#FEF3E2")!   // warm peach
    case .lunch:     return Color(hex: "#E8F5E9")!   // mint green
    case .dinner:    return Color(hex: "#E3F0FB")!   // soft blue
    case .snack:     return Color(hex: "#F3E5F5")!   // lavender
    }
}
func mealAccent(_ type: Meal.MealType) -> Color {
    switch type {
    case .breakfast: return Color(hex: "#C8922A")!
    case .lunch:     return Color(hex: "#3D7A52")!
    case .dinner:    return Color(hex: "#2979C8")!
    case .snack:     return Color(hex: "#8B44AC")!
    }
}

// MARK: - MealPlannerView
private struct AddMealRequest: Identifiable {
    let id   = UUID()
    let date: Date           // actual calendar date — used when creating the meal
    let type: Meal.MealType
}

struct MealPlannerView: View {

    @StateObject private var mealVM    = MealPlanViewModel()
    @StateObject private var groceryVM = GroceryViewModel()
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var householdService: HouseholdService

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var addMealRequest: AddMealRequest? = nil
    @State private var showGroceryList     = false
    @State private var selectedMeal: Meal? = nil
    @State private var showHistory         = false
    @State private var refreshID = UUID()

    private var canWrite: Bool {
        guard let uid = authVM.userID?.uuidString,
              let member = householdService.household?.members.first(where: { $0.id == uid })
        else { return true }
        return member.role.canWrite
    }

    private var isPastDate: Bool {
        selectedDate < Calendar.current.startOfDay(for: Date())
    }

    private var mealsForDay: [Meal] { mealVM.meals(for: selectedDate) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                mpCream.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    dateStrip
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            dayLabel
                            mealCards
                            summaryCard
                        }
                        .padding(.bottom, 100)
                        .frame(maxWidth: 680)
                        .frame(maxWidth: .infinity)
                    }
                }

                // (no shopping list FAB)
            }
            .navigationBarHidden(true)
            .onAppear {
                // Refresh on every appearance so household members see each other's deletions
                Task { await mealVM.loadFromSupabase() }
            }
            .sheet(item: $addMealRequest) { req in
                AddMealView(mealVM: mealVM, preselectedDate: req.date, preselectedType: req.type)
                    .onDisappear { refreshID = UUID() }
            }
            .sheet(isPresented: $showHistory) {
                MealHistoryView(mealVM: mealVM)
            }
            .sheet(isPresented: $showGroceryList) {
                GroceryListView(groceryVM: groceryVM)
            }
            .sheet(item: $selectedMeal) { meal in
                MealDetailView(mealID: meal.id, mealVM: mealVM)
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MEAL PLANNER")
                    .font(.system(size: 11, weight: .heavy)).kerning(2.5)
                    .foregroundColor(mpAmber)
                Text("This Week")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(mpBrown)
            }
            Spacer()
            HStack(spacing: 10) {
                // History button
                Button { showHistory = true } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#F5E4C3")!)
                            .frame(width: 52, height: 52)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(mpAmber)
                    }
                }
                // Amber circle grocery button
                Button {
                    groceryVM.syncFromMeals(mealVM.meals)
                    showGroceryList = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#F5E4C3")!)
                            .frame(width: 52, height: 52)
                        Image(systemName: "cart.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(mpAmber)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(mpCream)
        .overlay(alignment: .bottom) { mpDivider.frame(height: 1) }
    }

    // MARK: - Date Strip
    private var dateStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(monthLabel.uppercased())
                .font(.system(size: 10, weight: .heavy)).kerning(2)
                .foregroundColor(mpMuted)
                .padding(.leading, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visibleDays, id: \.date) { item in
                            DayCell(
                                dayShort: item.short,
                                dayNum:   item.num,
                                hasMeals: !mealVM.meals(for: item.date).isEmpty,
                                isSelected: Calendar.current.isDate(item.date, inSameDayAs: selectedDate)
                            ) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedDate = item.date
                                }
                            }
                            .id(item.date)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .onAppear {
                    proxy.scrollTo(selectedDate, anchor: .center)
                }
                .onChange(of: selectedDate) { _, date in
                    withAnimation { proxy.scrollTo(date, anchor: .center) }
                }
            }
        }
        .background(mpCream)
        .overlay(alignment: .bottom) { mpDivider.frame(height: 1) }
    }

    // Builds 14 days centred on today for the strip
    private struct DayItem {
        let date: Date              // start-of-day — stable identity for ScrollViewReader
        var short: String {
            Meal.Weekday.from(
                calendarWeekday: Calendar.current.component(.weekday, from: date)
            ).short
        }
        var num: Int {
            Calendar.current.component(.day, from: date)
        }
    }

    private var visibleDays: [DayItem] {
        let cal   = Calendar.current
        let today = Date()
        return (-3...10).compactMap { offset -> DayItem? in
            guard let raw = cal.date(byAdding: .day, value: offset, to: today) else { return nil }
            return DayItem(date: cal.startOfDay(for: raw))
        }
    }

    private var monthLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: selectedDate)
    }

    // MARK: - Day label
    private var dayLabel: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    Meal.Weekday.from(
                        calendarWeekday: Calendar.current.component(.weekday, from: selectedDate)
                    ).label.uppercased()
                )
                .font(.system(size: 13, weight: .heavy)).kerning(1.5)
                .foregroundColor(mpAmber)
                Text(isPastDate
                     ? "\(mealsForDay.count) meal\(mealsForDay.count == 1 ? "" : "s") · history"
                     : "\(mealsForDay.count) meal\(mealsForDay.count == 1 ? "" : "s") planned")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(mpMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Meal Cards
    private var mealCards: some View {
        VStack(spacing: 12) {
            ForEach(Meal.MealType.allCases) { type in
                MealTypeSection(
                    mealType: type,
                    meals:    mealVM.meals(for: selectedDate, type: type),
                    onAdd:    (canWrite && !isPastDate) ? { addMealRequest = AddMealRequest(date: selectedDate, type: type) } : nil,
                    onTap:    { selectedMeal = $0 }
                )
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Weekly Summary Card
    private var daysOpenCount: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let nextWeek = cal.date(byAdding: .day, value: 7, to: today) else { return 0 }
        let coveredDays = Set(
            mealVM.meals
                .filter { $0.date >= today && $0.date < nextWeek }
                .map { cal.startOfDay(for: $0.date) }
        )
        return max(0, 7 - coveredDays.count)
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryCol(value: "\(mealVM.meals.count)", label: "MEALS")
            Rectangle().fill(mpDivider).frame(width: 1, height: 32)
            summaryCol(value: "\(mealVM.allIngredients.count)", label: "INGREDIENTS")
            Rectangle().fill(mpDivider).frame(width: 1, height: 32)
            summaryCol(value: "\(daysOpenCount)", label: "DAYS OPEN")
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(mpDivider, lineWidth: 1))
        .shadow(color: mpBrown.opacity(0.04), radius: 6, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func summaryCol(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .black))
                .foregroundColor(mpBrown)
            Text(label)
                .font(.system(size: 9, weight: .heavy)).kerning(1)
                .foregroundColor(mpMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - DayCell
struct DayCell: View {
    let dayShort:   String
    let dayNum:     Int
    let hasMeals:   Bool
    let isSelected: Bool
    let action:     () -> Void

    private let amber   = Color(hex: "#C8922A")!
    private let brown   = Color(hex: "#1A1208")!
    private let muted   = Color(hex: "#7A6A55")!
    private let divider = Color(hex: "#E6DDD0")!

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(dayShort.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(isSelected ? .white : muted)

                Text("\(dayNum)")
                    .font(.system(size: 16, weight: isSelected ? .black : .semibold))
                    .foregroundColor(isSelected ? .white : brown)

                Circle()
                    .fill(hasMeals
                          ? (isSelected ? Color.white.opacity(0.8) : amber)
                          : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 56, height: 72)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? amber : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.clear : divider, lineWidth: 1)
                    )
            )
            .shadow(color: isSelected ? amber.opacity(0.3) : Color.black.opacity(0.03),
                    radius: isSelected ? 8 : 2, y: 2)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - MealTypeSection
private struct MealTypeSection: View {
    let mealType: Meal.MealType
    let meals:    [Meal]
    let onAdd:    (() -> Void)?   // nil = read-only; hides add buttons
    let onTap:    (Meal) -> Void

    private var accent: Color { mealAccent(mealType) }
    private var bg:     Color { mealBg(mealType) }
    private let brown   = Color(hex: "#1A1208")!
    private let muted   = Color(hex: "#7A6A55")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header row
            HStack(spacing: 8) {
                Image(systemName: mealType.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                Text(mealType.label.uppercased())
                    .font(.system(size: 10, weight: .heavy)).kerning(1.2)
                    .foregroundColor(accent)
                if !meals.isEmpty {
                    Text("·  \(meals.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(muted)
                }
                Spacer()
                if let onAdd {
                    Button(action: onAdd) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("Add")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(accent)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(accent.opacity(0.12))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            if meals.isEmpty {
                if let onAdd {
                    Button(action: onAdd) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(accent.opacity(0.45))
                            Text("Plan \(mealType.label.lowercased())")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(muted)
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.bottom, 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Nothing planned")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(muted)
                        .padding(.horizontal, 14).padding(.bottom, 14)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(meals) { meal in
                        Button { onTap(meal) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(brown)
                                        .lineLimit(1)
                                    HStack(spacing: 10) {
                                        Label("\(meal.prepTimeMinutes) min", systemImage: "clock")
                                        Label("\(meal.servings) srv",        systemImage: "person.2")
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
                                    .foregroundColor(muted.opacity(0.45))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if meal.id != meals.last?.id {
                            accent.opacity(0.15).frame(height: 1)
                                .padding(.leading, 14)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .background(bg)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundColor(accent.opacity(0.35))
        )
    }
}

// MARK: - ScreenshotMealCard
struct ScreenshotMealCard: View {
    let mealType: Meal.MealType
    let meal:     Meal?
    let onAdd:    () -> Void
    let onTap:    () -> Void

    private var accent: Color { mealAccent(mealType) }
    private var bg:     Color { mealBg(mealType) }
    private let brown   = Color(hex: "#1A1208")!
    private let muted   = Color(hex: "#7A6A55")!

    var body: some View {
        Button {
            if meal != nil { onTap() } else { onAdd() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: mealType.iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(mealType.label.uppercased())
                        .font(.system(size: 10, weight: .heavy)).kerning(1.2)
                        .foregroundColor(accent)
                    if let meal {
                        Text(meal.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(brown)
                            .lineLimit(1)
                    } else {
                        Text("Plan \(mealType.label.lowercased())")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(muted)
                    }
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 32, height: 32)
                    Image(systemName: meal == nil ? "plus" : "chevron.right")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(bg)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundColor(accent.opacity(0.35))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compat stubs
struct MealSlotCard: View {
    let mealType: Meal.MealType; let meal: Meal?
    let onAdd: () -> Void;       let onTap: (Meal) -> Void
    var body: some View {
        ScreenshotMealCard(
            mealType: mealType, meal: meal,
            onAdd: onAdd, onTap: { if let m = meal { onTap(m) } }
        )
    }
}
struct WeeklySummaryCard: View {
    @ObservedObject var mealVM: MealPlanViewModel
    var body: some View { EmptyView() }
}

#Preview {
    MealPlannerView()
        .environmentObject(AuthViewModel())
        .environmentObject(HouseholdService.shared)
}
