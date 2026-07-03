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
internal import Foundation
internal import Combine
internal import OSLog
internal import UserNotifications
internal import Supabase
internal import UIKit

@MainActor
final class ScheduleViewModel: ObservableObject {

    @Published var events:           [CalendarEvent]   = []
    @Published var tasks:            [HouseTask]       = []
    @Published var householdMembers: [HouseholdMember] = []

    private var cachedUserID:      UUID?
    private var cachedHouseholdID: UUID?

    private var deletedEventIDs:       Set<UUID> = []
    private var deletedTaskIDs:        Set<UUID> = []
    private var pendingUploadEventIDs: Set<UUID> = []
    private var pendingUploadTaskIDs:  Set<UUID> = []

    // Real-time sync
    private var cancellables:     Set<AnyCancellable> = []
    private var realtimeTask:     Task<Void, Never>?
    private var realtimeDebounce: Task<Void, Never>?
    private var realtimeChannel:  RealtimeChannelV2?

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
        let dayStart = cal.startOfDay(for: date)
        for ev in events {
            if cal.isDate(ev.date, inSameDayAs: date) {
                result.append(ev)
            } else if ev.repeatRule == .never, let endDate = ev.endDate {
                // Multi-day span: include on any day between start and end (inclusive)
                let evStart = cal.startOfDay(for: ev.date)
                let evEnd   = cal.startOfDay(for: endDate)
                if dayStart > evStart && dayStart <= evEnd {
                    result.append(ev)
                }
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

    // MARK: - Role-based write access
    private var hasWriteAccess: Bool {
        guard let uid = cachedUserID else { return false }
        if let role = HouseholdService.shared.household?.members.first(where: { $0.id == uid.uuidString })?.role {
            return role.canWrite
        }
        return true // solo user (no household) — full control
    }

    // MARK: - Ownership check

    // Only the creator may modify an event. If createdBy is nil (legacy/solo events), allow.
    private func isOwnedByCurrentUser(_ event: CalendarEvent) -> Bool {
        guard let createdBy = event.createdBy else { return true }
        return createdBy == cachedUserID?.uuidString
    }

    func canDelete(_ event: CalendarEvent) -> Bool {
        let role = HouseholdService.shared.household?.members
            .first(where: { $0.id == cachedUserID?.uuidString })?.role
        guard let role else { return isOwnedByCurrentUser(event) }
        guard role.canWrite else { return false }
        return true
    }

    func canEdit(_ event: CalendarEvent) -> Bool {
        let role = HouseholdService.shared.household?.members
            .first(where: { $0.id == cachedUserID?.uuidString })?.role
        guard let role else { return isOwnedByCurrentUser(event) }
        guard role.canWrite else { return false }
        return true
    }

    func canDelete(_ task: HouseTask) -> Bool {
        hasWriteAccess
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
        pendingUploadEventIDs.insert(stamped.id)
        persistPendingUploadIDs()
        persist()
        if UserPreferences.shared.notifSchedule {
            notif.scheduleEventReminders(for: [stamped])   // local notifications for this device
        }
        Task { await supabaseUpsertEvent(stamped) }
        Task { await sendEventCreationPush(for: stamped) }
        // Scheduled server-side pushes go to the whole household, so only
        // fire them for household events. Personal events rely on the local
        // notification scheduled in the sheet and the creation push above.
        if stamped.scope == .household {
            Task { await scheduleEventPushes(for: stamped) }
        }
    }

    func updateEvent(_ event: CalendarEvent) {
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            let old = events[idx]
            events[idx] = event
            persist()
            notif.cancelEventReminders(for: event.id)
            if UserPreferences.shared.notifSchedule {
                notif.scheduleEventReminders(for: [event])
            }
            Task { await supabaseUpdateEvent(event) }
            if event.scope == .household {
                Task { await scheduleEventPushes(for: event) }
            } else {
                Task { await cancelEventPushSchedule(for: event.id) }
            }
            Task { await sendEventUpdatePush(old: old, new: event) }
        }
    }

    func deleteEvent(_ event: CalendarEvent) {
        guard canDelete(event) else { return }
        deletedEventIDs.insert(event.id)
        pendingUploadEventIDs.remove(event.id)
        persistDeletedIDs()
        persistPendingUploadIDs()
        events.removeAll { $0.id == event.id }
        persist()
        notif.cancelEventReminders(for: event.id)
        Task { await supabaseDeleteEvent(id: event.id) }
        Task { await cancelEventPushSchedule(for: event.id) }
    }

    // MARK: - Event Push Helpers

    /// Immediate push on event creation, gated by scope:
    ///
    /// - **Household**: all members notified. Invitees get "You're invited";
    ///   everyone else gets the generic "New Event" broadcast.
    /// - **Personal, no invitees**: no push sent (creator gets a local notification only).
    /// - **Personal, with invitees**: only the selected invitees are notified.
    private func sendEventCreationPush(for event: CalendarEvent) async {
        let dateStr = event.isAllDay
            ? event.date.formatted(.dateTime.month(.abbreviated).day())
            : event.date.formatted(.dateTime.month(.abbreviated).day().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits))
        let creator = HouseholdService.shared.displayName(forUserID: cachedUserID)

        if event.scope == .personal {
            guard !event.inviteeIDs.isEmpty else { return }
            await PushNotificationService.shared.notifyUsers(
                event.inviteeIDs,
                title: "📅 \(creator) invited you: \(event.title)",
                body:  dateStr
            )
            return
        }

        // Household event — notify everyone.
        if event.inviteeIDs.isEmpty {
            await PushNotificationService.shared.notifyHouseholdFiltered(
                permission: \.receiveCalendarAlerts,
                title: "📅 \(creator) added an event",
                body:  "\(event.title) · \(dateStr)"
            )
        } else {
            async let inviteePush: Void = PushNotificationService.shared.notifyUsers(
                event.inviteeIDs,
                title: "📅 \(creator) invited you: \(event.title)",
                body:  dateStr
            )
            async let othersPush: Void = PushNotificationService.shared.notifyHouseholdExcludingFiltered(
                userIDs:    event.inviteeIDs,
                permission: \.receiveCalendarAlerts,
                title:      "📅 \(creator) added an event",
                body:       "\(event.title) · \(dateStr)"
            )
            _ = await (inviteePush, othersPush)
        }
    }

