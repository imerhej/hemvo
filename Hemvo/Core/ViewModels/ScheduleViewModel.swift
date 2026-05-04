//  ScheduleViewModel.swift
//  Hemvo
//  Manages family calendar events and household tasks.
//  Supabase `events` table: id, household_id, title, date, end_date,
//    assigned_to_id, is_all_day, notes, category, color_hex, repeat_rule,
//    travel_time, alert_option, created_by, created_at
//  Supabase `house_tasks` table: id, household_id, title, assigned_to_id,
//    due_date, is_complete, priority, notes, completed_date, created_by, created_at

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications
internal import Supabase

@MainActor
final class ScheduleViewModel: ObservableObject {

    @Published var events:           [CalendarEvent]   = []
    @Published var tasks:            [HouseTask]       = []
    @Published var householdMembers: [HouseholdMember] = []

    private var cachedUserID:      UUID?
    private var cachedHouseholdID: UUID?

    private var deletedEventIDs: Set<UUID> = []
    private var deletedTaskIDs:  Set<UUID> = []

    // MARK: - Computed
    var upcomingEvents: [CalendarEvent] {
        events.filter { $0.date >= Calendar.current.startOfDay(for: Date()) }
              .sorted { $0.date < $1.date }
    }

    var tasksDueToday: [HouseTask] {
        tasks.filter { $0.isDueToday && !$0.isComplete }
              .sorted { $0.priority.sortValue < $1.priority.sortValue }
    }

    var overdueTasks: [HouseTask] {
        tasks.filter { $0.isOverdue }
              .sorted { $0.dueDate < $1.dueDate }
    }

