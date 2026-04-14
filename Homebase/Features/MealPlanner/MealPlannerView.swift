//  MealPlannerView.swift
//  HomeBase
//  Redesigned: Editorial food-magazine — light warm palette, day strip.

internal import SwiftUI
internal import Combine

// MARK: - Palette
private extension Color {
    static let mpBackground = Color(hex: "#FAF7F2")!
    static let mpSurface    = Color(hex: "#FFFFFF")!
    static let mpAmber      = Color(hex: "#C8922A")!
    static let mpAmberLight = Color(hex: "#F5E4C3")!
    static let mpText       = Color(hex: "#1A1208")!
    static let mpTextSub    = Color(hex: "#7A6A55")!
    static let mpDivider    = Color(hex: "#E6DDD0")!
}

// MARK: - MealPlannerView
struct MealPlannerView: View {

    @StateObject private var mealVM    = MealPlanViewModel()
    @StateObject private var groceryVM = GroceryViewModel()

    @State private var selectedDay: Meal.Weekday = {
        let wd = Calendar.current.component(.weekday, from: Date())
        return Meal.Weekday.from(calendarWeekday: wd)
    }()
    @State private var showAddMeal     = false
    @State private var showGroceryList = false
    @State private var selectedMealID: UUID? = nil   // ID only — detail derives live from VM
    @State private var refreshID       = UUID()
    @State private var addMealType: Meal.MealType = .breakfast
    @Namespace private var stripAnim

