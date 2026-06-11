//  GroceryViewModel.swift
//  Hemvo
//  Manages grocery list — combines auto-generated items from meals and manual entries.
//  Checked items persist until explicitly deleted.
//  Supabase `grocery_items` table:
//    id, household_id, name, quantity, unit, category, is_checked,
//    source_meal_id, created_by, created_at

internal import SwiftUI
internal import Foundation
internal import Combine
internal import OSLog
internal import Supabase

@MainActor
final class GroceryViewModel: ObservableObject {

    @Published var items: [GroceryItem] = []

    private var cachedUserID:              UUID?
    private var cachedHouseholdID:         UUID?
    private var deletedIDs:                Set<UUID>   = []
    private var deletedMealIngredientNames: Set<String> = []

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

    // MARK: - Role-based write access
    private var hasWriteAccess: Bool {
        guard let uid = cachedUserID else { return false }
        if let role = HouseholdService.shared.household?.members.first(where: { $0.id == uid.uuidString })?.role {
            return role.canWrite
        }
        return true // solo user (no household) — full control
    }

    // MARK: - Ownership check
    func canDelete(id: UUID) -> Bool {
        guard cachedUserID != nil,
              items.first(where: { $0.id == id }) != nil else { return false }
        return hasWriteAccess
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
                // Skip if the user explicitly deleted this ingredient.
                guard !deletedMealIngredientNames.contains(key),
                      !deletedIDs.contains(ing.id) else { continue }
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
        var stamped = item
        if stamped.createdBy == nil { stamped.createdBy = cachedUserID?.uuidString }
        items.append(stamped)
        persist()
        Task { await supabaseUpsert(stamped) }
    }

    func toggleItem(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isChecked.toggle()
            persist()
            Task { await supabaseUpsert(items[idx]) }
        }
    }

    func deleteItem(id: UUID) {
        guard canDelete(id: id) else { return }
        guard let item = items.first(where: { $0.id == id }) else { return }
        deletedIDs.insert(item.id)
        if item.sourceMealID != nil {
            deletedMealIngredientNames.insert(item.name.lowercased())
            persistDeletedMealNames()
        }
        persistDeletedIDs()
        items.removeAll { $0.id == id }
        persist()
        Task { await supabaseDelete(id: item.id) }
    }

    func clearChecked() {
        let toDelete = checkedItems.filter { canDelete(id: $0.id) }
        for item in toDelete {
            deletedIDs.insert(item.id)
            if item.sourceMealID != nil {
                deletedMealIngredientNames.insert(item.name.lowercased())
            }
        }
        persistDeletedIDs()
        persistDeletedMealNames()
        items.removeAll { $0.isChecked && canDelete(id: $0.id) }
        persist()
        Task {
            for item in toDelete { await supabaseDelete(id: item.id) }
        }
    }

    func clearAll() {
        for item in items {
            deletedIDs.insert(item.id)
            if item.sourceMealID != nil {
                deletedMealIngredientNames.insert(item.name.lowercased())
            }
        }
        persistDeletedIDs()
        persistDeletedMealNames()
        items.removeAll()
        persist()
        Task { await supabaseDeleteAll() }
    }

    // MARK: - Persistence
    private let storageKey        = "hb_groceryItems"
    private let deletedIDsKey     = "hb_groceryDeletedIDs"
    private let deletedMealNamesKey = "hb_groceryDeletedMealNames"

    init() {
        loadDeletedIDs()
        loadDeletedMealNames()
        load()
        // Synchronously pre-populate from local household so adds that happen
        // before loadFromSupabase completes don't silently drop their data.
        if let hid = HouseholdService.shared.household?.id {
            cachedHouseholdID = UUID(uuidString: hid)
        }
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

    private func loadDeletedIDs() {
        guard let data = UserDefaults.standard.data(forKey: deletedIDsKey),
              let ids  = try? JSONDecoder().decode([UUID].self, from: data)
        else { return }
        deletedIDs = Set(ids)
    }

    private func persistDeletedIDs() {
        if let data = try? JSONEncoder().encode(Array(deletedIDs)) {
            UserDefaults.standard.set(data, forKey: deletedIDsKey)
        }
    }

    private func loadDeletedMealNames() {
        guard let data  = UserDefaults.standard.data(forKey: deletedMealNamesKey),
              let names = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        deletedMealIngredientNames = Set(names)
    }

    private func persistDeletedMealNames() {
        if let data = try? JSONEncoder().encode(Array(deletedMealIngredientNames)) {
            UserDefaults.standard.set(data, forKey: deletedMealNamesKey)
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
            var query = supabase.from("grocery_items").select()
            if let hid = cachedHouseholdID {
                query = query.eq("household_id", value: hid.uuidString)
            } else {
                query = query.eq("created_by", value: uid.uuidString)
            }
            let rows: [SupabaseGroceryRow] = try await query.execute().value

            // Re-fire delete for any rows that are in the tombstone set but
            // still present remotely (e.g. a previous delete was blocked by RLS).
            let staleRows = rows.filter { deletedIDs.contains($0.id) }
            for row in staleRows { Task { await supabaseDelete(id: row.id) } }

            // Expire tombstones for IDs confirmed absent from remote — safe to
            // clear only now, since Supabase delete() doesn't error on RLS blocks.
            let remoteIDSet = Set(rows.map { $0.id })
            let confirmedGone = deletedIDs.filter { !remoteIDSet.contains($0) }
            if !confirmedGone.isEmpty {
                deletedIDs.subtract(confirmedGone)
                persistDeletedIDs()
            }

            let remoteItems = rows.filter { !deletedIDs.contains($0.id) }.map { $0.toItem() }
            let remoteIDs   = Set(remoteItems.map { $0.id })
            let pendingLocal = items.filter { !remoteIDs.contains($0.id) && !deletedIDs.contains($0.id) }
            items = remoteItems + pendingLocal
            persist()
            for i in pendingLocal { Task { await supabaseUpsert(i) } }
        } catch {
            Logger.grocery.error("fetch grocery_items error: \(error.localizedDescription)")
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

    private func supabaseUpsert(_ item: GroceryItem) async {
        await resolveIDs()
        guard let uid = cachedUserID, let hid = cachedHouseholdID else {
            Logger.grocery.debug("upsert skipped — IDs not resolved")
            return
        }
        let row = SupabaseGroceryRow(from: item, userId: uid, householdId: hid)
        do {
            try await supabase.from("grocery_items").upsert(row, onConflict: "id").execute()
        } catch {
            Logger.grocery.error("upsert grocery_item error: \(error.localizedDescription)")
        }
    }

    private func supabaseDelete(id: UUID) async {
        do {
            try await supabase.from("grocery_items").delete()
                .eq("id", value: id.uuidString).execute()
            // Tombstone stays in deletedIDs until loadFromSupabase confirms
            // the row is gone — Supabase returns "success" even when RLS
            // silently blocks the delete, so clearing here is premature.
        } catch {
            Logger.grocery.error("delete grocery_item error: \(error.localizedDescription)")
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
            deletedIDs.removeAll()
            persistDeletedIDs()
            deletedMealIngredientNames.removeAll()
            persistDeletedMealNames()
        } catch {
            Logger.grocery.error("delete all grocery_items error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Supabase row mapping
private struct SupabaseGroceryRow: Codable {
    let id:           UUID
    let householdId:  UUID         // NOT NULL in DB
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

    init(from item: GroceryItem, userId: UUID, householdId: UUID) {
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
            sourceMealID: sourceMealId,
            createdBy:    createdBy.uuidString
        )
    }
}