    func events(on date: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        var result: [CalendarEvent] = []
        for ev in events {
            if cal.isDate(ev.date, inSameDayAs: date) {
                result.append(ev)
            } else if ev.occursOn(date: date) {
                var occurrence = ev
                let h = cal.component(.hour, from: ev.date)
                let m = cal.component(.minute, from: ev.date)
                if let newStart = cal.date(bySettingHour: h, minute: m, second: 0, of: date) {
                    occurrence.date = newStart
                    if let end = ev.endDate {
                        occurrence.endDate = newStart.addingTimeInterval(end.timeIntervalSince(ev.date))
                    }
                }
                result.append(occurrence)
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    func tasks(on date: Date) -> [HouseTask] {
        tasks.filter { Calendar.current.isDate($0.dueDate, inSameDayAs: date) }
              .sorted { $0.priority.sortValue < $1.priority.sortValue }
    }

    func hasActivity(on date: Date) -> Bool {
        !events(on: date).isEmpty || !tasks(on: date).isEmpty
    }

    // MARK: - Ownership check
    func canDelete(_ event: CalendarEvent) -> Bool {
        guard let uid = cachedUserID else { return false }
        guard let createdBy = event.createdBy else { return true }
        return createdBy == uid.uuidString
    }

    func canDelete(_ task: HouseTask) -> Bool {
        guard let uid = cachedUserID else { return false }
        guard let createdBy = task.createdBy else { return true }
        return createdBy == uid.uuidString
    }

    // MARK: - Member Lookup
    func member(for id: UUID?) -> HouseholdMember? {
        guard let id else { return nil }
        return householdMembers.first { $0.id == id }
    }

    private let notif = NotificationService.shared

    // MARK: - Event CRUD

    func addEvent(_ event: CalendarEvent) {
        var stamped = event
        if stamped.createdBy == nil { stamped.createdBy = cachedUserID?.uuidString }
        events.append(stamped)
        persist()
        if UserDefaults.standard.bool(forKey: "notif_schedule") {
            notif.scheduleEventReminders(for: [stamped])   // local notifications for this device
        }
        Task { await supabaseUpsertEvent(stamped) }
        Task { await sendEventCreationPush(for: stamped) }
        Task { await scheduleEventPushes(for: stamped) }   // server-side pushes for all members
    }

    func updateEvent(_ event: CalendarEvent) {
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            events[idx] = event
            persist()
            notif.cancelEventReminders(for: event.id)
            if UserDefaults.standard.bool(forKey: "notif_schedule") {
                notif.scheduleEventReminders(for: [event])
            }
            Task { await supabaseUpsertEvent(event) }
            // Rebuild server-side push schedule (cancels old ones, inserts new).
            Task { await scheduleEventPushes(for: event) }
        }
    }

    func deleteEvent(_ event: CalendarEvent) {
        guard canDelete(event) else { return }
        deletedEventIDs.insert(event.id)
        persistDeletedIDs()
        events.removeAll { $0.id == event.id }
        persist()
        notif.cancelEventReminders(for: event.id)
        Task { await supabaseDeleteEvent(id: event.id) }
        Task { await cancelEventPushSchedule(for: event.id) }
    }

    // MARK: - Event Push Helpers

    /// Immediate push to household on creation.
    /// Invitees get a personalised "you're invited" message;
    /// all other members get the generic "new event" broadcast.
    private func sendEventCreationPush(for event: CalendarEvent) async {
        let dateStr = event.isAllDay
            ? event.date.formatted(.dateTime.month(.abbreviated).day())
            : event.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())

        if event.inviteeIDs.isEmpty {
            // No specific invitees — broadcast to the whole household.
            await PushNotificationService.shared.notifyHousehold(
                title: "📅 New Event",
                body:  "\(event.title) · \(dateStr)"
            )
        } else {
            // Send a personal "invited" alert to invitees.
            await PushNotificationService.shared.notifyUsers(
                event.inviteeIDs,
                title: "📅 You're invited: \(event.title)",
                body:  dateStr
            )
            // Broadcast to the rest of the household (non-invitees).
            await PushNotificationService.shared.notifyHouseholdExcluding(
                userIDs: event.inviteeIDs,
                title:  "📅 New Event",
                body:   "\(event.title) · \(dateStr)"
            )
        }
    }

    /// Writes rows into `notification_schedule` so the cron Edge Function
    /// (`process-scheduled-push`, running every minute) can deliver APNs
    /// pushes at the right times to all household members.
    ///
    /// Rows written:
    ///   1. At event start time  — "Starting now"
    ///   2. At alert offset time — e.g. "15 minutes before" (if set)
    private func scheduleEventPushes(for event: CalendarEvent) async {
        guard let hid = cachedHouseholdID, event.date > Date() else { return }

        struct ScheduleRow: Encodable {
            let householdId: UUID
            let eventId:     UUID
            let fireAt:      Date
            let title:       String
            let body:        String
            enum CodingKeys: String, CodingKey {
                case householdId = "household_id"
                case eventId     = "event_id"
                case fireAt      = "fire_at"
                case title, body
            }
        }

        // Cancel any unsent schedules for this event before inserting new ones.
        try? await supabase
            .from("notification_schedule")
            .delete()
            .eq("event_id", value: event.id.uuidString)
            .eq("sent",     value: false)
            .execute()

        let timeStr = event.isAllDay
            ? event.date.formatted(.dateTime.month(.abbreviated).day())
            : event.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())

        var rows: [ScheduleRow] = []

        // 1. At event start time.
        rows.append(ScheduleRow(
            householdId: hid,
            eventId:     event.id,
            fireAt:      event.date,
            title:       "📅 \(event.title)",
            body:        event.isAllDay ? "All-day event is today." : "Starting now."
        ))

        // 2. Alert-based notification (before event).
        if event.alertOption != "None",
           let offset = eventAlertOffset(for: event.alertOption) {
            let alertFireAt = event.date.addingTimeInterval(-offset)
            if alertFireAt > Date() {
                rows.append(ScheduleRow(
                    householdId: hid,
                    eventId:     event.id,
                    fireAt:      alertFireAt,
                    title:       "📅 \(event.title)",
                    body:        "\(event.alertOption) · \(timeStr)"
                ))
            }
        }

        do {
            try await supabase
                .from("notification_schedule")
                .insert(rows)
                .execute()
        } catch {
            print("[Supabase] scheduleEventPushes error: \(error)")
        }
    }

    /// Removes any unsent push schedule rows for a deleted/cancelled event.
    private func cancelEventPushSchedule(for eventID: UUID) async {
        try? await supabase
            .from("notification_schedule")
            .delete()
            .eq("event_id", value: eventID.uuidString)
            .eq("sent",     value: false)
            .execute()
    }

    /// Converts an alertOption string to a TimeInterval offset (seconds before event).
    private func eventAlertOffset(for option: String) -> TimeInterval? {
        switch option {
        case "5 minutes before":  return 5  * 60
        case "15 minutes before": return 15 * 60
        case "30 minutes before": return 30 * 60
        case "1 hour before":     return 60 * 60
        case "1 day before":      return 24 * 60 * 60
        default:                  return nil
        }
    }

    // MARK: - Task CRUD
    func addTask(_ task: HouseTask) {
        var stamped = task
        if stamped.createdBy == nil { stamped.createdBy = cachedUserID?.uuidString }
        tasks.append(stamped)
        persist()
        Task { await supabaseUpsertTask(stamped) }
        Task { await sendTaskNotification(for: stamped) }
    }

