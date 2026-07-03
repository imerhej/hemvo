//  MaintenanceViewModel.swift
//  Hemvo
//  Active tasks + history. Completing a task moves it to history and reschedules.
//  Supabase `maintenance_items` table:
//    id, household_id, title, area, frequency, last_completed, next_due,
//    notes, estimated_minutes, assigned_member_id, created_by, created_at

internal import SwiftUI
internal import Combine
internal import OSLog
internal import Supabase

@MainActor
final class MaintenanceViewModel: ObservableObject {

    @Published var items:   [MaintenanceItem] = []   // active tasks
    @Published var history: [CompletedTask]   = []   // completed history (synced via Supabase)

    private var cachedUserID:      UUID?
    private var cachedHouseholdID: UUID?
    private var deletedItemIDs:    Set<UUID> = []
    private var pendingUploadIDs:  Set<UUID> = []
    private var deletedCompletionIDs: Set<UUID> = []
    private var pendingCompletionIDs: Set<UUID> = []

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
        let taskWord = item.difficulty == .hard ? "task" : "chore"
        let icon     = item.difficulty == .hard ? "🔧" : "🧹"
        let creator  = HouseholdService.shared.displayName(forUserID: cachedUserID)
        if item.assignedMemberIDs.isEmpty {
            await PushNotificationService.shared.notifyHouseholdFiltered(
                permission: \.receiveMaintenanceAlerts,
                title: "\(icon) \(creator) added a \(taskWord)",
                body: "\(item.title) · Due \(dateStr)"
            )
        } else {
            let uuids = item.assignedMemberIDs.compactMap { UUID(uuidString: $0) }
            await PushNotificationService.shared.notifyUsers(
                uuids,
                title: "\(icon) \(creator) assigned you a \(taskWord)",
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
        Task { await supabaseUpdate(item) }
    }

    // Recurring: logs a completion event and rolls the task's due date forward
    // by one frequency cycle instead of retiring it. Anchored to the due date
    // that was just met (not today) so the cadence stays fixed even if a task
    // is completed early or late.
    func markComplete(_ item: MaintenanceItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let completion = CompletedTask(
            id:               UUID(),
            originalID:       item.id,
            title:            item.title,
            area:             item.area,
            frequency:        item.frequency,
            estimatedMinutes: item.estimatedMinutes,
            notes:            item.notes,
            completedDate:    Date(),
            nextDue:          item.nextDue,
            createdBy:        cachedUserID?.uuidString
        )
        history.insert(completion, at: 0)
        pendingCompletionIDs.insert(completion.id)
        persistPendingCompletionIDs()

        var rolled = item
        rolled.lastCompleted = Date()
        rolled.nextDue = Calendar.current.date(byAdding: .day, value: item.frequency.days, to: item.nextDue) ?? item.nextDue
        items[idx] = rolled
        persist()

        notif.cancelMaintenanceReminder(for: item.id)
        if UserPreferences.shared.notifMaintenance {
            notif.scheduleMaintenanceReminder(for: rolled)
        }

        Task { await supabaseInsertCompletion(completion, taskId: item.id) }
        Task { await supabaseRollTaskForward(rolled) }
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
        // Deletes only this completion log entry — task.originalID may still
        // point at an active recurring task, which must not be touched.
        // Tombstone cleared in loadFromSupabase once the row is confirmed absent.
        deletedCompletionIDs.insert(task.id)
        persistDeletedCompletionIDs()
        Task { await supabaseDeleteCompletion(id: task.id) }
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
    private let activeKey            = "hemvo_maintenanceItems"
    private let historyKey           = "hemvo_maintenanceHistory"
    private let deletedItemIDsKey    = "hemvo_deletedMaintenanceIDs"
    private let pendingUploadIDsKey  = "hemvo_pendingUploadMaintenanceIDs"
    private let deletedCompletionIDsKey = "hemvo_deletedMaintenanceCompletionIDs"
    private let pendingCompletionIDsKey = "hemvo_pendingUploadMaintenanceCompletionIDs"

    init() {
        loadDeletedIDs()
        loadPendingUploadIDs()
        loadDeletedCompletionIDs()
        loadPendingCompletionIDs()
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

    private func loadDeletedCompletionIDs() {
        guard let d = UserDefaults.standard.data(forKey: deletedCompletionIDsKey),
              let v = try? JSONDecoder().decode([UUID].self, from: d) else { return }
        deletedCompletionIDs = Set(v)
    }

    private func persistDeletedCompletionIDs() {
        if let d = try? JSONEncoder().encode(Array(deletedCompletionIDs)) {
            UserDefaults.standard.set(d, forKey: deletedCompletionIDsKey)
        }
    }

    private func loadPendingCompletionIDs() {
        guard let d = UserDefaults.standard.data(forKey: pendingCompletionIDsKey),
              let v = try? JSONDecoder().decode([UUID].self, from: d) else { return }
        pendingCompletionIDs = Set(v)
    }

    private func persistPendingCompletionIDs() {
        if let d = try? JSONEncoder().encode(Array(pendingCompletionIDs)) {
            UserDefaults.standard.set(d, forKey: pendingCompletionIDsKey)
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
            // ── Active tasks: task_type = maintenance, is_complete always false ──
            // (Maintenance never flips is_complete anymore — completion is logged
            // to maintenance_completions instead, see markComplete().)
            var activeQuery = supabase.from("house_tasks").select()
                .eq("task_type", value: "maintenance")
                .eq("is_complete", value: false)
            if let hid = cachedHouseholdID {
                activeQuery = activeQuery.eq("household_id", value: hid.uuidString)
            } else {
                activeQuery = activeQuery.eq("created_by", value: uid.uuidString)
            }
            let rows: [SupabaseHouseTaskRow] = try await activeQuery.execute().value

            // ── Completion log (history) ─────────────────────────────────────
            var completionsQuery = supabase.from("maintenance_completions").select()
            if let hid = cachedHouseholdID {
                completionsQuery = completionsQuery.eq("household_id", value: hid.uuidString)
            } else {
                completionsQuery = completionsQuery.eq("completed_by", value: uid.uuidString)
            }
            let completionRows: [SupabaseCompletionRow] = try await completionsQuery.execute().value

            // ── Clear active-task tombstones confirmed absent remotely ──────
            let fetchedActiveIDs = Set(rows.map { $0.id })
            let confirmedGoneItems = deletedItemIDs.filter { !fetchedActiveIDs.contains($0) }
            if !confirmedGoneItems.isEmpty {
                confirmedGoneItems.forEach { deletedItemIDs.remove($0) }
                persistDeletedIDs()
            }
            let staleActive = rows.filter { deletedItemIDs.contains($0.id) }
            for row in staleActive { Task { await supabaseDelete(id: row.id) } }

            // ── Clear completion tombstones confirmed absent remotely ───────
            let fetchedCompletionIDs = Set(completionRows.map { $0.id })
            let confirmedGoneCompletions = deletedCompletionIDs.filter { !fetchedCompletionIDs.contains($0) }
            if !confirmedGoneCompletions.isEmpty {
                confirmedGoneCompletions.forEach { deletedCompletionIDs.remove($0) }
                persistDeletedCompletionIDs()
            }
            let staleCompletions = completionRows.filter { deletedCompletionIDs.contains($0.id) }
            for row in staleCompletions { Task { await supabaseDeleteCompletion(id: row.id) } }

            // ── Merge history: server truth + not-yet-synced local completions ──
            let remoteHistory = completionRows
                .filter { !deletedCompletionIDs.contains($0.id) }
                .map { $0.toCompletedTask() }
            let remoteHistoryIDs = Set(remoteHistory.map { $0.id })
            let pendingLocalHistory = history.filter {
                pendingCompletionIDs.contains($0.id) &&
                !remoteHistoryIDs.contains($0.id) &&
                !deletedCompletionIDs.contains($0.id)
            }
            history = (remoteHistory + pendingLocalHistory).sorted { $0.completedDate > $1.completedDate }
            persist()
            for h in pendingLocalHistory { Task { await supabaseInsertCompletion(h, taskId: h.originalID) } }

            // ── Merge active tasks ─────────────────────────────────────────
            let remoteItems = rows.map { $0.toItem() }
                .filter { !deletedItemIDs.contains($0.id) }
            let remoteIDs = Set(remoteItems.map { $0.id })
            let pendingLocal = items.filter {
                pendingUploadIDs.contains($0.id) &&
                !remoteIDs.contains($0.id) &&
                !deletedItemIDs.contains($0.id)
            }
            items = remoteItems + pendingLocal
            persist()
            if UserPreferences.shared.notifMaintenance {
                notif.scheduleMaintenanceReminders(for: items)
            }
            for i in pendingLocal { Task { await supabaseUpsert(i) } }
        } catch {
            Logger.maintenance.error("fetch maintenance_items error: \(error.localizedDescription)")
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
                Logger.realtime.error("maintenance subscribe error: \(error.localizedDescription)")
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

    // Plain UPDATE — only hits the UPDATE RLS policy so any household member
    // with write access can edit tasks they didn't create (upsert would fail
    // the INSERT policy's `created_by = auth.uid()` check first).
    private func supabaseUpdate(_ item: MaintenanceItem) async {
        guard !deletedItemIDs.contains(item.id) else { return }
        await resolveIDs()
        guard cachedHouseholdID != nil else { return }

        struct EditPayload: Encodable {
            let title:             String
            let area:              String
            let frequency:         String
            let estimatedMinutes:  Int
            let assignedToId:      UUID?
            let assignedMemberIds: [UUID]?
            let dueDate:           Date
            let priority:          String
            let difficulty:        String
            let notes:             String
            enum CodingKeys: String, CodingKey {
                case title
                case area
                case frequency
                case estimatedMinutes  = "estimated_minutes"
                case assignedToId      = "assigned_to_id"
                case assignedMemberIds = "assigned_member_ids"
                case dueDate           = "due_date"
                case priority
                case difficulty
                case notes
            }
        }

        let payload = EditPayload(
            title:             item.title,
            area:              item.area.rawValue,
            frequency:         item.frequency.rawValue,
            estimatedMinutes:  item.estimatedMinutes,
            assignedToId:      item.assignedMemberIDs.first.flatMap { UUID(uuidString: $0) },
            assignedMemberIds: item.assignedMemberIDs.isEmpty ? nil
                               : item.assignedMemberIDs.compactMap { UUID(uuidString: $0) },
            dueDate:           item.nextDue,
            priority:          item.isOverdue ? "high" : (item.isDueSoon ? "medium" : "low"),
            difficulty:        item.difficulty.rawValue,
            notes:             item.notes
        )
        do {
            try await supabase.from("house_tasks")
                .update(payload)
                .eq("id", value: item.id.uuidString)
                .execute()
        } catch {
            Logger.maintenance.error("update house_task error: \(error.localizedDescription)")
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
            Logger.maintenance.error("upsert house_task error: \(error.localizedDescription)")
        }
    }

    // Bumps due_date (and last_completed) forward on the same row instead of
    // flipping is_complete — the row stays active for the next occurrence.
    private func supabaseRollTaskForward(_ item: MaintenanceItem) async {
        struct RollForward: Encodable {
            let dueDate:       Date
            let completedDate: Date?
            enum CodingKeys: String, CodingKey {
                case dueDate       = "due_date"
                case completedDate = "completed_date"
            }
        }
        do {
            try await supabase.from("house_tasks")
                .update(RollForward(dueDate: item.nextDue, completedDate: item.lastCompleted))
                .eq("id", value: item.id.uuidString)
                .execute()
        } catch {
            Logger.maintenance.error("roll forward house_task error: \(error.localizedDescription)")
        }
    }

    private func supabaseInsertCompletion(_ completion: CompletedTask, taskId: UUID) async {
        guard !deletedCompletionIDs.contains(completion.id) else { return }
        await resolveIDs()
        guard let uid = cachedUserID, let hid = cachedHouseholdID else { return }

        struct CompletionRow: Encodable {
            let id:                 UUID
            let taskId:             UUID
            let householdId:        UUID
            let completedBy:        UUID
            let completedDate:      Date
            let dueDateAtCompletion: Date
            let title:              String
            let area:               String
            let frequency:          String
            let estimatedMinutes:   Int
            let notes:              String
            enum CodingKeys: String, CodingKey {
                case id
                case taskId              = "task_id"
                case householdId         = "household_id"
                case completedBy         = "completed_by"
                case completedDate       = "completed_date"
                case dueDateAtCompletion = "due_date_at_completion"
                case title, area, frequency, notes
                case estimatedMinutes    = "estimated_minutes"
            }
        }

        let row = CompletionRow(
            id:                 completion.id,
            taskId:             taskId,
            householdId:        hid,
            completedBy:        uid,
            completedDate:      completion.completedDate,
            dueDateAtCompletion: completion.nextDue,
            title:              completion.title,
            area:               completion.area.rawValue,
            frequency:          completion.frequency.rawValue,
            estimatedMinutes:   completion.estimatedMinutes,
            notes:              completion.notes
        )
        do {
            try await supabase.from("maintenance_completions").insert(row).execute()
            pendingCompletionIDs.remove(completion.id)
            persistPendingCompletionIDs()
        } catch {
            Logger.maintenance.error("insert maintenance_completion error: \(error.localizedDescription)")
        }
    }

    private func supabaseDeleteCompletion(id: UUID) async {
        do {
            try await supabase.from("maintenance_completions").delete()
                .eq("id", value: id.uuidString).execute()
            // Tombstone cleared in loadFromSupabase once the row is confirmed absent.
        } catch {
            Logger.maintenance.error("delete maintenance_completion error: \(error.localizedDescription)")
        }
    }

    private func supabaseDelete(id: UUID) async {
        do {
            try await supabase.from("house_tasks").delete()
                .eq("id", value: id.uuidString).execute()
            // Tombstone cleared in loadFromSupabase once the row is confirmed absent.
        } catch {
            Logger.maintenance.error("delete house_task error: \(error.localizedDescription)")
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
    var area:               String?
    var frequency:          String?
    var estimatedMinutes:   Int?
    var assignedToId:       UUID?
    var assignedMemberIds:  [UUID]?
    var dueDate:            Date
    var isComplete:         Bool
    var priority:           String
    var difficulty:         String
    var notes:              String
    var completedDate:      Date?
    let createdBy:          UUID
    let taskType:           String   // discriminates from Schedule's rows in the same table

    enum CodingKeys: String, CodingKey {
        case id
        case householdId        = "household_id"
        case title
        case area
        case frequency
        case estimatedMinutes   = "estimated_minutes"
        case assignedToId       = "assigned_to_id"
        case assignedMemberIds  = "assigned_member_ids"
        case dueDate            = "due_date"
        case isComplete         = "is_complete"
        case priority
        case difficulty
        case notes
        case completedDate      = "completed_date"
        case createdBy          = "created_by"
        case taskType           = "task_type"
    }

    init(from item: MaintenanceItem, userId: UUID, householdId: UUID) {
        id                = item.id
        // Preserve the original creator's UUID so edits by other household members
        // don't overwrite created_by and break the creator's own future update rights.
        createdBy         = UUID(uuidString: item.createdBy ?? "") ?? userId
        self.householdId  = householdId
        title             = item.title
        area              = item.area.rawValue
        frequency         = item.frequency.rawValue
        estimatedMinutes  = item.estimatedMinutes
        assignedMemberIds = item.assignedMemberIDs.isEmpty ? nil
                            : item.assignedMemberIDs.compactMap { UUID(uuidString: $0) }
        assignedToId      = item.assignedMemberIDs.first.flatMap { UUID(uuidString: $0) }
        dueDate           = item.nextDue
        isComplete        = false
        priority          = item.isOverdue ? "high" : (item.isDueSoon ? "medium" : "low")
        difficulty        = item.difficulty.rawValue
        notes             = item.notes
        completedDate     = item.lastCompleted
        taskType          = "maintenance"
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
            area:              MaintenanceItem.HomeArea(rawValue: area ?? "") ?? .general,
            frequency:         MaintenanceItem.Frequency(rawValue: frequency ?? "") ?? .monthly,
            difficulty:        MaintenanceItem.Difficulty(rawValue: difficulty) ?? .medium,
            lastCompleted:     completedDate,
            nextDue:           dueDate,
            notes:             notes,
            estimatedMinutes:  estimatedMinutes ?? 15,
            assignedMemberIDs: memberIDs,
            createdBy:         createdBy.uuidString
        )
    }
}

// MARK: - Supabase row mapping (maintenance_completions table)
private struct SupabaseCompletionRow: Codable {
    let id:                  UUID
    let taskId:              UUID?   // nullable: ON DELETE SET NULL if the recurring task is later deleted
    let householdId:         UUID
    let completedBy:         UUID
    let completedDate:       Date
    let dueDateAtCompletion: Date
    let title:               String
    let area:                String?
    let frequency:           String?
    let estimatedMinutes:    Int?
    let notes:               String?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId              = "task_id"
        case householdId         = "household_id"
        case completedBy         = "completed_by"
        case completedDate       = "completed_date"
        case dueDateAtCompletion = "due_date_at_completion"
        case title, area, frequency, notes
        case estimatedMinutes    = "estimated_minutes"
    }

    func toCompletedTask() -> CompletedTask {
        CompletedTask(
            id:               id,
            originalID:       taskId ?? id,
            title:            title,
            area:             MaintenanceItem.HomeArea(rawValue: area ?? "") ?? .general,
            frequency:        MaintenanceItem.Frequency(rawValue: frequency ?? "") ?? .monthly,
            estimatedMinutes: estimatedMinutes ?? 15,
            notes:            notes ?? "",
            completedDate:    completedDate,
            nextDue:          dueDateAtCompletion,
            createdBy:        completedBy.uuidString
        )
    }
}
