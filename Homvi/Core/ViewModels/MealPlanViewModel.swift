//  MealPlanViewModel.swift
//  Homvi
//  Manages the weekly meal plan state.
//  Supabase `meals` table schema:
//    id, household_id, name, day (smallint), meal_type, ingredients (jsonb),
//    notes, prep_time_minutes, servings, created_by, created_at

internal import SwiftUI
internal import Foundation
internal import Combine
internal import Supabase

@MainActor
final class MealPlanViewModel: ObservableObject {

    @Published var meals: [Meal] = []

    private var cachedUserID:      UUID?
    private var cachedHouseholdID: UUID?

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

    func meals(for day: Meal.Weekday, type: Meal.MealType) -> [Meal] {
        meals.filter { $0.day == day && $0.mealType == type }
    }

    private let notif = NotificationService.shared

    // MARK: - CRUD
    func addMeal(_ meal: Meal) {
        meals.removeAll { $0.id == meal.id }
        meals.append(meal)
        persist()
        if UserDefaults.standard.bool(forKey: "notif_meals") {
            notif.scheduleMealReminders(meals: meals)
        }
        objectWillChange.send()
        Task { await supabaseUpsert(meal) }
    }

    func updateMeal(_ meal: Meal) {
        if let idx = meals.firstIndex(where: { $0.id == meal.id }) {
            meals[idx] = meal
            persist()
            if UserDefaults.standard.bool(forKey: "notif_meals") {
                notif.scheduleMealReminders(meals: meals)
            }
            objectWillChange.send()
            Task { await supabaseUpsert(meal) }
        }
    }

    func deleteMeal(_ meal: Meal) {
        meals.removeAll { $0.id == meal.id }
        persist()
        if UserDefaults.standard.bool(forKey: "notif_meals") {
            notif.scheduleMealReminders(meals: meals)
        }
        objectWillChange.send()
        Task { await supabaseDelete(id: meal.id) }
    }

    func clearWeek() {
        meals.removeAll()
        persist()
        notif.cancelMealReminders()
        objectWillChange.send()
        Task { await supabaseDeleteAll() }
    }

    // MARK: - Persistence
    private let storageKey = "hb_meals"

    init() {
        load()
        if UserDefaults.standard.bool(forKey: "notif_meals") {
            notif.scheduleMealReminders(meals: meals)
        }
        Task { await loadFromSupabase() }
    }

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

    // MARK: - Supabase Sync

    func loadFromSupabase() async {
        guard let uid = await AuthService.shared.currentUserID() else { return }
        cachedUserID = uid

        if let profile = try? await AuthService.shared.loadProfile() {
            cachedHouseholdID = profile.householdId
        }

        do {
            var query = supabase.from("meals").select()

            if let hid = cachedHouseholdID {
                query = query.eq("household_id", value: hid.uuidString)
            } else {
                query = query.eq("created_by", value: uid.uuidString)
            }

            let rows: [SupabaseMealRow] = try await query.execute().value
            meals = rows.map { $0.toMeal() }
            persist()
            if UserDefaults.standard.bool(forKey: "notif_meals") {
                notif.scheduleMealReminders(meals: meals)
            }
        } catch {
            print("[Supabase] fetch meals error: \(error)")
        }
    }

    private func resolveIDs() async {
        if cachedUserID == nil {
            cachedUserID = await AuthService.shared.currentUserID()
        }
        if cachedHouseholdID == nil, let profile = try? await AuthService.shared.loadProfile() {
            cachedHouseholdID = profile.householdId
        }
    }

    private func supabaseUpsert(_ meal: Meal) async {
        await resolveIDs()
        guard let uid = cachedUserID else { return }
        let row = SupabaseMealRow(from: meal, userId: uid, householdId: cachedHouseholdID)
        do {
            try await supabase.from("meals").upsert(row, onConflict: "id").execute()
        } catch {
            print("[Supabase] upsert meal error: \(error)")
        }
    }

    private func supabaseDelete(id: UUID) async {
        do {
            try await supabase.from("meals").delete().eq("id", value: id.uuidString).execute()
        } catch {
            print("[Supabase] delete meal error: \(error)")
        }
    }

    private func supabaseDeleteAll() async {
        await resolveIDs()
        guard let uid = cachedUserID else { return }
        do {
            if let hid = cachedHouseholdID {
                try await supabase.from("meals").delete()
                    .eq("household_id", value: hid.uuidString).execute()
            } else {
                try await supabase.from("meals").delete()
                    .eq("created_by", value: uid.uuidString).execute()
            }
        } catch {
            print("[Supabase] delete all meals error: \(error)")
        }
    }
}

// MARK: - Supabase row mapping
private struct SupabaseMealRow: Codable {
    let id:             UUID
    let householdId:    UUID?
    var name:           String
    var day:            Int
    var mealType:       String
    var ingredients:    [GroceryItem]
    var notes:          String
    var prepTimeMinutes: Int
    var servings:       Int
    let createdBy:      UUID

    enum CodingKeys: String, CodingKey {
        case id
        case householdId     = "household_id"
        case name
        case day
        case mealType        = "meal_type"
        case ingredients
        case notes
        case prepTimeMinutes = "prep_time_minutes"
        case servings
        case createdBy       = "created_by"
    }

    init(from meal: Meal, userId: UUID, householdId: UUID?) {
        id               = meal.id
        createdBy        = userId
        self.householdId = householdId
        name             = meal.name
        day              = meal.day.rawValue
        mealType         = meal.mealType.rawValue
        ingredients      = meal.ingredients
        notes            = meal.notes
        prepTimeMinutes  = meal.prepTimeMinutes
        servings         = meal.servings
    }

    func toMeal() -> Meal {
        Meal(
            id:              id,
            name:            name,
            day:             Meal.Weekday(rawValue: day) ?? .monday,
            mealType:        Meal.MealType(rawValue: mealType) ?? .dinner,
            ingredients:     ingredients,
            notes:           notes,
            prepTimeMinutes: prepTimeMinutes,
            servings:        servings
        )
    }
}
