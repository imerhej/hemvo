//  Meal.swift
//  Homvi
//  Meal model for the weekly meal planner.

internal import Foundation

// MARK: - Meal
struct Meal: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var day: Weekday
    var mealType: MealType
    var ingredients: [GroceryItem]
    var notes: String
    var prepTimeMinutes: Int
    var servings: Int

    init(
        id: UUID = UUID(),
        name: String,
        day: Weekday,
        mealType: MealType,
        ingredients: [GroceryItem] = [],
        notes: String = "",
        prepTimeMinutes: Int = 30,
        servings: Int = 4
    ) {
        self.id = id
        self.name = name
        self.day = day
        self.mealType = mealType
        self.ingredients = ingredients
        self.notes = notes
        self.prepTimeMinutes = prepTimeMinutes
        self.servings = servings
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

        /// Maps Swift Calendar weekday (1=Sunday) to this enum
        static func from(calendarWeekday: Int) -> Weekday {
            // calendarWeekday: 1=Sun,2=Mon,...,7=Sat
            let mapped = calendarWeekday == 1 ? 7 : calendarWeekday - 1
            return Weekday(rawValue: mapped) ?? .monday
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
