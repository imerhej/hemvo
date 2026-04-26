//  ShoppingListViewModel.swift
//  Homvi
//  Supabase `shopping_lists` table:
//    id, household_id, name, emoji, created_by, created_at
//  Supabase `shopping_items` table:
//    id, list_id, name, quantity, unit, category, is_checked, note, created_at

internal import SwiftUI
internal import Combine
internal import Supabase

@MainActor
final class ShoppingListViewModel: ObservableObject {

    @Published var lists: [ShoppingList] = []

    private var cachedUserID:      UUID?
    private var cachedHouseholdID: UUID?

    private let key = "hb_shoppingLists"

    init() {
        load()
        Task { await loadFromSupabase() }
    }

    // MARK: - List CRUD
    func addList(name: String, emoji: String) {
        let list = ShoppingList(
            name: name.trimmingCharacters(in: .whitespaces), emoji: emoji)
        lists.insert(list, at: 0)
        persist()
        Task { await supabaseUpsertList(list) }
    }

    func updateList(_ list: ShoppingList) {
        guard let idx = lists.firstIndex(where: { $0.id == list.id }) else { return }
        lists[idx] = list
        persist()
        Task { await supabaseUpsertList(list) }
    }

    func deleteList(_ list: ShoppingList) {
        lists.removeAll { $0.id == list.id }
        persist()
        Task { await supabaseDeleteList(id: list.id) }
    }

    // MARK: - Item CRUD
    func addItem(to listID: UUID, name: String, quantity: String,
                 unit: String, category: ShoppingCategory, note: String) {
        guard let idx = lists.firstIndex(where: { $0.id == listID }) else { return }
        let item = ShoppingItem(
            name: name.trimmingCharacters(in: .whitespaces),
            quantity: quantity, unit: unit, category: category, note: note)
        lists[idx].items.append(item)
        persist()
        Task { await supabaseUpsertItem(item, listID: listID) }
    }

    func updateItem(_ item: ShoppingItem, in listID: UUID) {
        guard let li = lists.firstIndex(where: { $0.id == listID }),
              let ii = lists[li].items.firstIndex(where: { $0.id == item.id })
        else { return }
        lists[li].items[ii] = item
        persist()
        Task { await supabaseUpsertItem(item, listID: listID) }
    }

    func toggleItem(_ item: ShoppingItem, in listID: UUID) {
        guard let li = lists.firstIndex(where: { $0.id == listID }),
              let ii = lists[li].items.firstIndex(where: { $0.id == item.id })
        else { return }
        lists[li].items[ii].isChecked.toggle()
        let updated = lists[li].items[ii]
        persist()
        Task { await supabaseUpsertItem(updated, listID: listID) }
    }

    func deleteItem(_ item: ShoppingItem, from listID: UUID) {
        guard let li = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[li].items.removeAll { $0.id == item.id }
        persist()
        Task { await supabaseDeleteItem(id: item.id) }
    }

    func clearChecked(from listID: UUID) {
        guard let li = lists.firstIndex(where: { $0.id == listID }) else { return }
        let toDelete = lists[li].items.filter { $0.isChecked }
        lists[li].items.removeAll { $0.isChecked }
        persist()
        Task {
            for item in toDelete { await supabaseDeleteItem(id: item.id) }
        }
    }

    func uncheckAll(in listID: UUID) {
        guard let li = lists.firstIndex(where: { $0.id == listID }) else { return }
        for ii in lists[li].items.indices { lists[li].items[ii].isChecked = false }
        let updatedItems = lists[li].items
        persist()
        Task {
            for item in updatedItems { await supabaseUpsertItem(item, listID: listID) }
        }
    }