    var mealsForDay: [Meal] { mealVM.meals(for: selectedDay) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.mpBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerSection
                    dayStrip
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            dayLabel
                            mealGrid
                            weekStripCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showAddMeal) {
                AddMealView(
                    mealVM: mealVM,
                    preselectedDay: selectedDay,
                    preselectedType: addMealType
                )
                .onDisappear { refreshID = UUID() }
            }
            .sheet(isPresented: $showGroceryList) {
                GroceryListView(groceryVM: groceryVM)
            }
            .sheet(isPresented: Binding(
                get: { selectedMealID != nil },
                set: { if !$0 { selectedMealID = nil } }
            )) {
                if let id = selectedMealID {
                    MealDetailView(mealID: id, mealVM: mealVM)
                }
            }
        }
    }

    // MARK: - Header (cart only, no plus)
    private var headerSection: some View {
        ZStack {
            Color.mpSurface
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MEAL PLANNER")
                        .font(.system(size: 10, weight: .heavy))
                        .kerning(3)
                        .foregroundColor(Color.mpAmber)
                    Text("This Week")
                        .font(.system(size: 26, weight: .black))
                        .foregroundColor(Color.mpText)
                }
                Spacer()
                // Cart only — no plus button
                Button {
                    groceryVM.syncFromMeals(mealVM.meals)
                    showGroceryList = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.mpAmberLight)
                            .frame(width: 40, height: 40)
                        Image(systemName: "cart.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.mpAmber)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 52)
            .padding(.bottom, 14)
        }
        .frame(height: 120)
        .overlay(alignment: .bottom) {
            Color.mpDivider.frame(height: 1)
        }
    }

    // MARK: - Day Strip (horizontal scroll, abbreviated day names + month label)
    private var dayStrip: some View {
        VStack(spacing: 0) {
            // Month label above the strip
            HStack {
                Text(selectedCalDate.formatted(.dateTime.month(.wide).year()).uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(2)
                    .foregroundColor(Color.mpTextSub)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(allMonthDays, id: \.self) { date in
                            let cal        = Calendar.current
                            let dayNum     = cal.component(.day, from: date)
                            let weekdayIdx = cal.component(.weekday, from: date)
                            let weekday    = Meal.Weekday.from(calendarWeekday: weekdayIdx)
                            let isSelected = cal.isDate(date, inSameDayAs: selectedCalDate)
                            let isToday    = cal.isDateInToday(date)
                            let hasMeals   = !mealVM.meals(for: weekday).isEmpty
                            // Full abbreviated name: Mon, Tue, Wed…
                            let dayName    = date.formatted(.dateTime.weekday(.abbreviated))

                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                                    selectedCalDate = date
                                    selectedDay     = weekday
                                }
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            isSelected ? Color.mpAmber :
                                            isToday    ? Color.mpAmberLight :
                                                         Color.mpSurface
                                        )
                                        .if(isSelected) { v in
                                            v.matchedGeometryEffect(id: "strip", in: stripAnim)
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(
                                                    isToday && !isSelected
                                                        ? Color.mpAmber.opacity(0.45)
                                                        : Color.mpDivider.opacity(isSelected ? 0 : 1),
                                                    lineWidth: 1
                                                )
                                        )

                                    VStack(spacing: 2) {
                                        Text(dayName)
                                            .font(.system(size: 9, weight: .heavy))
                                            .kerning(0.2)
                                            .foregroundColor(
                                                isSelected ? .white.opacity(0.85) :
                                                isToday    ? Color.mpAmber :
                                                             Color.mpTextSub
                                            )
                                        Text("\(dayNum)")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(
                                                isSelected ? .white :
                                                isToday    ? Color.mpAmber :
                                                             Color.mpText
                                            )
                                        Circle()
                                            .fill(
                                                hasMeals
                                                    ? (isSelected ? Color.white.opacity(0.75) : Color.mpAmber)
                                                    : Color.clear
                                            )
                                            .frame(width: 3, height: 3)
                                    }
                                }
                                .frame(width: 44, height: 50)
                                .id(date)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(selectedCalDate, anchor: .center)
                    }
                }
            }

            Color.mpDivider.frame(height: 1)
        }
        .background(Color.mpSurface)
    }

    // MARK: - Day Label
    private var dayLabel: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDay.label.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .kerning(2)
                    .foregroundColor(Color.mpAmber)
                Text("\(mealsForDay.count) meal\(mealsForDay.count == 1 ? "" : "s") planned")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.mpTextSub)
            }
            Spacer()
            Button {
                addMealType = .breakfast
                showAddMeal = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("Add Meal")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(Color.mpAmber)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.mpAmberLight)
                .cornerRadius(20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    // MARK: - Meal Grid
    private var mealGrid: some View {
        VStack(spacing: 10) {
            ForEach(Meal.MealType.allCases) { type in
                let meal = mealVM.meal(for: selectedDay, type: type)
                MealRecipeCard(
                    mealType: type,
                    meal: meal,
                    onAdd: {
                        addMealType = type
                        showAddMeal = true
                    },
                    onTap: { m in selectedMealID = m.id }
                )
                .padding(.horizontal, 20)
                .id(refreshID)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Week Strip
    private var weekStripCard: some View {
        HStack(spacing: 0) {
            WeekStatLight(value: "\(mealVM.meals.count)",          label: "Meals")
            Color.mpDivider.frame(width: 1, height: 28)
            WeekStatLight(value: "\(mealVM.allIngredients.count)", label: "Ingredients")
            Color.mpDivider.frame(width: 1, height: 28)
            WeekStatLight(
                value: "\(Meal.Weekday.allCases.count - Set(mealVM.meals.map { $0.day }).count)",
                label: "Days Open"
            )
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.mpSurface)
                .shadow(color: Color.mpText.opacity(0.05), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.mpDivider, lineWidth: 1)
        )
    }

    // MARK: - All days in current month
    @State private var selectedCalDate: Date = Calendar.current.startOfDay(for: Date())

    private var allMonthDays: [Date] {
        let cal   = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: selectedCalDate)
        guard let firstOfMonth = cal.date(from: comps),
              let range        = cal.range(of: .day, in: .month, for: firstOfMonth)
        else { return [] }
        return range.compactMap { day -> Date? in
            comps.day = day
            return cal.date(from: comps)   // midnight — matches isDate(inSameDayAs:)
        }
    }
}

// MARK: - MealRecipeCard
struct MealRecipeCard: View {
    let mealType: Meal.MealType
    let meal: Meal?
    let onAdd: () -> Void
    let onTap: (Meal) -> Void

    private var typeColor: Color {
        switch mealType {
        case .breakfast: return Color(hex: "#C8922A")!
        case .lunch:     return Color(hex: "#4A9E6B")!
        case .dinner:    return Color(hex: "#3B7DD8")!
        case .snack:     return Color(hex: "#9A5CC4")!
        }
    }
    private var typeBg: Color {
        switch mealType {
        case .breakfast: return Color(hex: "#FEF5E7")!
        case .lunch:     return Color(hex: "#EAF7EF")!
        case .dinner:    return Color(hex: "#EBF2FD")!
        case .snack:     return Color(hex: "#F5EEF9")!
        }
    }

    var body: some View {
        if let meal {
            Button { onTap(meal) } label: {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(typeColor)
                        .frame(width: 4)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: mealType.iconName)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(typeColor)
                            Text(mealType.label.uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .kerning(1.2)
                                .foregroundColor(typeColor)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(hex: "#7A6A55")!.opacity(0.4))
                        }
                        Text(meal.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color(hex: "#1A1208")!)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            LightMetaChip(icon: "clock",       text: "\(meal.prepTimeMinutes)m",       color: typeColor)
                            LightMetaChip(icon: "person.2",    text: "\(meal.servings) srv",            color: typeColor)
                            if !meal.ingredients.isEmpty {
                                LightMetaChip(icon: "list.bullet", text: "\(meal.ingredients.count) ing.", color: typeColor)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#E6DDD0")!, lineWidth: 1))
                .shadow(color: Color(hex: "#1A1208")!.opacity(0.05), radius: 6, y: 2)
            }
            .buttonStyle(.plain)

        } else {
            Button(action: onAdd) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(typeBg)
                            .frame(width: 38, height: 38)
                        Image(systemName: mealType.iconName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(typeColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mealType.label.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .kerning(1.2)
                            .foregroundColor(typeColor.opacity(0.9))
                        Text("Plan \(mealType.label.lowercased())")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(hex: "#7A6A55")!)
                    }
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(typeColor)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(typeBg.opacity(0.6)))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(typeColor.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - LightMetaChip
private struct LightMetaChip: View {
    let icon: String; let text: String; let color: Color
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold))
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(20)
    }
}

// MARK: - WeekStatLight
private struct WeekStatLight: View {
    let value: String; let label: String
    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .black)).foregroundColor(Color(hex: "#1A1208")!)
            Text(label.uppercased()).font(.system(size: 8, weight: .heavy)).kerning(1.2).foregroundColor(Color(hex: "#7A6A55")!)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview { MealPlannerView() }
