//  MaintenanceViewModel.swift
//  Homvi
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
        items.append(item)
        persist()
        if UserDefaults.standard.bool(forKey: "notif_maintenance") {
            notif.scheduleMaintenanceReminder(for: item)
        }
        Task { await supabaseUpsert(item) }
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
        Task { await supabaseDelete(id: item.id) }
    }

    func deleteItem(_ item: MaintenanceItem) {
        items.removeAll { $0.id == item.id }
        persist()
        notif.cancelMaintenanceReminder(for: item.id)
        Task { await supabaseDelete(id: item.id) }
    }

    func deleteItems(at offsets: IndexSet, in source: [MaintenanceItem]) {
        offsets.forEach { deleteItem(source[$0]) }
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
    private let activeKey  = "hb_maintenanceItems"
    private let historyKey = "hb_maintenanceHistory"

    init() {
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

    // MARK: - Supabase Sync

    func loadFromSupabase() async {
        guard let uid = await AuthService.shared.currentUserID() else { return }
        cachedUserID = uid

        if let profile = try? await AuthService.shared.loadProfile() {
            cachedHouseholdID = profile.householdId
        }

        do {
            var query = supabase.from("maintenance_items").select()
            if let hid = cachedHouseholdID {
                query = query.eq("household_id", value: hid.uuidString)
            } else {
                query = query.eq("created_by", value: uid.uuidString)
            }
            let rows: [SupabaseMaintenanceRow] = try await query.execute().value
            items = rows.map { $0.toItem() }
            persist()
            if UserDefaults.standard.bool(forKey: "notif_maintenance") {
                notif.scheduleMaintenanceReminders(for: items)
            }
        } catch {
            print("[Supabase] fetch maintenance_items error: \(error)")
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

    private func supabaseUpsert(_ item: MaintenanceItem) async {
        await resolveIDs()
        guard let uid = cachedUserID else { return }
        let row = SupabaseMaintenanceRow(from: item, userId: uid, householdId: cachedHouseholdID)
        do {
            try await supabase.from("maintenance_items").upsert(row, onConflict: "id").execute()
        } catch {
            print("[Supabase] upsert maintenance_item error: \(error)")
        }
    }

    private func supabaseDelete(id: UUID) async {
        do {
            try await supabase.from("maintenance_items").delete()
                .eq("id", value: id.uuidString).execute()
        } catch {
            print("[Supabase] delete maintenance_item error: \(error)")
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

// MARK: - Supabase row mapping
private struct SupabaseMaintenanceRow: Codable {
    let id:               UUID
    let householdId:      UUID?
    var title:            String
    var area:             String
    var frequency:        String
    var lastCompleted:    Date?
    var nextDue:          Date
    var notes:            String
    var estimatedMinutes: Int
    var assignedMemberID: String?
    let createdBy:        UUID

    enum CodingKeys: String, CodingKey {
        case id
        case householdId      = "household_id"
        case title
        case area
        case frequency
        case lastCompleted    = "last_completed"
        case nextDue          = "next_due"
        case notes
        case estimatedMinutes = "estimated_minutes"
        case assignedMemberID = "assigned_member_id"
        case createdBy        = "created_by"
    }

    init(from item: MaintenanceItem, userId: UUID, householdId: UUID?) {
        id               = item.id
        createdBy        = userId
        self.householdId = householdId
        title            = item.title
        area             = item.area.rawValue
        frequency        = item.frequency.rawValue
        lastCompleted    = item.lastCompleted
        nextDue          = item.nextDue
        notes            = item.notes
        estimatedMinutes = item.estimatedMinutes
        assignedMemberID = item.assignedMemberID
    }

    func toItem() -> MaintenanceItem {
        MaintenanceItem(
            id:               id,
            title:            title,
            area:             MaintenanceItem.HomeArea(rawValue: area) ?? .general,
            frequency:        MaintenanceItem.Frequency(rawValue: frequency) ?? .monthly,
            lastCompleted:    lastCompleted,
            nextDue:          nextDue,
            notes:            notes,
            estimatedMinutes: estimatedMinutes,
            assignedMemberID: assignedMemberID
        )
    }
}
