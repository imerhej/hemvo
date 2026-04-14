//  GroceryViewModel.swift
//  HomeBase
//  Manages grocery list — combines auto-generated items from meals and manual entries.
//  Checked items persist until explicitly deleted.

internal import SwiftUI
internal import Foundation
internal import Combine

@MainActor
final class GroceryViewModel: ObservableObject {

    @Published var items: [GroceryItem] = []

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
    // Preserves isChecked state for any item already in the list (matched by name).
    func syncFromMeals(_ meals: [Meal]) {
        // Build a lookup of existing checked states by item name (lowercased)
        var checkedByName: [String: Bool] = [:]
        for item in items where item.sourceMealID != nil {
            checkedByName[item.name.lowercased()] = item.isChecked
        }

        // Remove auto-generated items
        items.removeAll { $0.sourceMealID != nil }

        // Re-add from meals, restoring checked state if the item existed before
        var seen = Set<String>()
        for meal in meals {
            for ing in meal.ingredients {
                let key = ing.name.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                var item          = ing
                item.sourceMealID = meal.id
                // Restore previously checked state so sync doesn't uncheck items
                item.isChecked    = checkedByName[key] ?? false
                items.append(item)
            }
        }
        persist()
    }

    // MARK: - CRUD
    func addItem(_ item: GroceryItem) {
        items.append(item)
        persist()
    }

    func toggleItem(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isChecked.toggle()
            persist()
        }
    }

    func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func clearChecked() {
        items.removeAll { $0.isChecked }
        persist()
    }

    func clearAll() {
        items.removeAll()
        persist()
    }

    // MARK: - Persistence
    private let storageKey = "hb_groceryItems"

    init() { load() }

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
}
