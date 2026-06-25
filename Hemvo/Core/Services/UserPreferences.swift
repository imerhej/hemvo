// UserPreferences.swift
// Hemvo
// Source of truth for the 5 user preference keys.
// Writes to UserDefaults (instant local cache) and Supabase profiles
// (authoritative, follows the Hemvo account across all devices).
// On login, AuthViewModel calls seed(from:) to populate from the profile.

internal import Foundation
internal import SwiftUI
internal import Combine
internal import OSLog
internal import Supabase


@MainActor
final class UserPreferences: ObservableObject {

    static let shared = UserPreferences()

    private let ud = UserDefaults.standard
    // True while seeding from a remote profile so didSet handlers skip Supabase writes.
    private var isSyncing = false
    private var saveTask: Task<Void, Never>?

    // MARK: - Published preferences

    @Published var notifBills: Bool {
        didSet {
            guard !isSyncing else { return }
            ud.set(notifBills, forKey: "notif_bills")
            scheduleSupabaseSave()
        }
    }
    @Published var notifMeals: Bool {
        didSet {
            guard !isSyncing else { return }
            ud.set(notifMeals, forKey: "notif_meals")
            scheduleSupabaseSave()
        }
    }
    @Published var notifSchedule: Bool {
        didSet {
            guard !isSyncing else { return }
            ud.set(notifSchedule, forKey: "notif_schedule")
            scheduleSupabaseSave()
        }
    }
    @Published var notifMaintenance: Bool {
        didSet {
            guard !isSyncing else { return }
            ud.set(notifMaintenance, forKey: "notif_maintenance")
            scheduleSupabaseSave()
        }
    }
    @Published var avatarColor: String {
        didSet {
            guard !isSyncing else { return }
            ud.set(avatarColor, forKey: "hemvo_avatarColor")
            // avatarColor is persisted to Supabase by AuthService.updateProfile(),
            // not here — no scheduleSupabaseSave() call needed.
        }
    }

    // MARK: - Init

    private init() {
        ud.register(defaults: [
            "notif_bills":       true,
            "notif_meals":       true,
            "notif_schedule":    true,
            "notif_maintenance": true,
            "hemvo_avatarColor":    "#4CAF74",
        ])
        notifBills       = ud.bool(forKey: "notif_bills")
        notifMeals       = ud.bool(forKey: "notif_meals")
        notifSchedule    = ud.bool(forKey: "notif_schedule")
        notifMaintenance = ud.bool(forKey: "notif_maintenance")
        avatarColor      = ud.string(forKey: "hemvo_avatarColor") ?? "#4CAF74"
    }

    // MARK: - Seed from Supabase profile

    /// Called by AuthViewModel.loadProfile() after a successful profile fetch.
    /// Overwrites local cache with the authoritative Supabase values.
    /// Owner-disabled permissions override the flat columns so local notification
    /// scheduling is suppressed even if the DB write hasn't propagated yet.
    func seed(from profile: HemvoProfile) {
        isSyncing = true
        defer { isSyncing = false }
        let perms = profile.permissions
        let bills       = perms?.receiveExpenseAlerts     == false ? false : profile.notifBills
        let meals       = perms?.receiveMealAlerts        == false ? false : profile.notifMeals
        let schedule    = perms?.receiveCalendarAlerts    == false ? false : profile.notifSchedule
        let maintenance = perms?.receiveMaintenanceAlerts == false ? false : profile.notifMaintenance
        if let v = bills        { notifBills = v;       ud.set(v, forKey: "notif_bills") }
        if let v = meals        { notifMeals = v;       ud.set(v, forKey: "notif_meals") }
        if let v = schedule     { notifSchedule = v;    ud.set(v, forKey: "notif_schedule") }
        if let v = maintenance  { notifMaintenance = v; ud.set(v, forKey: "notif_maintenance") }
        if let v = profile.avatarColor { avatarColor = v; ud.set(v, forKey: "hemvo_avatarColor") }
    }

    // MARK: - Account deletion cleanup

    func clearAll() {
        saveTask?.cancel()
        let keys = ["notif_bills", "notif_meals", "notif_schedule", "notif_maintenance", "hemvo_avatarColor"]
        keys.forEach { ud.removeObject(forKey: $0) }
    }

    // MARK: - Supabase write (debounced, off main actor)

    private func scheduleSupabaseSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s debounce
            guard !Task.isCancelled,
                  let uid = supabase.auth.currentSession?.user.id else { return }
            let payload: [String: Bool] = [
                "notif_bills":       self.notifBills,
                "notif_meals":       self.notifMeals,
                "notif_schedule":    self.notifSchedule,
                "notif_maintenance": self.notifMaintenance,
            ]
            do {
                try await supabase
                    .from("profiles")
                    .update(payload)
                    .eq("id", value: uid.uuidString)
                    .execute()
            } catch {
                Logger.prefs.error("Failed to save notification prefs: \(error.localizedDescription)")
            }
        }
    }
}
