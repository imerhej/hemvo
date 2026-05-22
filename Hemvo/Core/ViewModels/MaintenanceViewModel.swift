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
    @Published var history: [CompletedTask]   = []   // completed history (synced via Supabase)

    private var cachedUserID:      UUID?
    private var cachedHouseholdID: UUID?
    private var deletedItemIDs:    Set<UUID> = []
    private var pendingUploadIDs:  Set<UUID> = []

    private var realtimeTask:     Task<Void, Never>?
    private var realtimeDebounce: Task<Void, Never>?
    private var realtimeChannel:  RealtimeChannelV2?

    // MARK: - Role-based write access
    private var hasWriteAccess: Bool {
        guard let uid = cachedUserID else { return false }
        if let role = HouseholdService.shared.household?.members.first(where: { $0.id == uid.uuidString })?.role {
            return role.canWrite
        }
        return true // solo user (no household) — full control
    }

    // MARK: - Ownership checks
    func canDelete(_ item: MaintenanceItem) -> Bool {
        hasWriteAccess
    }

    func canMarkComplete(_ item: MaintenanceItem) -> Bool {
        guard let uid = cachedUserID else { return false }
        let uidStr = uid.uuidString
        return item.createdBy == uidStr || item.assignedMemberIDs.contains(uidStr)
    }

    func canDeleteHistory(_ task: CompletedTask) -> Bool {
        hasWriteAccess
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
        pendingUploadIDs.insert(stamped.id)
        persistPendingUploadIDs()
        persist()
        if UserPreferences.shared.notifMaintenance {
            notif.scheduleMaintenanceReminder(for: stamped)
        }
        Task { await supabaseUpsert(stamped) }
        Task { await sendItemCreationPush(for: stamped) }
    }

    private func sendItemCreationPush(for item: MaintenanceItem) async {
        let dateStr  = item.nextDue.formatted(.dateTime.month().day())
        let taskWord = item.difficulty == .hard ? "Maintenance Task" : "Chore"
        let icon     = item.difficulty == .hard ? "🔧" : "🧹"
        if item.assignedMemberIDs.isEmpty {
            await PushNotificationService.shared.notifyHouseholdFiltered(
                permission: \.receiveMaintenanceAlerts,
                title: "\(icon) New \(taskWord)",
                body: "\(item.title) · Due \(dateStr)"
            )
        } else {
            let uuids = item.assignedMemberIDs.compactMap { UUID(uuidString: $0) }
            await PushNotificationService.shared.notifyUsers(
                uuids,
                title: "\(icon) \(taskWord) Assigned",
                body: "\(item.title) · Due \(dateStr)"
            )
        }
    }

    func updateItem(_ item: MaintenanceItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let previous = items[idx]
        items[idx] = item
        persist()
        notif.cancelMaintenanceReminder(for: item.id)
        if UserPreferences.shared.notifMaintenance {
            notif.scheduleMaintenanceReminder(for: item)
        }
        let addedIDs = Set(item.assignedMemberIDs).subtracting(Set(previous.assignedMemberIDs))
        if !addedIDs.isEmpty {
            let uuids    = addedIDs.compactMap { UUID(uuidString: $0) }
            let taskWord = item.difficulty == .hard ? "Maintenance Task" : "Chore"
            let icon     = item.difficulty == .hard ? "🔧" : "🧹"
            Task {
                await PushNotificationService.shared.notifyUsers(
                    uuids,
                    title: "\(icon) \(taskWord) Assigned to You",
                    body: "\"\(item.title)\" has been assigned to you."
                )
            }
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
            nextDue:          item.nextDue,
            createdBy:        item.createdBy
        )
        history.insert(completed, at: 0)
        items.remove(at: idx)
        persist()
        notif.cancelMaintenanceReminder(for: item.id)
        // Update is_complete = true instead of deleting so the row stays in Supabase
        // for history and the active-tasks query (is_complete = false) won't return it.
        Task { await supabaseMarkComplete(id: item.id) }
        // Tombstone cleared in loadFromSupabase once is_complete=true rows
        // stop appearing in the is_complete=false query.
    }

    func deleteItem(_ item: MaintenanceItem) {
        guard canDelete(item) else { return }
        deletedItemIDs.insert(item.id)
        pendingUploadIDs.remove(item.id)
        persistDeletedIDs()
        persistPendingUploadIDs()
        items.removeAll { $0.id == item.id }
        persist()
        notif.cancelMaintenanceReminder(for: item.id)
        Task { await supabaseDelete(id: item.id) }
    }

    func deleteItems(at offsets: IndexSet, in source: [MaintenanceItem]) {
        offsets.map { source[$0] }.filter { canDelete($0) }.forEach { deleteItem($0) }
    }

    // MARK: - History CRUD
    func updateHistory(_ task: CompletedTask) {
        guard let idx = history.firstIndex(where: { $0.id == task.id }) else { return }
        history[idx] = task; persist()
    }

    func deleteHistory(_ task: CompletedTask) {
        history.removeAll { $0.id == task.id }
        persist()
        // Tombstone prevents the row from being re-added during sync before the
        // Supabase delete propagates. Cleared in loadFromSupabase once the row
        // is confirmed absent from both active and completed queries.
        deletedItemIDs.insert(task.originalID)
        persistDeletedIDs()
        Task { await supabaseDelete(id: task.originalID) }
    }

    deinit {
        realtimeTask?.cancel()
        realtimeDebounce?.cancel()
        if let ch = realtimeChannel {
            Task { await supabase.realtimeV2.removeChannel(ch) }
        }
    }

    func seedDefaultsIfNeeded() { }

    // MARK: - Persistence
    private let activeKey            = "hb_maintenanceItems"
    private let historyKey           = "hb_maintenanceHistory"
    private let deletedItemIDsKey    = "hb_deletedMaintenanceIDs"
    private let pendingUploadIDsKey  = "hb_pendingUploadMaintenanceIDs"

    init() {
        loadDeletedIDs()
        loadPendingUploadIDs()
        load()
        if UserPreferences.shared.notifMaintenance {
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

    private func loadPendingUploadIDs() {
        guard let d = UserDefaults.standard.data(forKey: pendingUploadIDsKey),
              let v = try? JSONDecoder().decode([UUID].self, from: d) else { return }
        pendingUploadIDs = Set(v)
    }

    private func persistPendingUploadIDs() {
        if let d = try? JSONEncoder().encode(Array(pendingUploadIDs)) {
            UserDefaults.standard.set(d, forKey: pendingUploadIDsKey)
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

        if realtimeTask == nil, cachedHouseholdID != nil {
            startRealtimeSubscription()
        }

        do {
            // ── Build scoped queries ───────────────────────────────────────
            var activeQuery    = supabase.from("house_tasks").select()
            var completedQuery = supabase.from("house_tasks").select()
            if let hid = cachedHouseholdID {
                activeQuery    = activeQuery.eq("household_id", value: hid.uuidString)
                    .eq("is_complete", value: false)
                completedQuery = completedQuery.eq("household_id", value: hid.uuidString)
                    .eq("is_complete", value: true)
            } else {
                activeQuery    = activeQuery.eq("created_by", value: uid.uuidString)
                    .eq("is_complete", value: false)
                completedQuery = completedQuery.eq("created_by", value: uid.uuidString)
                    .eq("is_complete", value: true)
            }

            let rows:          [SupabaseHouseTaskRow] = try await activeQuery.execute().value
            let completedRows: [SupabaseHouseTaskRow] = try await completedQuery.execute().value
            let completedIDs = Set(completedRows.map { $0.id })

            // ── Clear tombstones confirmed absent from BOTH queries ────────
            // A tombstoned ID that still appears in completedRows hasn't been
            // deleted from Supabase yet — keep the tombstone and retry below.
            let fetchedActiveIDs = Set(rows.map { $0.id })
            let confirmedGone    = deletedItemIDs.filter {
                !fetchedActiveIDs.contains($0) && !completedIDs.contains($0)
            }
            if !confirmedGone.isEmpty {
                confirmedGone.forEach { deletedItemIDs.remove($0) }
                persistDeletedIDs()
            }

            // ── Retry delete for tombstoned rows still present in Supabase ─
            let staleActive    = rows.filter          { deletedItemIDs.contains($0.id) }
            let staleCompleted = completedRows.filter { deletedItemIDs.contains($0.id) }
            for row in staleActive    { Task { await supabaseDelete(id: row.id) } }
            for row in staleCompleted { Task { await supabaseDelete(id: row.id) } }

            // ── Sync completed tasks into history for all household members ─
            // Uses local item data where available so area/frequency/estimatedMinutes
            // are preserved; falls back to DB defaults when the item was never cached.
            let historyOriginalIDs = Set(history.map { $0.originalID })
            let localItemsByID     = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            var historyChanged     = false

            for row in completedRows
                where !historyOriginalIDs.contains(row.id) && !deletedItemIDs.contains(row.id) {
                let ct: CompletedTask
                if let local = localItemsByID[row.id] {
                    ct = CompletedTask(
                        id:               row.id,
                        originalID:       row.id,
                        title:            local.title,
                        area:             local.area,
                        frequency:        local.frequency,
                        estimatedMinutes: local.estimatedMinutes,
                        notes:            local.notes,
                        completedDate:    row.completedDate ?? Date(),
                        nextDue:          local.nextDue,
                        createdBy:        row.createdBy.uuidString
                    )
                } else {
                    ct = CompletedTask(
                        id:               row.id,
                        originalID:       row.id,
                        title:            row.title,
                        area:             .general,
                        frequency:        .monthly,
                        estimatedMinutes: 15,
                        notes:            row.notes,
                        completedDate:    row.completedDate ?? Date(),
                        nextDue:          row.dueDate,
                        createdBy:        row.createdBy.uuidString
                    )
                }
                history.append(ct)
                historyChanged = true
            }

            // ── Remove history entries deleted by another household member ──
            // If a completed row is no longer in Supabase and wasn't tombstoned
            // by this device, it was deleted by someone else — purge it locally.
            let prevCount = history.count
            history.removeAll {
                !completedIDs.contains($0.originalID) && !deletedItemIDs.contains($0.originalID)
            }
            if history.count != prevCount { historyChanged = true }

            if historyChanged {
                history.sort { $0.completedDate > $1.completedDate }
                persist()
            }

            // ── Merge active tasks ─────────────────────────────────────────
            let historyIDs  = Set(history.map { $0.originalID })
            let remoteItems = rows.map { $0.toItem() }
                .filter { !deletedItemIDs.contains($0.id) && !historyIDs.contains($0.id) }
            let remoteIDs   = Set(remoteItems.map { $0.id })
            let pendingLocal = items.filter {
                pendingUploadIDs.contains($0.id) &&
                !remoteIDs.contains($0.id) &&
                !deletedItemIDs.contains($0.id) &&
                !completedIDs.contains($0.id)
            }
            items = remoteItems + pendingLocal
            persist()
            if UserPreferences.shared.notifMaintenance {
                notif.scheduleMaintenanceReminders(for: items)
            }
            for i in pendingLocal { Task { await supabaseUpsert(i) } }
        } catch {
            print("[Supabase] fetch maintenance_items error: \(error)")
        }
    }

    private func startRealtimeSubscription() {
        guard let hid = cachedHouseholdID else { return }

        let channel = supabase.realtimeV2.channel("maintenance:\(hid.uuidString):\(UUID().uuidString)")
        realtimeChannel = channel

        realtimeTask = Task { [weak self, channel] in
            let taskStream = channel.postgresChange(
                AnyAction.self, schema: "public", table: "house_tasks",
                filter: .eq("household_id", value: hid.uuidString.lowercased())
            )

            do {
                try await channel.subscribeWithError()
            } catch {
                print("[Realtime] maintenance subscribe error: \(error)")
                self?.realtimeTask = nil
                return
            }

            for await _ in taskStream {
                guard !Task.isCancelled, let self else { break }
                self.scheduleRealtimeReload()
            }

            if !Task.isCancelled {
                self?.realtimeTask = nil
            }
        }
    }

    private func scheduleRealtimeReload() {
        realtimeDebounce?.cancel()
        realtimeDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.loadFromSupabase()
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
        guard !deletedItemIDs.contains(item.id) else { return }
        await resolveIDs()
        guard let uid = cachedUserID, let hid = cachedHouseholdID else { return }
        let row = SupabaseHouseTaskRow(from: item, userId: uid, householdId: hid)
        do {
            try await supabase.from("house_tasks").upsert(row, onConflict: "id").execute()
            pendingUploadIDs.remove(item.id)
            persistPendingUploadIDs()
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
            // Tombstone cleared in loadFromSupabase once the row is confirmed absent.
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
    var createdBy:        String?
}

// MARK: - Supabase row mapping (house_tasks table)
private struct SupabaseHouseTaskRow: Codable {
    let id:                 UUID
    let householdId:        UUID
    var title:              String
    var assignedToId:       UUID?
    var assignedMemberIds:  [UUID]?
    var dueDate:            Date
    var isComplete:         Bool
    var priority:           String
    var difficulty:         String
    var notes:              String
    var completedDate:      Date?
    let createdBy:          UUID

    enum CodingKeys: String, CodingKey {
        case id
        case householdId        = "household_id"
        case title
        case assignedToId       = "assigned_to_id"
        case assignedMemberIds  = "assigned_member_ids"
        case dueDate            = "due_date"
        case isComplete         = "is_complete"
        case priority
        case difficulty
        case notes
        case completedDate      = "completed_date"
        case createdBy          = "created_by"
    }

    init(from item: MaintenanceItem, userId: UUID, householdId: UUID) {
        id                = item.id
        createdBy         = userId
        self.householdId  = householdId
        title             = item.title
        assignedMemberIds = item.assignedMemberIDs.isEmpty ? nil
                            : item.assignedMemberIDs.compactMap { UUID(uuidString: $0) }
        assignedToId      = item.assignedMemberIDs.first.flatMap { UUID(uuidString: $0) }
        dueDate           = item.nextDue
        isComplete        = false
        priority          = item.isOverdue ? "high" : (item.isDueSoon ? "medium" : "low")
        difficulty        = item.difficulty.rawValue
        notes             = item.notes
        completedDate     = item.lastCompleted
    }

    func toItem() -> MaintenanceItem {
        let memberIDs: [String]
        if let ids = assignedMemberIds, !ids.isEmpty {
            memberIDs = ids.map { $0.uuidString }
        } else if let id = assignedToId {
            memberIDs = [id.uuidString]
        } else {
            memberIDs = []
        }
        return MaintenanceItem(
            id:                id,
            title:             title,
            difficulty:        MaintenanceItem.Difficulty(rawValue: difficulty) ?? .medium,
            lastCompleted:     completedDate,
            nextDue:           dueDate,
            notes:             notes,
            assignedMemberIDs: memberIDs,
            createdBy:         createdBy.uuidString
        )
    }

    func toCompletedTask() -> CompletedTask {
        CompletedTask(
            id:               id,
            originalID:       id,
            title:            title,
            area:             .general,
            frequency:        .monthly,
            estimatedMinutes: 15,
            notes:            notes,
            completedDate:    completedDate ?? Date(),
            nextDue:          dueDate,
            createdBy:        createdBy.uuidString
        )
    }
}
