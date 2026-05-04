//  ShoppingListViewModel.swift
//  Hemvo
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

    private var deletedListIDs: Set<UUID> = []
    private var deletedItemIDs: Set<UUID> = []

    private let key              = "hb_shoppingLists"
    private let deletedListIDsKey = "hb_deletedShoppingListIDs"
    private let deletedItemIDsKey = "hb_deletedShoppingItemIDs"

    init() {
        loadDeletedIDs()
        load()
        Task { await loadFromSupabase() }
    }

    // MARK: - Ownership check
    func canDelete(_ list: ShoppingList) -> Bool {
        guard let uid = cachedUserID else { return false }
        guard let createdBy = list.createdBy else { return true }
        return createdBy == uid.uuidString
    }

    func canDeleteItem(_ item: ShoppingItem) -> Bool {
        guard let uid = cachedUserID else { return false }
        guard let createdBy = item.createdBy else { return true }
        return createdBy == uid.uuidString
    }

    // MARK: - List CRUD
    func addList(name: String, emoji: String) {
        var list = ShoppingList(
            name: name.trimmingCharacters(in: .whitespaces), emoji: emoji)
        list.createdBy = cachedUserID?.uuidString
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
        guard canDelete(list) else { return }
        deletedListIDs.insert(list.id)
        for item in list.items { deletedItemIDs.insert(item.id) }
        persistDeletedIDs()
        lists.removeAll { $0.id == list.id }
        persist()
        Task { await supabaseDeleteList(id: list.id) }
    }

    // MARK: - Item CRUD
    func addItem(to listID: UUID, name: String, quantity: String,
                 unit: String, category: ShoppingCategory, note: String) {
        guard let idx = lists.firstIndex(where: { $0.id == listID }) else { return }
        var item = ShoppingItem(
            name: name.trimmingCharacters(in: .whitespaces),
            quantity: quantity, unit: unit, category: category, note: note)
        item.createdBy = cachedUserID?.uuidString
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
        guard canDeleteItem(item) else { return }
        guard let li = lists.firstIndex(where: { $0.id == listID }) else { return }
        deletedItemIDs.insert(item.id)
        persistDeletedIDs()
        lists[li].items.removeAll { $0.id == item.id }
        persist()
        Task { await supabaseDeleteItem(id: item.id) }
    }

    func clearChecked(from listID: UUID) {
        guard let li = lists.firstIndex(where: { $0.id == listID }) else { return }
        let toDelete = lists[li].items.filter { $0.isChecked }
        for item in toDelete { deletedItemIDs.insert(item.id) }
        persistDeletedIDs()
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

    private func loadDeletedIDs() {
        if let d = UserDefaults.standard.data(forKey: deletedListIDsKey),
           let v = try? JSONDecoder().decode([UUID].self, from: d) { deletedListIDs = Set(v) }
        if let d = UserDefaults.standard.data(forKey: deletedItemIDsKey),
           let v = try? JSONDecoder().decode([UUID].self, from: d) { deletedItemIDs = Set(v) }
    }

    private func persistDeletedIDs() {
        if let d = try? JSONEncoder().encode(Array(deletedListIDs)) { UserDefaults.standard.set(d, forKey: deletedListIDsKey) }
        if let d = try? JSONEncoder().encode(Array(deletedItemIDs)) { UserDefaults.standard.set(d, forKey: deletedItemIDsKey) }
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
            // Fetch lists
            var listQuery = supabase.from("shopping_lists").select()
            if let hid = cachedHouseholdID {
                listQuery = listQuery.eq("household_id", value: hid.uuidString)
            } else {
                listQuery = listQuery.eq("created_by", value: uid.uuidString)
            }
            let listRows: [SupabaseListRow] = try await listQuery.execute().value

            // Re-fire delete for tombstoned lists still present remotely.
            let staleListRows = listRows.filter { deletedListIDs.contains($0.id) }
            for row in staleListRows { Task { await supabaseDeleteList(id: row.id) } }

            let validListRows = listRows.filter { !deletedListIDs.contains($0.id) }

            guard !validListRows.isEmpty else {
                lists = []
                persist()
                return
            }

            // Fetch all items for those lists in one query
            let listIDs = validListRows.map { $0.id.uuidString }
            let itemRows: [SupabaseItemRow] = try await supabase
                .from("shopping_items")
                .select()
                .in("list_id", values: listIDs)
                .execute()
                .value

            // Re-fire delete for tombstoned items still present remotely.
            let staleItemRows = itemRows.filter { deletedItemIDs.contains($0.id) }
            for row in staleItemRows { Task { await supabaseDeleteItem(id: row.id) } }

            // Assemble ShoppingList objects, excluding tombstoned items.
            let validItemRows = itemRows.filter { !deletedItemIDs.contains($0.id) }
            let itemsByList = Dictionary(grouping: validItemRows, by: { $0.listId })
            lists = validListRows.map { row in
                var list   = row.toList()
                list.items = (itemsByList[row.id] ?? []).map { $0.toItem() }
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
        if cachedHouseholdID == nil {
            cachedHouseholdID = (try? await AuthService.shared.loadProfile())?.householdId
                ?? UUID(uuidString: HouseholdService.shared.household?.id ?? "")
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
            deletedListIDs.remove(id)
            persistDeletedIDs()
        } catch {
            print("[Supabase] delete shopping_list error: \(error)")
        }
    }

    private func supabaseUpsertItem(_ item: ShoppingItem, listID: UUID) async {
        await resolveIDs()
        guard let uid = cachedUserID, let hid = cachedHouseholdID else { return }
        let row = SupabaseItemRow(from: item, listId: listID, householdId: hid, createdBy: uid)
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
            deletedItemIDs.remove(id)
            persistDeletedIDs()
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
        var list = ShoppingList(id: id, name: name, emoji: emoji)
        list.createdBy = createdBy.uuidString
        return list
    }
}

// MARK: - Item row mapping
private struct SupabaseItemRow: Codable {
    let id:          UUID
    let listId:      UUID
    let householdId: UUID         // NOT NULL in DB
    var name:        String
    var quantity:    String
    var unit:        String
    var category:    String
    var isChecked:   Bool
    var note:        String
    let createdBy:   UUID

    enum CodingKeys: String, CodingKey {
        case id
        case listId      = "list_id"
        case householdId = "household_id"
        case name
        case quantity
        case unit
        case category
        case isChecked   = "is_checked"
        case note
        case createdBy   = "created_by"
    }

    init(from item: ShoppingItem, listId: UUID, householdId: UUID, createdBy: UUID) {
        id               = item.id
        self.listId      = listId
        self.householdId = householdId
        self.createdBy   = createdBy
        name             = item.name
        quantity         = item.quantity
        unit             = item.unit
        category         = item.category.rawValue
        isChecked        = item.isChecked
        note             = item.note
    }

    func toItem() -> ShoppingItem {
        var item = ShoppingItem(
            id:        id,
            name:      name,
            quantity:  quantity,
            unit:      unit,
            category:  ShoppingCategory(rawValue: category) ?? .other,
            isChecked: isChecked,
            note:      note
        )
        item.createdBy = createdBy.uuidString
        return item
    }
}
