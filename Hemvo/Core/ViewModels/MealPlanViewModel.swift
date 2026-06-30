//  MealPlanViewModel.swift
//  Hemvo
//  Manages the weekly meal plan state.
//  Supabase `meals` table schema:
//    id, household_id, name, day (smallint), meal_date (text "yyyy-MM-dd"),
//    meal_type, ingredients (jsonb), notes, prep_time_minutes, servings,
//    created_by, created_at

internal import SwiftUI
internal import Foundation
internal import Combine
internal import OSLog
internal import Supabase
internal import UIKit

@MainActor
final class MealPlanViewModel: ObservableObject {

    @Published var meals: [Meal] = []

    private var cachedUserID:      UUID?
    private var cachedHouseholdID: UUID?

    private var deletedMealIDs:    Set<UUID> = []
    private var pendingUploadIDs:  Set<UUID> = []
    private var isSyncing:         Bool      = false

    // Real-time sync
    private var cancellables:      Set<AnyCancellable> = []
    private var realtimeTask:      Task<Void, Never>?
    private var realtimeChannel:   RealtimeChannelV2?

    // MARK: - Computed
    var todaysMeals: [Meal] {
        let cal = Calendar.current
        return meals
            .filter { cal.isDateInToday($0.date) }
            .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }
    }

    var allIngredients: [GroceryItem] {
        meals.flatMap { $0.ingredients }
    }

    /// Past meals in reverse-chronological order — read-only historical record.
    var pastMeals: [Meal] {
        let today = Calendar.current.startOfDay(for: Date())
        return meals
            .filter { $0.date < today }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Query (date-based — fixes week-leakage bug)
    func meals(for date: Date) -> [Meal] {
        let cal = Calendar.current
        return meals
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }
    }

    func meals(for date: Date, type: Meal.MealType) -> [Meal] {
        let cal = Calendar.current
        return meals.filter {
            cal.isDate($0.date, inSameDayAs: date) && $0.mealType == type
        }
    }

    func meal(for date: Date, type: Meal.MealType) -> Meal? {
        let cal = Calendar.current
        return meals.first {
            cal.isDate($0.date, inSameDayAs: date) && $0.mealType == type
        }
    }

    // Legacy weekday-based helpers (used by todaysMeals fallback and DashboardView)
    func meals(for day: Meal.Weekday) -> [Meal] {
        meals.filter { $0.day == day }
            .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }
    }

    private let notif = NotificationService.shared

    // Shared ISO date formatter used by scheduleMealPush and supabaseDeleteFuture.
    private static let isoFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - CRUD
    func addMeal(_ meal: Meal) {
        var stamped = meal
        if stamped.createdBy == nil { stamped.createdBy = cachedUserID?.uuidString }
        meals.removeAll { $0.id == stamped.id }
        meals.append(stamped)
        persist()
        if UserPreferences.shared.notifMeals {
            notif.scheduleMealReminders(meals: meals)
        }
        objectWillChange.send()
        pendingUploadIDs.insert(stamped.id)
        persistPendingUploadIDs()
        Task { await supabaseUpsert(stamped) }
        Task {
            await resolveIDs()
            guard let hid = cachedHouseholdID else { return }
            // Immediate push to all household members (excludes sender via creator_id).
            await PushNotificationService.shared.notifyHousehold(
                householdID: hid.uuidString,
                creatorID:   cachedUserID?.uuidString,
                title: "🍽️ Meal Planned",
                body:  "\(stamped.name) · \(stamped.day.label) \(stamped.mealType.rawValue)"
            )
            // Scheduled 8 PM push the evening before for the whole household.
            await scheduleMealPush(forDate: stamped.date)
        }
    }

    func updateMeal(_ meal: Meal) {
        if let idx = meals.firstIndex(where: { $0.id == meal.id }) {
            let oldDate = meals[idx].date
            meals[idx] = meal
            persist()
            if UserPreferences.shared.notifMeals {
                notif.scheduleMealReminders(meals: meals)
            }
            objectWillChange.send()
            Task { await supabaseUpsert(meal) }
            Task {
                await resolveIDs()
                await scheduleMealPush(forDate: meal.date)
                if !Calendar.current.isDate(oldDate, inSameDayAs: meal.date) {
                    await scheduleMealPush(forDate: oldDate)
                }
            }
        }
    }

    func deleteMeal(_ meal: Meal) {
        deletedMealIDs.insert(meal.id)
        pendingUploadIDs.remove(meal.id)
        persistDeletedIDs()
        persistPendingUploadIDs()
        let deletedDate = meal.date
        meals.removeAll { $0.id == meal.id }
        persist()
        if UserPreferences.shared.notifMeals {
            notif.scheduleMealReminders(meals: meals)
        }
        objectWillChange.send()
        Task { await supabaseDelete(id: meal.id) }
        Task { await resolveIDs(); await scheduleMealPush(forDate: deletedDate) }
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
    func canDelete(_ meal: Meal) -> Bool {
        hasWriteAccess && !meal.isPast
    }

    func clearWeek() {
        let today = Calendar.current.startOfDay(for: Date())
        let futureMeals = meals.filter { $0.date >= today }
        for meal in futureMeals {
            deletedMealIDs.insert(meal.id)
            pendingUploadIDs.remove(meal.id)
        }
        persistDeletedIDs()
        persistPendingUploadIDs()
        meals.removeAll { $0.date >= today }
        persist()
        notif.cancelMealReminders()
        objectWillChange.send()
        Task { await supabaseDeleteFuture() }
    }

    // MARK: - Persistence
    private let storageKey           = "hemvo_meals"
    private let deletedMealIDsKey    = "hemvo_deletedMealIDs"
    private let pendingUploadIDsKey  = "hemvo_pendingUploadIDs"

    init() {
        loadDeletedIDs()
        loadPendingUploadIDs()
        load()
        if UserPreferences.shared.notifMeals {
            notif.scheduleMealReminders(meals: meals)
        }
        Task { await loadFromSupabase() }

        // Re-sync whenever the app returns from background.
        NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.loadFromSupabase() }
            }
            .store(in: &cancellables)

        // Fallback sync every 15 s — catches deletions that Realtime missed
        // (e.g. when the table isn't yet in supabase_realtime publication).
        Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.loadFromSupabase() }
            }
            .store(in: &cancellables)
    }

    deinit {
        realtimeTask?.cancel()
        if let ch = realtimeChannel {
            Task { await supabase.realtimeV2.removeChannel(ch) }
        }
    }

    private func load() {
        guard let data    = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Meal].self, from: data)
        else { return }
        meals = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(meals) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadDeletedIDs() {
        guard let d = UserDefaults.standard.data(forKey: deletedMealIDsKey),
              let v = try? JSONDecoder().decode([UUID].self, from: d) else { return }
        deletedMealIDs = Set(v)
    }

    private func persistDeletedIDs() {
        if let d = try? JSONEncoder().encode(Array(deletedMealIDs)) {
            UserDefaults.standard.set(d, forKey: deletedMealIDsKey)
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
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        guard let uid = await AuthService.shared.currentUserID() else { return }
        cachedUserID = uid

        if let profile = try? await AuthService.shared.loadProfile() {
            cachedHouseholdID = profile.householdId
        }
        if cachedHouseholdID == nil {
            cachedHouseholdID = UUID(uuidString: HouseholdService.shared.household?.id ?? "")
        }

        // Start the Realtime listener the first time the household ID is resolved.
        if realtimeTask == nil, cachedHouseholdID != nil {
            startRealtimeSubscription()
        }

        do {
            var query = supabase.from("meals").select()

            if let hid = cachedHouseholdID {
                query = query.eq("household_id", value: hid.uuidString)
            } else {
                query = query.eq("created_by", value: uid.uuidString)
            }

            let rows: [SupabaseMealRow] = try await query.execute().value

            let remoteRowIDs = Set(rows.map { $0.id })

            // Clear tombstones for meals confirmed gone from Supabase.
            // Only safe here — not in supabaseDelete — because PostgREST returns
            // 200 OK even when RLS silently blocks the delete (0 rows affected).
            let confirmedDeleted = deletedMealIDs.filter { !remoteRowIDs.contains($0) }
            confirmedDeleted.forEach { deletedMealIDs.remove($0) }
            if !confirmedDeleted.isEmpty { persistDeletedIDs() }

            // Clear pending-upload flags for meals now confirmed in Supabase.
            let confirmedUploaded = pendingUploadIDs.filter { remoteRowIDs.contains($0) }
            confirmedUploaded.forEach { pendingUploadIDs.remove($0) }
            if !confirmedUploaded.isEmpty { persistPendingUploadIDs() }

            // Re-fire delete for tombstoned meals still present remotely
            // (keeps retrying until RLS allows it — e.g. after migration is applied).
            let staleRows = rows.filter { deletedMealIDs.contains($0.id) }
            for row in staleRows { Task { await supabaseDelete(id: row.id) } }

            let remoteMeals = rows.filter { !deletedMealIDs.contains($0.id) }.map { $0.toMeal() }
            let remoteIDs = Set(remoteMeals.map { $0.id })

            // Only treat a local meal as "pending upload" if it was explicitly
            // registered as such (created locally, upsert not yet confirmed).
            // This prevents meals deleted by other users from being re-uploaded
            // just because they still exist in this device's UserDefaults.
            let pendingLocal = meals.filter {
                !remoteIDs.contains($0.id) &&
                !deletedMealIDs.contains($0.id) &&
                pendingUploadIDs.contains($0.id)
            }
            meals = remoteMeals + pendingLocal
            persist()
            if UserPreferences.shared.notifMeals {
                notif.scheduleMealReminders(meals: meals)
            }
            for m in pendingLocal { Task { await supabaseUpsert(m) } }
        } catch {
            Logger.meals.error("fetch meals error: \(error.localizedDescription)")
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

    private func supabaseUpsert(_ meal: Meal) async {
        await resolveIDs()
        guard let uid = cachedUserID, let hid = cachedHouseholdID else { return }
        // Bail early if the meal was deleted before the network call starts.
        guard !deletedMealIDs.contains(meal.id) else { return }
        let row = SupabaseMealRow(from: meal, userId: uid, householdId: hid)
        do {
            try await supabase.from("meals").upsert(row, onConflict: "id").execute()
            if deletedMealIDs.contains(meal.id) {
                // Meal was deleted while upsert was in-flight — undo the upsert
                // so the row doesn't linger in Supabase for other users to see.
                await supabaseDelete(id: meal.id)
            } else {
                pendingUploadIDs.remove(meal.id)
                persistPendingUploadIDs()
            }
        } catch {
            Logger.meals.error("upsert meal error: \(error.localizedDescription)")
        }
    }

    /// Inserts (or replaces) a `notification_schedule` row that fires at 8 PM
    /// the evening before `mealDate`, consolidating all meals for that day into
    /// a single push. If no meals remain for the date the row is deleted only.
    private func scheduleMealPush(forDate mealDate: Date) async {
        guard let hid = cachedHouseholdID else { return }
        let cal          = Calendar.current
        let dayStart     = cal.startOfDay(for: mealDate)
        let dateKey      = MealPlanViewModel.isoFmt.string(from: dayStart)

        // Remove any existing unsent meal push for this date so we can replace it.
        do {
            try await supabase
                .from("notification_schedule")
                .delete()
                .eq("household_id", value: hid.uuidString)
                .eq("source",       value: "meal")
                .eq("meal_date",    value: dateKey)
                .eq("sent",         value: false)
                .execute()
        } catch {
            Logger.meals.error("cancel meal push schedule error: \(error.localizedDescription)")
        }

        let mealsForDate = meals.filter { cal.isDate($0.date, inSameDayAs: dayStart) }
        guard !mealsForDate.isEmpty else { return }

        // 8 PM the evening before, in the device's local timezone.
        guard let dayBefore = cal.date(byAdding: .day, value: -1, to: dayStart) else { return }
        var comp    = cal.dateComponents([.year, .month, .day], from: dayBefore)
        comp.hour   = 20
        comp.minute = 0
        guard let fireAt = cal.date(from: comp), fireAt > Date() else { return }

        // Consolidated meal summary (same format as local notification).
        let names = mealsForDate
            .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }
            .map { $0.name }
        let summary: String
        switch names.count {
        case 1:  summary = names[0]
        case 2:  summary = "\(names[0]) and \(names[1])"
        default:
            let leading = names.dropLast().joined(separator: ", ")
            summary = names.last.map { "\(leading) and \($0)" } ?? leading
        }
        let weekdayLabel = Meal.Weekday.from(
            calendarWeekday: cal.component(.weekday, from: dayStart)
        ).label

        struct Row: Encodable {
            let householdId: UUID
            let fireAt:      Date
            let title:       String
            let body:        String
            let source:      String
            let mealDate:    String
            enum CodingKeys: String, CodingKey {
                case householdId = "household_id"
                case fireAt      = "fire_at"
                case title, body, source
                case mealDate    = "meal_date"
            }
        }

        do {
            try await supabase
                .from("notification_schedule")
                .insert(Row(
                    householdId: hid,
                    fireAt:      fireAt,
                    title:       "🍽️ Tomorrow's Meals",
                    body:        "\(weekdayLabel): \(summary)",
                    source:      "meal",
                    mealDate:    dateKey
                ))
                .execute()
        } catch {
            Logger.meals.error("scheduleMealPush error: \(error.localizedDescription)")
        }
    }

    private func supabaseDelete(id: UUID) async {
        do {
            try await supabase.from("meals").delete().eq("id", value: id.uuidString).execute()
            // Do NOT clear the tombstone here. PostgREST returns 200 OK even when
            // RLS blocks the delete (0 rows affected, no Swift error), so clearing
            // here would let loadFromSupabase re-fetch and restore the meal.
            // Tombstones are cleared in loadFromSupabase once the row is confirmed
            // gone, or in applyRealtimeChange when the Realtime DELETE event arrives.
        } catch {
            Logger.meals.error("delete meal error: \(error.localizedDescription)")
        }
    }

    // MARK: - Realtime

    private func startRealtimeSubscription() {
        guard let hid = cachedHouseholdID else { return }

        // Unique suffix avoids getting a cached channel back if the previous
        // ViewModel's async removeChannel() call hasn't completed yet.
        let channel = supabase.realtimeV2.channel("meals:\(hid.uuidString):\(UUID().uuidString)")
        realtimeChannel = channel

        realtimeTask = Task { [weak self, channel] in
            // Register listener BEFORE subscribing (SDK requirement).
            // Pass lowercase UUID — Realtime CDC delivers UUIDs lowercase.
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "meals",
                filter: .eq("household_id", value: hid.uuidString.lowercased())
            )

            do {
                try await channel.subscribeWithError()
            } catch {
                Logger.realtime.error("meals subscribe error: \(error.localizedDescription)")
                await MainActor.run { [weak self] in self?.realtimeTask = nil }
                return
            }

            for await change in changes {
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in self?.applyRealtimeChange(change) }
            }

            if !Task.isCancelled {
                await MainActor.run { [weak self] in self?.realtimeTask = nil }
            }
        }
    }

    // Apply a CDC event directly — no network round-trip, instant UI update.
    private func applyRealtimeChange(_ change: AnyAction) {
        switch change {
        case .insert(let action):
            guard let meal = decodeMealFromRecord(action.record) else { return }
            guard !deletedMealIDs.contains(meal.id) else { return }
            meals.removeAll { $0.id == meal.id }
            meals.append(meal)

        case .update(let action):
            guard let meal = decodeMealFromRecord(action.record) else { return }
            guard !deletedMealIDs.contains(meal.id) else { return }
            if let idx = meals.firstIndex(where: { $0.id == meal.id }) {
                meals[idx] = meal
            } else {
                meals.append(meal)
            }

        case .delete(let action):
            if case .string(let idStr) = action.oldRecord["id"],
               let id = UUID(uuidString: idStr) {
                // Row is confirmed deleted by Supabase — safe to clear tombstone.
                deletedMealIDs.remove(id)
                persistDeletedIDs()
                meals.removeAll { $0.id == id }
            } else {
                // oldRecord is empty (REPLICA IDENTITY not yet FULL) — reload to
                // find what was removed. No debounce: delete must be fast.
                Task { [weak self] in await self?.loadFromSupabase() }
                return
            }

        }

        persist()
        if UserPreferences.shared.notifMeals {
            notif.scheduleMealReminders(meals: meals)
        }
        objectWillChange.send()
    }

    private func decodeMealFromRecord(_ record: [String: AnyJSON]) -> Meal? {
        guard let data = try? JSONEncoder().encode(record),
              let row  = try? JSONDecoder().decode(SupabaseMealRow.self, from: data)
        else { return nil }
        return row.toMeal()
    }

    private func supabaseDeleteFuture() async {
        await resolveIDs()
        guard let uid = cachedUserID else { return }
        let todayStr = MealPlanViewModel.isoFmt.string(from: Calendar.current.startOfDay(for: Date()))
        do {
            if let hid = cachedHouseholdID {
                try await supabase.from("meals").delete()
                    .eq("household_id", value: hid.uuidString)
                    .gte("meal_date", value: todayStr)
                    .execute()
            } else {
                try await supabase.from("meals").delete()
                    .eq("created_by", value: uid.uuidString)
                    .gte("meal_date", value: todayStr)
                    .execute()
            }
        } catch {
            Logger.meals.error("delete future meals error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Supabase row mapping
private struct SupabaseMealRow: Codable {
    let id:              UUID
    let householdId:     UUID
    var name:            String
    var day:             Int
    var mealDate:        String?   // "yyyy-MM-dd" — nil for rows created before migration
    var mealType:        String
    var ingredients:     [GroceryItem]
    var notes:           String
    var prepTimeMinutes: Int
    var servings:        Int
    let createdBy:       UUID

    enum CodingKeys: String, CodingKey {
        case id
        case householdId     = "household_id"
        case name
        case day
        case mealDate        = "meal_date"
        case mealType        = "meal_type"
        case ingredients
        case notes
        case prepTimeMinutes = "prep_time_minutes"
        case servings
        case createdBy       = "created_by"
    }

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(from meal: Meal, userId: UUID, householdId: UUID) {
        id               = meal.id
        createdBy        = userId
        self.householdId = householdId
        name             = meal.name
        day              = meal.day.rawValue
        mealDate         = Self.iso.string(from: meal.date)
        mealType         = meal.mealType.rawValue
        ingredients      = meal.ingredients
        notes            = meal.notes
        prepTimeMinutes  = meal.prepTimeMinutes
        servings         = meal.servings
    }

    func toMeal() -> Meal {
        let cal = Calendar.current
        let date: Date
        if let mealDate, let d = Self.iso.date(from: mealDate) {
            date = cal.startOfDay(for: d)
        } else {
            // Fallback for rows created before the meal_date column was added
            let weekday = Meal.Weekday(rawValue: day) ?? .monday
            date = weekday.dateInCurrentWeek()
        }
        return Meal(
            id:              id,
            name:            name,
            date:            date,
            mealType:        Meal.MealType(rawValue: mealType) ?? .dinner,
            ingredients:     ingredients,
            notes:           notes,
            prepTimeMinutes: prepTimeMinutes,
            servings:        servings,
            createdBy:       createdBy.uuidString
        )
    }
}