    /// Sends the right notification depending on whether the task is assigned.
    ///
    /// - Assigned task: personal alert to the assignee only. The household-wide
    ///   broadcast is intentionally skipped — the assignee is already a member
    ///   and would get a duplicate otherwise.
    /// - Unassigned task: broadcast to all household members except the creator.
    private func sendTaskNotification(for task: HouseTask) async {
        let dateStr = task.dueDate.formatted(.dateTime.month(.abbreviated).day())

        if let assignedID = task.assignedToID {
            // Look up the assigner's first name for a personalised message.
            let assignerName: String
            if let uid = cachedUserID,
               let me = householdMembers.first(where: { $0.id == uid }) {
                assignerName = me.name.components(separatedBy: " ").first ?? me.name
            } else {
                assignerName = "Someone"
            }

            let priorityTag: String
            switch task.priority {
            case .high:   priorityTag = " 🔴"
            case .medium: priorityTag = " 🟡"
            case .low:    priorityTag = ""
            }

            await PushNotificationService.shared.notifyUsers(
                [assignedID],
                title: "📋 \(assignerName) assigned you a task\(priorityTag)",
                body:  "\(task.title) · Due \(dateStr)"
            )
        } else {
            // No specific assignee — let the whole household know.
            await PushNotificationService.shared.notifyHousehold(
                title: "✅ New Task",
                body:  "\(task.title) · Due \(dateStr)"
            )
        }
    }

