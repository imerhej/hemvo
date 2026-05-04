//  MaintenanceViewModel.swift
//  Hemvo
//  Active tasks + history. Completing a task moves it to history and reschedules.
//  Supabase `maintenance_items` table:
//    id, household_id, title, area, frequency, last_completed, next_due,
//    notes, estimated_minutes, assigned_member_id, created_by, created_at

internal import SwiftUI
internal import Combine
internal import Supabase

@MainActor
final class MaintenanceViewModel: ObservableObject {

    @Published var items:   [MaintenanceItem] = []   // active tasks
    @Published var history: [CompletedTask]   = []   // completed history (local only)

    private var cachedUserID:      UUID?
    private var cachedHouseholdID: UUID?
    private var deletedItemIDs:    Set<UUID> = []

    // MARK: - Ownership check
    func canDelete(_ item: MaintenanceItem) -> Bool {
        guard let uid = cachedUserID else { return false }
        return item.createdBy == uid.uuidString
    }

    // MARK: - Active computed
    var overdueItems:  [MaintenanceItem] { items.filter { $0.isOverdue  }.sorted { $0.nextDue < $1.nextDue } }
    var dueSoonItems:  [MaintenanceItem] { items.filter { $0.isDueSoon  }.sorted { $0.nextDue < $1.nextDue } }
    var upToDateItems: [MaintenanceItem] { items.filter { $0.isUpToDate }.sorted { $0.nextDue < $1.nextDue } }

    func items(for area: MaintenanceItem.HomeArea) -> [MaintenanceItem] {
        items.filter { $0.area == area }
    }

    private let notif = NotificationService.shared

    // MARK: - Active CRUD
    func addItem(_ item: MaintenanceItem) {
        var stamped = item
        if stamped.createdBy == nil { stamped.createdBy = cachedUserID?.uuidString }
        items.append(stamped)
        persist()
        if UserDefaults.standard.bool(forKey: "notif_maintenance") {
            notif.scheduleMaintenanceReminder(for: stamped)
        }
        Task { await supabaseUpsert(stamped) }
    }

    func updateItem(_ item: MaintenanceItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        persist()
        notif.cancelMaintenanceReminder(for: item.id)
        if UserDefaults.standard.bool(forKey: "notif_maintenance") {
            notif.scheduleMaintenanceReminder(for: item)
        }
        Task { await supabaseUpsert(item) }
    }

    func markComplete(_ item: MaintenanceItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        deletedItemIDs.insert(item.id)
        persistDeletedIDs()
        let completed = CompletedTask(
            id:               UUID(),
            originalID:       item.id,
            title:            item.title,
            area:             item.area,
            frequency:        item.frequency,
            estimatedMinutes: item.estimatedMinutes,
            notes:            item.notes,
            completedDate:    Date(),
            nextDue:          item.nextDue
        )
        history.insert(completed, at: 0)
        items.remove(at: idx)
        persist()
        notif.cancelMaintenanceReminder(for: item.id)
        // Update is_complete = true instead of deleting so the row stays in Supabase
        // for history and the active-tasks query (is_complete = false) won't return it.
        Task {
            await supabaseMarkComplete(id: item.id)
            deletedItemIDs.remove(item.id)
            persistDeletedIDs()
        }
    }

    func deleteItem(_ item: MaintenanceItem) {
        guard canDelete(item) else { return }
        deletedItemIDs.insert(item.id)
        persistDeletedIDs()
        items.removeAll { $0.id == item.id }
        persist()
        notif.cancelMaintenanceReminder(for: item.id)
        Task { await supabaseDelete(id: item.id) }
    }

    func deleteItems(at offsets: IndexSet, in source: [MaintenanceItem]) {
        offsets.map { source[$0] }.filter { canDelete($0) }.forEach { deleteItem($0) }
    }

    // MARK: - History CRUD (local only)
    func updateHistory(_ task: CompletedTask) {
        guard let idx = history.firstIndex(where: { $0.id == task.id }) else { return }
        history[idx] = task; persist()
    }

    func deleteHistory(_ task: CompletedTask) {
        history.removeAll { $0.id == task.id }; persist()
    }

    func seedDefaultsIfNeeded() { }

    // MARK: - Persistence
    private let activeKey         = "hb_maintenanceItems"
    private let historyKey        = "hb_maintenanceHistory"
    private let deletedItemIDsKey = "hb_deletedMaintenanceIDs"

    init() {
        loadDeletedIDs()
        load()
        if UserDefaults.standard.bool(forKey: "notif_maintenance") {
            notif.scheduleMaintenanceReminders(for: items)
        }
        Task { await loadFromSupabase() }
    }

    private func load() {
        if let d = UserDefaults.standard.data(forKey: activeKey),
           let v = try? JSONDecoder().decode([MaintenanceItem].self, from: d) { items = v }
        if let d = UserDefaults.standard.data(forKey: historyKey),
           let v = try? JSONDecoder().decode([CompletedTask].self, from: d) { history = v }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(items)   { UserDefaults.standard.set(d, forKey: activeKey) }
        if let d = try? JSONEncoder().encode(history) { UserDefaults.standard.set(d, forKey: historyKey) }
    }

