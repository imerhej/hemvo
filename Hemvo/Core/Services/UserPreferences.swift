// UserPreferences.swift
// Hemvo
// Single source of truth for the 5 user preference keys.
// Writes to both UserDefaults (immediate, always works) and
// NSUbiquitousKeyValueStore (iCloud KV, when entitlement is present).
// When iCloud delivers an external change the @Published values update
// automatically, which refreshes any observing SwiftUI view.
//
// To enable iCloud KV sync: add the iCloud capability in Xcode
// Signing & Capabilities → iCloud → Key-value storage, then
// add com.apple.developer.ubiquity-kvstore-identifier to both
// entitlement files. No paid account feature beyond standard iCloud.

internal import Foundation
internal import SwiftUI
internal import Combine

@MainActor
final class UserPreferences: ObservableObject {

    static let shared = UserPreferences()

    // MARK: - Backing stores

    private let kv = NSUbiquitousKeyValueStore.default
    private let ud = UserDefaults.standard

    // Prevents writing back to both stores when we're mid-pull from iCloud.
    private var isSyncing = false

    // MARK: - Published preferences

    @Published var notifBills: Bool {
        didSet { guard !isSyncing else { return }; write("notif_bills", notifBills) }
    }
    @Published var notifMeals: Bool {
        didSet { guard !isSyncing else { return }; write("notif_meals", notifMeals) }
    }
    @Published var notifSchedule: Bool {
        didSet { guard !isSyncing else { return }; write("notif_schedule", notifSchedule) }
    }
    @Published var notifMaintenance: Bool {
        didSet { guard !isSyncing else { return }; write("notif_maintenance", notifMaintenance) }
    }
    @Published var avatarColor: String {
        didSet { guard !isSyncing else { return }; write("hb_avatarColor", avatarColor) }
    }

    // MARK: - Init

    private init() {
        // Seed UserDefaults defaults so first-launch reads return true.
        ud.register(defaults: [
            "notif_bills":       true,
            "notif_meals":       true,
            "notif_schedule":    true,
            "notif_maintenance": true,
            "hb_avatarColor":    "#4CAF74",
        ])

        // Load from UserDefaults first (always available).
        notifBills       = ud.bool(forKey: "notif_bills")
        notifMeals       = ud.bool(forKey: "notif_meals")
        notifSchedule    = ud.bool(forKey: "notif_schedule")
        notifMaintenance = ud.bool(forKey: "notif_maintenance")
        avatarColor      = ud.string(forKey: "hb_avatarColor") ?? "#4CAF74"

        // Override with iCloud KV values if present (another device may have
        // synced a newer value before this device was launched).
        pullFromiCloud()

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kv,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pullFromiCloud()
            }
        }
    }

    // MARK: - iCloud pull

    private func pullFromiCloud() {
        isSyncing = true
        defer { isSyncing = false }

        if let v = kv.object(forKey: "notif_bills")       as? Bool { notifBills = v;       ud.set(v, forKey: "notif_bills") }
        if let v = kv.object(forKey: "notif_meals")       as? Bool { notifMeals = v;       ud.set(v, forKey: "notif_meals") }
        if let v = kv.object(forKey: "notif_schedule")    as? Bool { notifSchedule = v;    ud.set(v, forKey: "notif_schedule") }
        if let v = kv.object(forKey: "notif_maintenance") as? Bool { notifMaintenance = v; ud.set(v, forKey: "notif_maintenance") }
        if let v = kv.string(forKey: "hb_avatarColor")            { avatarColor = v;       ud.set(v, forKey: "hb_avatarColor") }
    }

    // MARK: - Write helpers

    private func write(_ key: String, _ value: Bool) {
        ud.set(value, forKey: key)
        kv.set(value, forKey: key)
        kv.synchronize()
    }

    private func write(_ key: String, _ value: String) {
        ud.set(value, forKey: key)
        kv.set(value, forKey: key)
        kv.synchronize()
    }

    // MARK: - Account deletion cleanup

    func clearAll() {
        let keys = ["notif_bills", "notif_meals", "notif_schedule", "notif_maintenance", "hb_avatarColor"]
        keys.forEach { ud.removeObject(forKey: $0); kv.removeObject(forKey: $0) }
        kv.synchronize()
    }
}