    func toggleTask(_ task: HouseTask) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].isComplete.toggle()
            tasks[idx].completedDate = tasks[idx].isComplete ? Date() : nil
            persist()
            // Use a targeted partial UPDATE (not upsert) so we only touch
            // is_complete + completed_date. A full upsert would stamp
            // created_by = current user, corrupting ownership and breaking
            // the RLS policy for tasks owned by another household member.
            let updated = tasks[idx]
            Task { await supabaseToggleTask(updated) }
        }
    }

    func deleteTask(_ task: HouseTask) {
        guard canDelete(task) else { return }
        deletedTaskIDs.insert(task.id)
        persistDeletedIDs()
        tasks.removeAll { $0.id == task.id }
        persist()
        Task { await supabaseDeleteTask(id: task.id) }
    }

    func deleteTasks(at offsets: IndexSet) {
        let toDelete = offsets.map { tasks[$0] }.filter { canDelete($0) }
        for t in toDelete { deletedTaskIDs.insert(t.id) }
        persistDeletedIDs()
        tasks.removeAll { t in toDelete.contains(where: { $0.id == t.id }) }
        persist()
        for t in toDelete { Task { await supabaseDeleteTask(id: t.id) } }
    }

    // MARK: - Member CRUD (local only — members are managed by HouseholdService)
    func addMember(_ member: HouseholdMember) {
        householdMembers.append(member); persist()
    }
    func deleteMember(_ member: HouseholdMember) {
        householdMembers.removeAll { $0.id == member.id }; persist()
    }

    // MARK: - Persistence
    private let eventsKey          = "hb_events"
    private let tasksKey           = "hb_tasks"
    private let membersKey         = "hb_members"
    private let deletedEventIDsKey = "hb_deletedEventIDs"
    private let deletedTaskIDsKey  = "hb_deletedTaskIDs"

    init() {
        loadDeletedIDs()
        load()
        if UserDefaults.standard.bool(forKey: "notif_schedule") {
            notif.scheduleEventReminders(for: events)
        }
        Task { await loadFromSupabase() }
    }

    private func load() {
        if let d = UserDefaults.standard.data(forKey: eventsKey),
           let v = try? JSONDecoder().decode([CalendarEvent].self, from: d) { events = v }
        if let d = UserDefaults.standard.data(forKey: tasksKey),
           let v = try? JSONDecoder().decode([HouseTask].self, from: d) { tasks = v }
        if let d = UserDefaults.standard.data(forKey: membersKey),
           let v = try? JSONDecoder().decode([HouseholdMember].self, from: d) { householdMembers = v }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(events)          { UserDefaults.standard.set(d, forKey: eventsKey) }
        if let d = try? JSONEncoder().encode(tasks)           { UserDefaults.standard.set(d, forKey: tasksKey) }
        if let d = try? JSONEncoder().encode(householdMembers){ UserDefaults.standard.set(d, forKey: membersKey) }
    }

    private func loadDeletedIDs() {
        if let d = UserDefaults.standard.data(forKey: deletedEventIDsKey),
           let v = try? JSONDecoder().decode([UUID].self, from: d) { deletedEventIDs = Set(v) }
        if let d = UserDefaults.standard.data(forKey: deletedTaskIDsKey),
           let v = try? JSONDecoder().decode([UUID].self, from: d) { deletedTaskIDs = Set(v) }
    }

    private func persistDeletedIDs() {
        if let d = try? JSONEncoder().encode(Array(deletedEventIDs)) { UserDefaults.standard.set(d, forKey: deletedEventIDsKey) }
        if let d = try? JSONEncoder().encode(Array(deletedTaskIDs))  { UserDefaults.standard.set(d, forKey: deletedTaskIDsKey) }
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

        await loadEventsFromSupabase(uid: uid)
        await loadTasksFromSupabase(uid: uid)
    }

    private func loadEventsFromSupabase(uid: UUID) async {
        do {
            var query = supabase.from("events").select()
            if let hid = cachedHouseholdID {
                query = query.eq("household_id", value: hid.uuidString)
            } else {
                query = query.eq("created_by", value: uid.uuidString)
            }
            let rows: [SupabaseEventRow] = try await query.execute().value

            // Re-fire delete for tombstoned events still present remotely.
            let staleRows = rows.filter { deletedEventIDs.contains($0.id) }
            for row in staleRows { Task { await supabaseDeleteEvent(id: row.id) } }

            let remoteEvents = rows.filter { !deletedEventIDs.contains($0.id) }.map { $0.toEvent() }
            let remoteIDs = Set(remoteEvents.map { $0.id })
            let pendingLocal = events.filter { !remoteIDs.contains($0.id) && !deletedEventIDs.contains($0.id) }
            events = remoteEvents + pendingLocal
            if let d = try? JSONEncoder().encode(events) {
                UserDefaults.standard.set(d, forKey: eventsKey)
            }
            if UserDefaults.standard.bool(forKey: "notif_schedule") {
                notif.scheduleEventReminders(for: events)
            }
            for ev in pendingLocal { Task { await supabaseUpsertEvent(ev) } }
        } catch {
            print("[Supabase] fetch events error: \(error)")
        }
    }

    private func loadTasksFromSupabase(uid: UUID) async {
        do {
            var query = supabase.from("house_tasks").select()
            if let hid = cachedHouseholdID {
                query = query.eq("household_id", value: hid.uuidString)
            } else {
                query = query.eq("created_by", value: uid.uuidString)
            }
            let rows: [SupabaseTaskRow] = try await query.execute().value

            // Re-fire delete for tombstoned tasks still present remotely.
            let staleRows = rows.filter { deletedTaskIDs.contains($0.id) }
            for row in staleRows { Task { await supabaseDeleteTask(id: row.id) } }

            let remoteTasks = rows.filter { !deletedTaskIDs.contains($0.id) }.map { $0.toTask() }
            let remoteIDs = Set(remoteTasks.map { $0.id })
            let pendingLocal = tasks.filter { !remoteIDs.contains($0.id) && !deletedTaskIDs.contains($0.id) }
            tasks = remoteTasks + pendingLocal
            if let d = try? JSONEncoder().encode(tasks) {
                UserDefaults.standard.set(d, forKey: tasksKey)
            }
            for t in pendingLocal { Task { await supabaseUpsertTask(t) } }
        } catch {
            print("[Supabase] fetch tasks error: \(error)")
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

    private func supabaseUpsertEvent(_ event: CalendarEvent) async {
        await resolveIDs()
        guard let uid = cachedUserID else { return }
        let row = SupabaseEventRow(from: event, userId: uid, householdId: cachedHouseholdID)
        do {
            try await supabase.from("events").upsert(row, onConflict: "id").execute()
        } catch {
            print("[Supabase] upsert event error: \(error)")
        }
    }

    private func supabaseDeleteEvent(id: UUID) async {
        do {
            try await supabase.from("events").delete().eq("id", value: id.uuidString).execute()
            deletedEventIDs.remove(id)
            persistDeletedIDs()
        } catch {
            print("[Supabase] delete event error: \(error)")
        }
    }

    private func supabaseUpsertTask(_ task: HouseTask) async {
        await resolveIDs()
        guard let uid = cachedUserID, let hid = cachedHouseholdID else { return }
        let row = SupabaseTaskRow(from: task, userId: uid, householdId: hid)
        do {
            try await supabase.from("house_tasks").upsert(row, onConflict: "id").execute()
        } catch {
            print("[Supabase] upsert task error: \(error)")
        }
    }

    /// Partial UPDATE of only is_complete + completed_date.
    /// Works for both the creator and the assigned member under the RLS policy
    /// `USING (created_by = auth.uid() OR assigned_to_id = auth.uid())`.
    private func supabaseToggleTask(_ task: HouseTask) async {
        struct Toggle: Encodable {
            let isComplete:    Bool
            let completedDate: Date?
            enum CodingKeys: String, CodingKey {
                case isComplete    = "is_complete"
                case completedDate = "completed_date"
            }
        }
        do {
            try await supabase.from("house_tasks")
                .update(Toggle(isComplete: task.isComplete, completedDate: task.completedDate))
                .eq("id", value: task.id.uuidString)
                .execute()
        } catch {
            print("[Supabase] toggle task error: \(error)")
        }
    }

    private func supabaseDeleteTask(id: UUID) async {
        do {
            try await supabase.from("house_tasks").delete().eq("id", value: id.uuidString).execute()
            deletedTaskIDs.remove(id)
            persistDeletedIDs()
        } catch {
            print("[Supabase] delete task error: \(error)")
        }
    }
}

// MARK: - Event row mapping
private struct SupabaseEventRow: Codable {
    let id:           UUID
    let householdId:  UUID?
    var title:        String
    var date:         Date
    var endDate:      Date?
    var assignedToId: UUID?
    var isAllDay:     Bool
    var notes:        String
    var category:     String
    var colorHex:     String
    var repeatRule:   String
    var travelTime:   String
    var alertOption:  String
    let createdBy:    UUID
    var inviteeIds:   [UUID]

    enum CodingKeys: String, CodingKey {
        case id
        case householdId  = "household_id"
        case title
        case date
        case endDate      = "end_date"
        case assignedToId = "assigned_to_id"
        case isAllDay     = "is_all_day"
        case notes
        case category
        case colorHex     = "color_hex"
        case repeatRule   = "repeat_rule"
        case travelTime   = "travel_time"
        case alertOption  = "alert_option"
        case createdBy    = "created_by"
        case inviteeIds   = "invitee_ids"
    }

    init(from event: CalendarEvent, userId: UUID, householdId: UUID?) {
        id               = event.id
        createdBy        = userId
        self.householdId = householdId
        title            = event.title
        date             = event.date
        endDate          = event.endDate
        assignedToId     = event.assignedToID
        isAllDay         = event.isAllDay
        notes            = event.notes
        category         = event.category.rawValue
        colorHex         = event.colorHex
        repeatRule       = event.repeatRule.rawValue
        travelTime       = event.travelTime
        alertOption      = event.alertOption
        inviteeIds       = event.inviteeIDs
    }

    func toEvent() -> CalendarEvent {
        CalendarEvent(
            id:           id,
            title:        title,
            date:         date,
            endDate:      endDate,
            assignedToID: assignedToId,
            isAllDay:     isAllDay,
            notes:        notes,
            category:     CalendarEvent.EventCategory(rawValue: category) ?? .general,
            colorHex:     colorHex,
            repeatRule:   CalendarEvent.RecurrenceRule(rawValue: repeatRule) ?? .never,
            travelTime:   travelTime,
            alertOption:  alertOption,
            createdBy:    createdBy.uuidString,
            inviteeIDs:   inviteeIds
        )
    }
}

// MARK: - Task row mapping
private struct SupabaseTaskRow: Codable {
    let id:            UUID
    let householdId:   UUID         // NOT NULL in DB
    var title:         String
    var assignedToId:  UUID?
    var dueDate:       Date
    var isComplete:    Bool
    var priority:      String
    var notes:         String
    var completedDate: Date?
    let createdBy:     UUID

    enum CodingKeys: String, CodingKey {
        case id
        case householdId  = "household_id"
        case title
        case assignedToId = "assigned_to_id"
        case dueDate      = "due_date"
        case isComplete   = "is_complete"
        case priority
        case notes
        case completedDate = "completed_date"
        case createdBy    = "created_by"
    }

    init(from task: HouseTask, userId: UUID, householdId: UUID) {
        id               = task.id
        createdBy        = userId
        self.householdId = householdId
        title            = task.title
        assignedToId     = task.assignedToID
        dueDate          = task.dueDate
        isComplete       = task.isComplete
        priority         = task.priority.rawValue
        notes            = task.notes
        completedDate    = task.completedDate
    }

    func toTask() -> HouseTask {
        HouseTask(
            id:            id,
            title:         title,
            assignedToID:  assignedToId,
            dueDate:       dueDate,
            isComplete:    isComplete,
            priority:      HouseTask.Priority(rawValue: priority) ?? .medium,
            notes:         notes,
            completedDate: completedDate,
            createdBy:     createdBy.uuidString
        )
    }
}
