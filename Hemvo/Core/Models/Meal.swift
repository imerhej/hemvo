//  Meal.swift
//  Hemvo
//  Meal model for the weekly meal planner.

internal import Foundation

// MARK: - Meal
struct Meal: Identifiable, Equatable {
    let id: UUID
    var name: String
    var date: Date           // actual calendar date — fixes week-leakage bug
    var mealType: MealType
    var ingredients: [GroceryItem]
    var notes: String
    var prepTimeMinutes: Int
    var servings: Int
    var createdBy: String?

    /// Derived from `date` — do not store or encode separately.
    var day: Weekday {
        Weekday.from(calendarWeekday: Calendar.current.component(.weekday, from: date))
    }

    /// True when the meal date is before today (start of day). Past meals are read-only.
    var isPast: Bool {
        date < Calendar.current.startOfDay(for: Date())
    }

    init(
        id: UUID = UUID(),
        name: String,
        date: Date = Date(),
        mealType: MealType,
        ingredients: [GroceryItem] = [],
        notes: String = "",
        prepTimeMinutes: Int = 30,
        servings: Int = 4,
        createdBy: String? = nil
    ) {
        self.id             = id
        self.name           = name
        self.date           = Calendar.current.startOfDay(for: date)
        self.mealType       = mealType
        self.ingredients    = ingredients
        self.notes          = notes
        self.prepTimeMinutes = prepTimeMinutes
        self.servings       = servings
        self.createdBy      = createdBy
    }

    // MARK: - Weekday
    enum Weekday: Int, Codable, CaseIterable, Identifiable {
        case monday = 1, tuesday, wednesday,
             thursday, friday, saturday, sunday

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .monday:    return "Monday"
            case .tuesday:   return "Tuesday"
            case .wednesday: return "Wednesday"
            case .thursday:  return "Thursday"
            case .friday:    return "Friday"
            case .saturday:  return "Saturday"
            case .sunday:    return "Sunday"
            }
        }

        var short: String { String(label.prefix(3)) }

        /// Maps Swift Calendar weekday (1=Sunday) to this enum.
        static func from(calendarWeekday: Int) -> Weekday {
            let mapped = calendarWeekday == 1 ? 7 : calendarWeekday - 1
            return Weekday(rawValue: mapped) ?? .monday
        }

        /// Returns the start-of-day date for this weekday in the current calendar week.
        func dateInCurrentWeek() -> Date {
            let cal = Calendar.current
            let today = Date()
            // rawValue: Mon=1...Sun=7 → Calendar weekday: Mon=2...Sun=1
            let targetCalWD = rawValue == 7 ? 1 : rawValue + 1
            let todayCalWD  = cal.component(.weekday, from: today)
            let diff = targetCalWD - todayCalWD
            return cal.startOfDay(for: cal.date(byAdding: .day, value: diff, to: today) ?? today)
        }
    }

    // MARK: - MealType
    enum MealType: String, Codable, CaseIterable, Identifiable {
        case breakfast, lunch, dinner, snack

        var id: String { rawValue }

        var label: String { rawValue.capitalized }

        var iconName: String {
            switch self {
            case .breakfast: return "sun.horizon.fill"
            case .lunch:     return "sun.max.fill"
            case .dinner:    return "moon.stars.fill"
            case .snack:     return "leaf.fill"
            }
        }

        var sortOrder: Int {
            switch self {
            case .breakfast: return 0
            case .lunch:     return 1
            case .snack:     return 2
            case .dinner:    return 3
            }
        }
    }
}

// MARK: - Codable (custom — backward compat with old `day: Int` UserDefaults format)
extension Meal: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, date, mealType, ingredients, notes
        case prepTimeMinutes, servings, createdBy
        case legacyDay = "day"   // old format stored weekday rawValue as Int
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self,      forKey: .id)
        name            = try c.decode(String.self,    forKey: .name)
        mealType        = try c.decode(MealType.self,  forKey: .mealType)
        ingredients     = (try? c.decode([GroceryItem].self, forKey: .ingredients)) ?? []
        notes           = (try? c.decode(String.self,  forKey: .notes)) ?? ""
        prepTimeMinutes = (try? c.decode(Int.self,     forKey: .prepTimeMinutes)) ?? 30
        servings        = (try? c.decode(Int.self,     forKey: .servings)) ?? 4
        createdBy       = try? c.decode(String.self,   forKey: .createdBy)

        if let d = try? c.decode(Date.self, forKey: .date) {
            date = d
        } else if let rawDay = try? c.decode(Int.self, forKey: .legacyDay),
                  let weekday = Weekday(rawValue: rawDay) {
            // Old format: map to this week's occurrence of the stored weekday
            date = weekday.dateInCurrentWeek()
        } else {
            date = Calendar.current.startOfDay(for: Date())
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,               forKey: .id)
        try c.encode(name,             forKey: .name)
        try c.encode(date,             forKey: .date)
        try c.encode(mealType,         forKey: .mealType)
        try c.encode(ingredients,      forKey: .ingredients)
        try c.encode(notes,            forKey: .notes)
        try c.encode(prepTimeMinutes,  forKey: .prepTimeMinutes)
        try c.encode(servings,         forKey: .servings)
        try? c.encode(createdBy,       forKey: .createdBy)
    }
}