    /// Sends an immediate push when an event is edited, gated by what actually changed
    /// and who should be notified based on the old and new scope.
    ///
    /// - Personal → Household: broadcast to the whole household (new shared event).
    /// - Household → Personal: no push; the event silently disappears on next sync.
    /// - Household → Household: notify all members if title, date, or all-day changed.
    /// - Personal → Personal: "You're invited" to new invitees; "Event Updated" to
    ///   existing invitees when title, date, or all-day changed.
    private func sendEventUpdatePush(old: CalendarEvent, new: CalendarEvent) async {
        let dateStr = new.isAllDay
            ? new.date.formatted(.dateTime.month(.abbreviated).day())
            : new.date.formatted(.dateTime.month(.abbreviated).day()
                .hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits))

        let detailsChanged = old.title != new.title
            || !Calendar.current.isDate(old.date, equalTo: new.date, toGranularity: .minute)
            || old.isAllDay != new.isAllDay

        switch (old.scope, new.scope) {

        // Personal → Household: treat like a new shared event.
        case (.personal, .household):
            if new.inviteeIDs.isEmpty {
                await PushNotificationService.shared.notifyHouseholdFiltered(
                    permission: \.receiveCalendarAlerts,
                    title: "📅 New Shared Event",
                    body:  "\(new.title) · \(dateStr)"
                )
            } else {
                async let inviteePush: Void = PushNotificationService.shared.notifyUsers(
                    new.inviteeIDs,
                    title: "📅 You're invited: \(new.title)",
                    body:  dateStr
                )
                async let othersPush: Void = PushNotificationService.shared.notifyHouseholdExcludingFiltered(
                    userIDs:    new.inviteeIDs,
                    permission: \.receiveCalendarAlerts,
                    title:      "📅 New Shared Event",
                    body:       "\(new.title) · \(dateStr)"
                )
                _ = await (inviteePush, othersPush)
            }

        // Household → Personal: event disappears from others on next sync; no push.
        case (.household, .personal):
            break

        // Household → Household: notify everyone if anything meaningful changed.
        case (.household, .household):
            guard detailsChanged else { return }
            if new.inviteeIDs.isEmpty {
                await PushNotificationService.shared.notifyHouseholdFiltered(
                    permission: \.receiveCalendarAlerts,
                    title: "📅 Event Updated",
                    body:  "\(new.title) · \(dateStr)"
                )
            } else {
                async let inviteePush: Void = PushNotificationService.shared.notifyUsers(
                    new.inviteeIDs,
                    title: "📅 Event Updated: \(new.title)",
                    body:  dateStr
                )
                async let othersPush: Void = PushNotificationService.shared.notifyHouseholdExcludingFiltered(
                    userIDs:    new.inviteeIDs,
                    permission: \.receiveCalendarAlerts,
                    title:      "📅 Event Updated",
                    body:       "\(new.title) · \(dateStr)"
                )
                _ = await (inviteePush, othersPush)
            }

        // Personal → Personal: notify new invitees and (if details changed) existing ones.
        case (.personal, .personal):
            let newInvitees      = Set(new.inviteeIDs).subtracting(old.inviteeIDs)
            let existingInvitees = Set(new.inviteeIDs).intersection(old.inviteeIDs)

            if !newInvitees.isEmpty {
                await PushNotificationService.shared.notifyUsers(
                    Array(newInvitees),
                    title: "📅 You're invited: \(new.title)",
                    body:  dateStr
                )
            }
            if detailsChanged && !existingInvitees.isEmpty {
                await PushNotificationService.shared.notifyUsers(
                    Array(existingInvitees),
                    title: "📅 Event Updated: \(new.title)",
                    body:  dateStr
                )
            }
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
        await resolveIDs()
        guard let hid = cachedHouseholdID, event.date > Date() else { return }
        let creatorID = cachedUserID

        struct ScheduleRow: Encodable {
            let householdId: UUID
            let eventId:     UUID
            let fireAt:      Date
            let title:       String
            let body:        String
            let creatorId:   UUID?
            enum CodingKeys: String, CodingKey {
                case householdId = "household_id"
                case eventId     = "event_id"
                case fireAt      = "fire_at"
                case title, body
                case creatorId   = "creator_id"
            }
        }

        // Cancel any unsent schedules for this event before inserting new ones.
        do {
            try await supabase
                .from("notification_schedule")
                .delete()
                .eq("event_id", value: event.id.uuidString)
                .eq("sent",     value: false)
                .execute()
        } catch {
            Logger.schedule.error("cancelOldSchedules error: \(error.localizedDescription)")
        }

        let timeStr = event.isAllDay
            ? event.date.formatted(.dateTime.month(.abbreviated).day())
            : event.date.formatted(.dateTime.month(.abbreviated).day().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits))

