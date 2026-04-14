//  MealPlanViewModel.swift
//  HomeBase
//  Manages the weekly meal plan state.

internal import SwiftUI
internal import Foundation
internal import Combine

@MainActor
final class MealPlanViewModel: ObservableObject {

    @Published var meals: [Meal] = []

    // MARK: - Computed
    var todaysMeals: [Meal] {
        let wd  = Calendar.current.component(.weekday, from: Date())
        let day = Meal.Weekday.from(calendarWeekday: wd)
        return meals.filter { $0.day == day }
            .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }
    }

    var allIngredients: [GroceryItem] {
        meals.flatMap { $0.ingredients }
    }

    // MARK: - Query
    func meal(for day: Meal.Weekday, type: Meal.MealType) -> Meal? {
        meals.first { $0.day == day && $0.mealType == type }
    }

    func meals(for day: Meal.Weekday) -> [Meal] {
        meals.filter { $0.day == day }
            .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }
    }

    // MARK: - CRUD
    func addMeal(_ meal: Meal) {
        // Step 1: Remove any existing entry with the SAME id.
        //         This handles the "move" case — e.g. Friday dinner edited to
        //         Saturday dinner via AddMealView, which calls addMeal with the
        //         same id but a new day/type. Without this, the original slot
        //         would linger alongside the new one.
        meals.removeAll { $0.id == meal.id }

        // Step 2: If the target slot (day + mealType) is already occupied by a
        //         *different* meal, replace it so we never have two meals in the
        //         same slot.
        if let idx = meals.firstIndex(where: {
            $0.day == meal.day && $0.mealType == meal.mealType
        }) {
            meals[idx] = meal
        } else {
            meals.append(meal)
        }

        persist()
        objectWillChange.send()
    }

    func updateMeal(_ meal: Meal) {
        if let idx = meals.firstIndex(where: { $0.id == meal.id }) {
            meals[idx] = meal
            persist()
            objectWillChange.send()
        }
    }

    func deleteMeal(_ meal: Meal) {
        meals.removeAll { $0.id == meal.id }
        persist()
        objectWillChange.send()
    }

    func clearWeek() {
        meals.removeAll()
        persist()
        objectWillChange.send()
    }

    // MARK: - Persistence
    private let storageKey = "hb_meals"

    init() { load() }

    private func load() {
        guard let data    = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Meal].self, from: data)
        else { return }
        meals = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(meals) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
