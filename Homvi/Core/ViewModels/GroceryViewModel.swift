//  GroceryViewModel.swift
//  Homvi
//  Manages grocery list — combines auto-generated items from meals and manual entries.
//  Checked items persist until explicitly deleted.
//  Supabase `grocery_items` table:
//    id, household_id, name, quantity, unit, category, is_checked,
//    source_meal_id, created_by, created_at

internal import SwiftUI
internal import Foundation
internal import Combine
internal import Supabase

@MainActor
final class GroceryViewModel: ObservableObject {

    @Published var items: [GroceryItem] = []

    private var cachedUserID:      UUID?
    private var cachedHouseholdID: UUID?

    // MARK: - Computed
    var checkedItems:   [GroceryItem] { items.filter {  $0.isChecked } }
    var uncheckedItems: [GroceryItem] { items.filter { !$0.isChecked } }

    var itemsByCategory: [String: [GroceryItem]] {
        Dictionary(grouping: items, by: { $0.category.rawValue })
    }

    var uncheckedByCategory: [String: [GroceryItem]] {
        Dictionary(grouping: uncheckedItems, by: { $0.category.rawValue })
    }

    var progress: Double {
        guard !items.isEmpty else { return 0 }
        return Double(checkedItems.count) / Double(items.count)
    }

    // MARK: - Sync from Meal Plan
    func syncFromMeals(_ meals: [Meal]) {
        var checkedByName: [String: Bool] = [:]
        for item in items where item.sourceMealID != nil {
            checkedByName[item.name.lowercased()] = item.isChecked
        }

        let oldMealItems = items.filter { $0.sourceMealID != nil }
        items.removeAll { $0.sourceMealID != nil }

        var seen = Set<String>()
        var newMealItems: [GroceryItem] = []
        for meal in meals {
            for ing in meal.ingredients {
                let key = ing.name.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                var item          = ing
                item.sourceMealID = meal.id
                item.isChecked    = checkedByName[key] ?? false
                items.append(item)
                newMealItems.append(item)
            }
        }
        persist()

        // Remove old meal-sourced items from Supabase and upsert the new ones
        Task {
            for old in oldMealItems {
                await supabaseDelete(id: old.id)
            }
            for new in newMealItems {
                await supabaseUpsert(new)
            }
        }
    }

    // MARK: - CRUD
    func addItem(_ item: GroceryItem) {
        items.append(item)
        persist()
        Task { await supabaseUpsert(item) }
    }

    func toggleItem(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isChecked.toggle()
            persist()
            Task { await supabaseUpsert(items[idx]) }
        }
    }

    func deleteItem(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        persist()
        Task { await supabaseDelete(id: item.id) }
    }

    func clearChecked() {
        let toDelete = checkedItems
        items.removeAll { $0.isChecked }
        persist()
        Task {
            for item in toDelete { await supabaseDelete(id: item.id) }
        }
    }

    func clearAll() {
        items.removeAll()
        persist()
        Task { await supabaseDeleteAll() }
    }

    // MARK: - Persistence
    private let storageKey = "hb_groceryItems"

    init() {
        load()
        Task { await loadFromSupabase() }
    }

    private func load() {
        guard let data    = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([GroceryItem].self, from: data)
        else { return }
        items = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
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
            var query = supabase.from("grocery_items").select()
            if let hid = cachedHouseholdID {
                query = query.eq("household_id", value: hid.uuidString)
            } else {
                query = query.eq("created_by", value: uid.uuidString)
            }
            let rows: [SupabaseGroceryRow] = try await query.execute().value
            items = rows.map { $0.toItem() }
            persist()
        } catch {
            print("[Supabase] fetch grocery_items error: \(error)")
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

    private func supabaseUpsert(_ item: GroceryItem) async {
        await resolveIDs()
        guard let uid = cachedUserID else { return }
        let row = SupabaseGroceryRow(from: item, userId: uid, householdId: cachedHouseholdID)
        do {
            try await supabase.from("grocery_items").upsert(row, onConflict: "id").execute()
        } catch {
            print("[Supabase] upsert grocery_item error: \(error)")
        }
    }

    private func supabaseDelete(id: UUID) async {
        do {
            try await supabase.from("grocery_items").delete()
                .eq("id", value: id.uuidString).execute()
        } catch {
            print("[Supabase] delete grocery_item error: \(error)")
        }
    }

    private func supabaseDeleteAll() async {
        await resolveIDs()
        guard let uid = cachedUserID else { return }
        do {
            if let hid = cachedHouseholdID {
                try await supabase.from("grocery_items").delete()
                    .eq("household_id", value: hid.uuidString).execute()
            } else {
                try await supabase.from("grocery_items").delete()
                    .eq("created_by", value: uid.uuidString).execute()
            }
        } catch {
            print("[Supabase] delete all grocery_items error: \(error)")
        }
    }
}

// MARK: - Supabase row mapping
private struct SupabaseGroceryRow: Codable {
    let id:           UUID
    let householdId:  UUID?
    var name:         String
    var quantity:     String
    var unit:         String
    var category:     String
    var isChecked:    Bool
    var sourceMealId: UUID?
    let createdBy:    UUID

    enum CodingKeys: String, CodingKey {
        case id
        case householdId  = "household_id"
        case name
        case quantity
        case unit
        case category
        case isChecked    = "is_checked"
        case sourceMealId = "source_meal_id"
        case createdBy    = "created_by"
    }

    init(from item: GroceryItem, userId: UUID, householdId: UUID?) {
        id               = item.id
        createdBy        = userId
        self.householdId = householdId
        name             = item.name
        quantity         = item.quantity
        unit             = item.unit
        category         = item.category.rawValue
        isChecked        = item.isChecked
        sourceMealId     = item.sourceMealID
    }

    func toItem() -> GroceryItem {
        GroceryItem(
            id:           id,
            name:         name,
            quantity:     quantity,
            unit:         unit,
            category:     GroceryItem.GroceryCategory(rawValue: category) ?? .other,
            isChecked:    isChecked,
            sourceMealID: sourceMealId
        )
    }
}