    // MARK: - Persistence
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ShoppingList].self, from: data)
        else { return }
        lists = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(lists) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Supabase Sync

    func loadFromSupabase() async {
        guard let uid = await AuthService.shared.currentUserID() else { return }
        cachedUserID = uid

        if let profile = try? await AuthService.shared.loadProfile() {
            cachedHouseholdID = profile.householdId
        }

        do {
            // Fetch lists
            var listQuery = supabase.from("shopping_lists").select()
            if let hid = cachedHouseholdID {
                listQuery = listQuery.eq("household_id", value: hid.uuidString)
            } else {
                listQuery = listQuery.eq("created_by", value: uid.uuidString)
            }
            let listRows: [SupabaseListRow] = try await listQuery.execute().value

            guard !listRows.isEmpty else {
                lists = []
                persist()
                return
            }

            // Fetch all items for those lists in one query
            let listIDs = listRows.map { $0.id.uuidString }
            let itemRows: [SupabaseItemRow] = try await supabase
                .from("shopping_items")
                .select()
                .in("list_id", values: listIDs)
                .execute()
                .value

            // Assemble ShoppingList objects
            let itemsByList = Dictionary(grouping: itemRows, by: { $0.listId })
            lists = listRows.map { row in
                var list     = row.toList()
                list.items   = (itemsByList[row.id] ?? []).map { $0.toItem() }
                return list
            }
            persist()
        } catch {
            print("[Supabase] fetch shopping_lists error: \(error)")
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

    private func supabaseUpsertList(_ list: ShoppingList) async {
        await resolveIDs()
        guard let uid = cachedUserID else { return }
        let row = SupabaseListRow(from: list, userId: uid, householdId: cachedHouseholdID)
        do {
            try await supabase.from("shopping_lists").upsert(row, onConflict: "id").execute()
        } catch {
            print("[Supabase] upsert shopping_list error: \(error)")
        }
    }

    private func supabaseDeleteList(id: UUID) async {
        do {
            // Cascade on the FK will delete associated items
            try await supabase.from("shopping_lists").delete()
                .eq("id", value: id.uuidString).execute()
        } catch {
            print("[Supabase] delete shopping_list error: \(error)")
        }
    }

    private func supabaseUpsertItem(_ item: ShoppingItem, listID: UUID) async {
        let row = SupabaseItemRow(from: item, listId: listID)
        do {
            try await supabase.from("shopping_items").upsert(row, onConflict: "id").execute()
        } catch {
            print("[Supabase] upsert shopping_item error: \(error)")
        }
    }

    private func supabaseDeleteItem(id: UUID) async {
        do {
            try await supabase.from("shopping_items").delete()
                .eq("id", value: id.uuidString).execute()
        } catch {
            print("[Supabase] delete shopping_item error: \(error)")
        }
    }
}

// MARK: - List row mapping
private struct SupabaseListRow: Codable {
    let id:          UUID
    let householdId: UUID?
    var name:        String
    var emoji:       String
    let createdBy:   UUID

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case name
        case emoji
        case createdBy   = "created_by"
    }

    init(from list: ShoppingList, userId: UUID, householdId: UUID?) {
        id               = list.id
        createdBy        = userId
        self.householdId = householdId
        name             = list.name
        emoji            = list.emoji
    }

    func toList() -> ShoppingList {
        ShoppingList(id: id, name: name, emoji: emoji)
    }
}

// MARK: - Item row mapping
private struct SupabaseItemRow: Codable {
    let id:        UUID
    let listId:    UUID
    var name:      String
    var quantity:  String
    var unit:      String
    var category:  String
    var isChecked: Bool
    var note:      String

    enum CodingKeys: String, CodingKey {
        case id
        case listId    = "list_id"
        case name
        case quantity
        case unit
        case category
        case isChecked = "is_checked"
        case note
    }

    init(from item: ShoppingItem, listId: UUID) {
        id             = item.id
        self.listId    = listId
        name           = item.name
        quantity       = item.quantity
        unit           = item.unit
        category       = item.category.rawValue
        isChecked      = item.isChecked
        note           = item.note
    }

    func toItem() -> ShoppingItem {
        ShoppingItem(
            id:        id,
            name:      name,
            quantity:  quantity,
            unit:      unit,
            category:  ShoppingCategory(rawValue: category) ?? .other,
            isChecked: isChecked,
            note:      note
        )
    }
}