        var rows: [ScheduleRow] = []

        // 1. At event start time.
        rows.append(ScheduleRow(
            householdId: hid,
            eventId:     event.id,
            fireAt:      event.date,
            title:       "📅 \(event.title)",
            body:        event.isAllDay ? "All-day event is today." : "Starting now.",
            creatorId:   creatorID
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
                    body:        "\(event.alertOption) · \(timeStr)",
                    creatorId:   creatorID
                ))
            }
        }

        do {
            try await supabase
                .from("notification_schedule")
                .insert(rows)
                .execute()
        } catch {
            Logger.schedule.error("scheduleEventPushes error: \(error.localizedDescription)")
        }
    }

    /// Removes any unsent push schedule rows for a deleted/cancelled event.
    private func cancelEventPushSchedule(for eventID: UUID) async {
        do {
            try await supabase
                .from("notification_schedule")
                .delete()
                .eq("event_id", value: eventID.uuidString)
                .eq("sent",     value: false)
                .execute()
        } catch {
            Logger.schedule.error("cancelEventPushSchedule error: \(error.localizedDescription)")
        }
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
        pendingUploadTaskIDs.insert(stamped.id)
        persistPendingUploadIDs()
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
            // No specific assignee — broadcast to members who receive calendar/task alerts.
            await PushNotificationService.shared.notifyHouseholdFiltered(
                permission: \.receiveCalendarAlerts,
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
        pendingUploadTaskIDs.remove(task.id)
        persistDeletedIDs()
        persistPendingUploadIDs()
        tasks.removeAll { $0.id == task.id }
        persist()
        Task { await supabaseDeleteTask(id: task.id) }
    }

    func deleteTasks(at offsets: IndexSet) {
        let toDelete = offsets.map { tasks[$0] }.filter { canDelete($0) }
        for t in toDelete {
            deletedTaskIDs.insert(t.id)
            pendingUploadTaskIDs.remove(t.id)
        }
        persistDeletedIDs()
        persistPendingUploadIDs()
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
    private let eventsKey                = "hemvo_events"
    private let tasksKey                 = "hemvo_tasks"
    private let membersKey               = "hemvo_members"
    private let deletedEventIDsKey       = "hemvo_deletedEventIDs"
    private let deletedTaskIDsKey        = "hemvo_deletedTaskIDs"
    private let pendingUploadEventIDsKey = "hemvo_pendingUploadEventIDs"
    private let pendingUploadTaskIDsKey  = "hemvo_pendingUploadTaskIDs"

    init() {
        loadDeletedIDs()
        loadPendingUploadIDs()
        load()
        if UserPreferences.shared.notifSchedule {
            notif.scheduleEventReminders(for: events)
        }
        Task { await loadFromSupabase() }
        NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.loadFromSupabase() }
            }
            .store(in: &cancellables)
    }

    deinit {
        realtimeTask?.cancel()
        realtimeDebounce?.cancel()
        if let ch = realtimeChannel {
            Task { await supabase.realtimeV2.removeChannel(ch) }
        }
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

    private func loadPendingUploadIDs() {
        if let d = UserDefaults.standard.data(forKey: pendingUploadEventIDsKey),
           let v = try? JSONDecoder().decode([UUID].self, from: d) { pendingUploadEventIDs = Set(v) }
        if let d = UserDefaults.standard.data(forKey: pendingUploadTaskIDsKey),
           let v = try? JSONDecoder().decode([UUID].self, from: d) { pendingUploadTaskIDs = Set(v) }
    }

    private func persistPendingUploadIDs() {
        if let d = try? JSONEncoder().encode(Array(pendingUploadEventIDs)) { UserDefaults.standard.set(d, forKey: pendingUploadEventIDsKey) }
        if let d = try? JSONEncoder().encode(Array(pendingUploadTaskIDs))  { UserDefaults.standard.set(d, forKey: pendingUploadTaskIDsKey) }
    }

    // MARK: - Supabase Sync

    func loadFromSupabase() async {
        guard let uid = await AuthService.shared.currentUserID() else { return }
        cachedUserID = uid

        // Evict any personal events that slipped into the local cache (e.g. via stale
        // UserDefaults written before scope filtering existed). Do this before the Supabase
        // fetch so the in-memory state is already clean if the network call fails.
        let before = events.count
        events = events.filter { isVisible($0, to: uid) }
        if events.count != before { persist() }

        if let profile = try? await AuthService.shared.loadProfile() {
            cachedHouseholdID = profile.householdId
        }
        if cachedHouseholdID == nil {
            cachedHouseholdID = UUID(uuidString: HouseholdService.shared.household?.id ?? "")
        }

        if realtimeTask == nil, cachedHouseholdID != nil {
            startRealtimeSubscription()
        }

        // Re-upsert the device token with the now-resolved household_id.
        // First launch can register the token before household_id is known,
        // leaving household_id = NULL in the DB and causing notifyHousehold
        // to find zero rows. Refreshing here ensures the token is always
        // registered with the correct household.
        if cachedHouseholdID != nil {
            PushNotificationService.shared.refreshToken()
        }

        await loadEventsFromSupabase(uid: uid)
        await loadTasksFromSupabase(uid: uid)
    }

    private func startRealtimeSubscription() {
        guard let hid = cachedHouseholdID else { return }

        let channel = supabase.realtimeV2.channel("schedule:\(hid.uuidString):\(UUID().uuidString)")
        realtimeChannel = channel

        realtimeTask = Task { [weak self, channel] in
            let eventStream = channel.postgresChange(
                AnyAction.self, schema: "public", table: "events",
                filter: .eq("household_id", value: hid.uuidString.lowercased())
            )
            let taskStream = channel.postgresChange(
                AnyAction.self, schema: "public", table: "house_tasks",
                filter: .eq("household_id", value: hid.uuidString.lowercased())
            )

            do {
                try await channel.subscribeWithError()
            } catch {
                Logger.realtime.error("schedule subscribe error: \(error.localizedDescription)")
                self?.realtimeTask = nil
                return
            }

            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    for await action in eventStream {
                        guard !Task.isCancelled, let self else { break }
                        await self.handleEventChange(action)
                    }
                }
                group.addTask { [weak self] in
                    for await action in taskStream {
                        guard !Task.isCancelled, let self else { break }
                        await self.handleTaskChange(action)
                    }
                }
            }

            if !Task.isCancelled {
                self?.realtimeTask = nil
            }
        }
    }

    // MARK: - Realtime payload handlers

    // Decodes Supabase CDC timestamp strings — handles both with and without
    // fractional seconds (e.g. "2026-05-10T12:00:00Z" and "…T12:00:00.123456Z").
    private static let realtimeDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c   = try decoder.singleValueContainer()
            let s   = try c.decode(String.self)
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fmt.date(from: s) { return date }
            fmt.formatOptions = [.withInternetDateTime]
            if let date = fmt.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c,
                debugDescription: "Cannot decode date: \(s)")
        }
        return d
    }()

    private func handleEventChange(_ action: AnyAction) async {
        switch action {
        case .insert(let a):
            guard let row = try? a.decodeRecord(as: SupabaseEventRow.self,
                                                decoder: Self.realtimeDecoder) else {
                scheduleRealtimeReload(); return
            }
            let event = row.toEvent()
            guard !deletedEventIDs.contains(event.id) else { return }
            // Skip if already in the list (our own optimistic insert).
            guard !events.contains(where: { $0.id == event.id }) else { return }
            // Personal events from other users that didn't invite this user are not shown.
            guard cachedUserID.map({ isVisible(event, to: $0) }) ?? true else { return }
            events.append(event)
            if UserPreferences.shared.notifSchedule {
                notif.scheduleEventReminders(for: [event])
            }
            persist()

        case .update(let a):
            guard let row = try? a.decodeRecord(as: SupabaseEventRow.self,
                                                decoder: Self.realtimeDecoder) else {
                scheduleRealtimeReload(); return
            }
            let event = row.toEvent()
            // If scope/invitees changed and the event is no longer visible, remove it.
            if let uid = cachedUserID, !isVisible(event, to: uid) {
                events.removeAll { $0.id == event.id }
                persist()
                return
            }
            if let idx = events.firstIndex(where: { $0.id == event.id }) {
                events[idx] = event
            } else if !deletedEventIDs.contains(event.id) {
                events.append(event)
                if UserPreferences.shared.notifSchedule {
                    notif.scheduleEventReminders(for: [event])
                }
            }
            persist()

        case .delete(let a):
            // oldRecord["id"] is available because REPLICA IDENTITY FULL is set.
            guard case .string(let s) = a.oldRecord["id"],
                  let id = UUID(uuidString: s) else {
                scheduleRealtimeReload(); return
            }
            events.removeAll { $0.id == id }
            persist()

        @unknown default:
            break
        }
    }

    private func handleTaskChange(_ action: AnyAction) async {
        switch action {
        case .insert(let a):
            guard let row = try? a.decodeRecord(as: SupabaseTaskRow.self,
                                                decoder: Self.realtimeDecoder) else {
                scheduleRealtimeReload(); return
            }
            let task = row.toTask()
            guard !deletedTaskIDs.contains(task.id) else { return }
            guard !tasks.contains(where: { $0.id == task.id }) else { return }
            tasks.append(task)
            persist()

        case .update(let a):
            guard let row = try? a.decodeRecord(as: SupabaseTaskRow.self,
                                                decoder: Self.realtimeDecoder) else {
                scheduleRealtimeReload(); return
            }
            let task = row.toTask()
            if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[idx] = task
            } else if !deletedTaskIDs.contains(task.id) {
                tasks.append(task)
            }
            persist()

        case .delete(let a):
            guard case .string(let s) = a.oldRecord["id"],
                  let id = UUID(uuidString: s) else {
                scheduleRealtimeReload(); return
            }
            tasks.removeAll { $0.id == id }
            persist()

        @unknown default:
            break
        }
    }

    // Fallback: short debounced full-reload when direct payload decode fails.
    private func scheduleRealtimeReload() {
        realtimeDebounce?.cancel()
        realtimeDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.loadFromSupabase()
        }
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
            let remoteRowIDs = Set(rows.map { $0.id })

            // Tombstones that are no longer in Supabase → delete succeeded; clear them.
            let clearedTombstones = deletedEventIDs.filter { !remoteRowIDs.contains($0) }
            if !clearedTombstones.isEmpty {
                deletedEventIDs.subtract(clearedTombstones)
                persistDeletedIDs()
            }

            // Re-fire delete for tombstoned events still present remotely (RLS may have
            // silently blocked the first attempt when called by a non-creator).
            let staleRows = rows.filter { deletedEventIDs.contains($0.id) }
            for row in staleRows { Task { await supabaseDeleteEvent(id: row.id) } }

            let remoteEvents = rows
                .filter { !deletedEventIDs.contains($0.id) }
                .map { $0.toEvent() }
                .filter { isVisible($0, to: uid) }
            let remoteIDs = Set(remoteEvents.map { $0.id })
            // Only re-upload events that were explicitly created offline on this device.
            // Without this guard, events deleted on another device would be resurrected
            // because the local cache would treat their absence as a pending upload.
            let pendingLocal = events.filter {
                pendingUploadEventIDs.contains($0.id) &&
                !remoteIDs.contains($0.id) &&
                !deletedEventIDs.contains($0.id)
            }
            events = remoteEvents + pendingLocal
            if let d = try? JSONEncoder().encode(events) {
                UserDefaults.standard.set(d, forKey: eventsKey)
            }
            if UserPreferences.shared.notifSchedule {
                notif.scheduleEventReminders(for: events)
            }
            for ev in pendingLocal { Task { await supabaseUpsertEvent(ev) } }
        } catch {
            Logger.schedule.error("fetch events error: \(error.localizedDescription)")
        }
    }

    private func loadTasksFromSupabase(uid: UUID) async {
        do {
            var query = supabase.from("house_tasks").select()
                .eq("task_type", value: "schedule")
            if let hid = cachedHouseholdID {
                query = query.eq("household_id", value: hid.uuidString)
            } else {
                query = query.eq("created_by", value: uid.uuidString)
            }
            let rows: [SupabaseTaskRow] = try await query.execute().value
            let remoteRowIDs = Set(rows.map { $0.id })

            // Tombstones that are no longer in Supabase → delete succeeded; clear them.
            let clearedTombstones = deletedTaskIDs.filter { !remoteRowIDs.contains($0) }
            if !clearedTombstones.isEmpty {
                deletedTaskIDs.subtract(clearedTombstones)
                persistDeletedIDs()
            }

            // Re-fire delete for tombstoned tasks still present remotely.
            let staleRows = rows.filter { deletedTaskIDs.contains($0.id) }
            for row in staleRows { Task { await supabaseDeleteTask(id: row.id) } }

            let remoteTasks = rows.filter { !deletedTaskIDs.contains($0.id) }.map { $0.toTask() }
            let remoteIDs = Set(remoteTasks.map { $0.id })
            let pendingLocal = tasks.filter {
                pendingUploadTaskIDs.contains($0.id) &&
                !remoteIDs.contains($0.id) &&
                !deletedTaskIDs.contains($0.id)
            }
            tasks = remoteTasks + pendingLocal
            if let d = try? JSONEncoder().encode(tasks) {
                UserDefaults.standard.set(d, forKey: tasksKey)
            }
            for t in pendingLocal { Task { await supabaseUpsertTask(t) } }
        } catch {
            Logger.schedule.error("fetch tasks error: \(error.localizedDescription)")
        }
    }

    /// Returns false for personal events that don't belong to the given user.
    /// Household events are always visible. Personal events require the user to
    /// be the creator or an explicit invitee.
    private func isVisible(_ event: CalendarEvent, to userID: UUID) -> Bool {
        if event.scope == .household { return true }
        return event.createdBy == userID.uuidString || event.inviteeIDs.contains(userID)
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
        guard !deletedEventIDs.contains(event.id) else { return }
        await resolveIDs()
        guard let uid = cachedUserID else { return }
        let row = SupabaseEventRow(from: event, userId: uid, householdId: cachedHouseholdID)
        do {
            try await supabase.from("events").upsert(row, onConflict: "id").execute()
            pendingUploadEventIDs.remove(event.id)
            persistPendingUploadIDs()
        } catch {
            Logger.schedule.error("upsert event error: \(error.localizedDescription)")
        }
    }

    /// Plain UPDATE of only the mutable event fields — never touches created_by or household_id.
    /// This allows any household member (not just the creator) to save edits under the
    /// new "events_update" RLS policy that checks household membership instead of ownership.
    private func supabaseUpdateEvent(_ event: CalendarEvent) async {
        guard !deletedEventIDs.contains(event.id) else { return }
        struct EventPatch: Encodable {
            var title:        String
            var location:     String
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
            var inviteeIds:   [UUID]
            var scope:        String
            enum CodingKeys: String, CodingKey {
                case title
                case location
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
                case inviteeIds   = "invitee_ids"
                case scope
            }
        }
        let patch = EventPatch(
            title:        event.title,
            location:     event.location,
            date:         event.date,
            endDate:      event.endDate,
            assignedToId: event.assignedToID,
            isAllDay:     event.isAllDay,
            notes:        event.notes,
            category:     event.category.rawValue,
            colorHex:     event.colorHex,
            repeatRule:   event.repeatRule.rawValue,
            travelTime:   event.travelTime,
            alertOption:  event.alertOption,
            inviteeIds:   event.inviteeIDs,
            scope:        event.scope.rawValue
        )
        do {
            try await supabase.from("events")
                .update(patch)
                .eq("id", value: event.id.uuidString)
                .execute()
        } catch {
            Logger.schedule.error("update event error: \(error.localizedDescription)")
        }
    }

    private func supabaseDeleteEvent(id: UUID) async {
        do {
            try await supabase.from("events").delete().eq("id", value: id.uuidString).execute()
            // Do NOT remove from deletedEventIDs here. The tombstone is only cleared
            // in loadEventsFromSupabase once we confirm the row is absent remotely.
            // This prevents a silent RLS block (0 rows affected, no error thrown) from
            // causing the event to re-appear on the next sync.
        } catch {
            Logger.schedule.error("delete event error: \(error.localizedDescription)")
        }
    }

    private func supabaseUpsertTask(_ task: HouseTask) async {
        guard !deletedTaskIDs.contains(task.id) else { return }
        await resolveIDs()
        guard let uid = cachedUserID, let hid = cachedHouseholdID else { return }
        let row = SupabaseTaskRow(from: task, userId: uid, householdId: hid)
        do {
            try await supabase.from("house_tasks").upsert(row, onConflict: "id").execute()
            pendingUploadTaskIDs.remove(task.id)
            persistPendingUploadIDs()
        } catch {
            Logger.schedule.error("upsert task error: \(error.localizedDescription)")
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
            Logger.schedule.error("toggle task error: \(error.localizedDescription)")
        }
    }

    private func supabaseDeleteTask(id: UUID) async {
        do {
            try await supabase.from("house_tasks").delete().eq("id", value: id.uuidString).execute()
            // Tombstone cleared in loadTasksFromSupabase once confirmed absent remotely.
        } catch {
            Logger.schedule.error("delete task error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Event row mapping
private struct SupabaseEventRow: Codable {
    let id:           UUID
    let householdId:  UUID?
    var title:        String
    var location:     String
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
    // Optional so rows fetched before the scope migration column exists still decode.
    var scope:        String?

    enum CodingKeys: String, CodingKey {
        case id
        case householdId  = "household_id"
        case title
        case location
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
        case scope
    }

    init(from event: CalendarEvent, userId: UUID, householdId: UUID?) {
        id               = event.id
        // Preserve the original creator; fall back to current user only for new events.
        createdBy        = event.createdBy.flatMap { UUID(uuidString: $0) } ?? userId
        self.householdId = householdId
        title            = event.title
        location         = event.location
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
        scope            = event.scope.rawValue
    }

    func toEvent() -> CalendarEvent {
        CalendarEvent(
            id:           id,
            title:        title,
            location:     location,
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
            inviteeIDs:   inviteeIds,
            // nil scope means the DB row pre-dates the scope column; treat as Household
            // so existing events remain visible to all household members.
            scope:        CalendarEvent.EventScope(rawValue: scope ?? "Household") ?? .household
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
    let taskType:      String       // discriminates from Maintenance's rows in the same table

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
        case taskType     = "task_type"
    }

    init(from task: HouseTask, userId: UUID, householdId: UUID) {
        id               = task.id
        // Preserve the original creator; fall back to current user only for new tasks.
        createdBy        = task.createdBy.flatMap { UUID(uuidString: $0) } ?? userId
        self.householdId = householdId
        title            = task.title
        assignedToId     = task.assignedToID
        dueDate          = task.dueDate
        isComplete       = task.isComplete
        priority         = task.priority.rawValue
        notes            = task.notes
        completedDate    = task.completedDate
        taskType         = "schedule"
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
