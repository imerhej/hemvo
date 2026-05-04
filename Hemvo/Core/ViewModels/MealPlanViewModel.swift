//  MealPlanViewModel.swift
//  Hemvo
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

    private var deletedMealIDs:    Set<UUID> = []

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
        var stamped = meal
        if stamped.createdBy == nil { stamped.createdBy = cachedUserID?.uuidString }
        meals.removeAll { $0.id == stamped.id }
        meals.append(stamped)
        persist()
        if UserDefaults.standard.bool(forKey: "notif_meals") {
            notif.scheduleMealReminders(meals: meals)
        }
        objectWillChange.send()
        Task { await supabaseUpsert(stamped) }
        Task {
            await PushNotificationService.shared.notifyHousehold(
                title: "🍽️ Meal Planned",
                body: "\(stamped.name) · \(stamped.day.label) \(stamped.mealType.rawValue)"
            )
        }
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
        guard canDelete(meal) else { return }
        deletedMealIDs.insert(meal.id)
        persistDeletedIDs()
        meals.removeAll { $0.id == meal.id }
        persist()
        if UserDefaults.standard.bool(forKey: "notif_meals") {
            notif.scheduleMealReminders(meals: meals)
        }
        objectWillChange.send()
        Task { await supabaseDelete(id: meal.id) }
    }

    // MARK: - Ownership check
    func canDelete(_ meal: Meal) -> Bool {
        guard let uid = cachedUserID else { return false }
        guard let createdBy = meal.createdBy else { return true }
        return createdBy == uid.uuidString
    }

    func clearWeek() {
        for meal in meals { deletedMealIDs.insert(meal.id) }
        persistDeletedIDs()
        meals.removeAll()
        persist()
        notif.cancelMealReminders()
        objectWillChange.send()
        Task { await supabaseDeleteAll() }
    }

    // MARK: - Persistence
    private let storageKey        = "hb_meals"
    private let deletedMealIDsKey = "hb_deletedMealIDs"

    init() {
        loadDeletedIDs()
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

    private func loadDeletedIDs() {
        guard let d = UserDefaults.standard.data(forKey: deletedMealIDsKey),
              let v = try? JSONDecoder().decode([UUID].self, from: d) else { return }
        deletedMealIDs = Set(v)
    }

    private func persistDeletedIDs() {
        if let d = try? JSONEncoder().encode(Array(deletedMealIDs)) {
            UserDefaults.standard.set(d, forKey: deletedMealIDsKey)
        }
    }

    // MARK: - Supabase Sync

    func loadFromSupabase() async {
        guard let uid = await AuthService.shared.currentUserID() else { return }
        cachedUserID = uid

        if let profile = try? await AuthService.shared.loadProfile() {
            cachedHouseholdID = profile.householdId
        }
        if cachedHouseholdID == nil {
            cachedHouseholdID = UUID(uuidString: HouseholdService.shared.household?.id ?? "")
        }

        do {
            var query = supabase.from("meals").select()

            if let hid = cachedHouseholdID {
                query = query.eq("household_id", value: hid.uuidString)
            } else {
                query = query.eq("created_by", value: uid.uuidString)
            }

            let rows: [SupabaseMealRow] = try await query.execute().value

            // Re-fire delete for tombstoned meals still present remotely.
            let staleRows = rows.filter { deletedMealIDs.contains($0.id) }
            for row in staleRows { Task { await supabaseDelete(id: row.id) } }

            let remoteMeals = rows.filter { !deletedMealIDs.contains($0.id) }.map { $0.toMeal() }
            let remoteIDs = Set(remoteMeals.map { $0.id })
            let pendingLocal = meals.filter { !remoteIDs.contains($0.id) && !deletedMealIDs.contains($0.id) }
            meals = remoteMeals + pendingLocal
            persist()
            if UserDefaults.standard.bool(forKey: "notif_meals") {
                notif.scheduleMealReminders(meals: meals)
            }
            for m in pendingLocal { Task { await supabaseUpsert(m) } }
        } catch {
            print("[Supabase] fetch meals error: \(error)")
        }
    }

    private func resolveIDs() async {
        if cachedUserID == nil {
            cachedUserID = await AuthService.shared.currentUserID()
        }
        if cachedHouseholdID == nil {
            cachedHouseholdID = (try? await AuthService.shared.loadProfile())?.householdId
                ?? UUID(uuidString: HouseholdService.shared.household?.id ?? "")
        }
    }

    private func supabaseUpsert(_ meal: Meal) async {
        await resolveIDs()
        guard let uid = cachedUserID, let hid = cachedHouseholdID else { return }
        let row = SupabaseMealRow(from: meal, userId: uid, householdId: hid)
        do {
            try await supabase.from("meals").upsert(row, onConflict: "id").execute()
        } catch {
            print("[Supabase] upsert meal error: \(error)")
        }
    }

    private func supabaseDelete(id: UUID) async {
        do {
            try await supabase.from("meals").delete().eq("id", value: id.uuidString).execute()
            deletedMealIDs.remove(id)
            persistDeletedIDs()
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
            deletedMealIDs.removeAll()
            persistDeletedIDs()
        } catch {
            print("[Supabase] delete all meals error: \(error)")
        }
    }
}

// MARK: - Supabase row mapping
private struct SupabaseMealRow: Codable {
    let id:             UUID
    let householdId:    UUID         // NOT NULL in DB
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

    init(from meal: Meal, userId: UUID, householdId: UUID) {
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
            servings:        servings,
            createdBy:       createdBy.uuidString
        )
    }
}