    private func loadDeletedIDs() {
        guard let d = UserDefaults.standard.data(forKey: deletedItemIDsKey),
              let v = try? JSONDecoder().decode([UUID].self, from: d) else { return }
        deletedItemIDs = Set(v)
    }

    private func persistDeletedIDs() {
        if let d = try? JSONEncoder().encode(Array(deletedItemIDs)) {
            UserDefaults.standard.set(d, forKey: deletedItemIDsKey)
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
            var query = supabase.from("house_tasks").select()
            if let hid = cachedHouseholdID {
                query = query.eq("household_id", value: hid.uuidString).eq("is_complete", value: false)
            } else {
                query = query.eq("created_by", value: uid.uuidString).eq("is_complete", value: false)
            }
            let rows: [SupabaseHouseTaskRow] = try await query.execute().value

            // Re-fire delete for tombstoned items still present remotely.
            let staleRows = rows.filter { deletedItemIDs.contains($0.id) }
            for row in staleRows { Task { await supabaseDelete(id: row.id) } }

            let historyIDs = Set(history.map { $0.originalID })
            let remoteItems = rows.map { $0.toItem() }
                .filter { !deletedItemIDs.contains($0.id) && !historyIDs.contains($0.id) }
            let remoteIDs = Set(remoteItems.map { $0.id })
            let pendingLocal = items.filter { !remoteIDs.contains($0.id) && !deletedItemIDs.contains($0.id) }
            items = remoteItems + pendingLocal
            persist()
            if UserDefaults.standard.bool(forKey: "notif_maintenance") {
                notif.scheduleMaintenanceReminders(for: items)
            }
            for i in pendingLocal { Task { await supabaseUpsert(i) } }
        } catch {
            print("[Supabase] fetch maintenance_items error: \(error)")
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

    private func supabaseUpsert(_ item: MaintenanceItem) async {
        await resolveIDs()
        guard let uid = cachedUserID, let hid = cachedHouseholdID else { return }
        let row = SupabaseHouseTaskRow(from: item, userId: uid, householdId: hid)
        do {
            try await supabase.from("house_tasks").upsert(row, onConflict: "id").execute()
        } catch {
            print("[Supabase] upsert house_task error: \(error)")
        }
    }

    private func supabaseMarkComplete(id: UUID) async {
        struct Completion: Encodable {
            let isComplete: Bool
            let completedDate: Date
            enum CodingKeys: String, CodingKey {
                case isComplete   = "is_complete"
                case completedDate = "completed_date"
            }
        }
        do {
            try await supabase.from("house_tasks")
                .update(Completion(isComplete: true, completedDate: Date()))
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            print("[Supabase] markComplete house_task error: \(error)")
        }
    }

    private func supabaseDelete(id: UUID) async {
        do {
            try await supabase.from("house_tasks").delete()
                .eq("id", value: id.uuidString).execute()
            deletedItemIDs.remove(id)
            persistDeletedIDs()
        } catch {
            print("[Supabase] delete house_task error: \(error)")
        }
    }
}

// MARK: - CompletedTask model
struct CompletedTask: Codable, Identifiable {
    var id:               UUID
    var originalID:       UUID
    var title:            String
    var area:             MaintenanceItem.HomeArea
    var frequency:        MaintenanceItem.Frequency
    var estimatedMinutes: Int
    var notes:            String
    var completedDate:    Date
    var nextDue:          Date
}

// MARK: - Supabase row mapping (house_tasks table)
private struct SupabaseHouseTaskRow: Codable {
    let id:             UUID
    let householdId:    UUID
    var title:          String
    var assignedToId:   UUID?
    var dueDate:        Date
    var isComplete:     Bool
    var priority:       String
    var notes:          String
    var completedDate:  Date?
    let createdBy:      UUID

    enum CodingKeys: String, CodingKey {
        case id
        case householdId   = "household_id"
        case title
        case assignedToId  = "assigned_to_id"
        case dueDate       = "due_date"
        case isComplete    = "is_complete"
        case priority
        case notes
        case completedDate = "completed_date"
        case createdBy     = "created_by"
    }

    init(from item: MaintenanceItem, userId: UUID, householdId: UUID) {
        id               = item.id
        createdBy        = userId
        self.householdId = householdId
        title            = item.title
        assignedToId     = item.assignedMemberID.flatMap { UUID(uuidString: $0) }
        dueDate          = item.nextDue
        isComplete       = false
        priority         = item.isOverdue ? "high" : (item.isDueSoon ? "medium" : "low")
        notes            = item.notes
        completedDate    = item.lastCompleted
    }

    func toItem() -> MaintenanceItem {
        MaintenanceItem(
            id:               id,
            title:            title,
            lastCompleted:    completedDate,
            nextDue:          dueDate,
            notes:            notes,
            assignedMemberID: assignedToId?.uuidString,
            createdBy:        createdBy.uuidString
        )
    }
}
