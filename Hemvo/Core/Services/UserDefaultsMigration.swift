// UserDefaultsMigration.swift
// Hemvo
//
// One-time migration from legacy hb_ UserDefaults keys to hemvo_ prefix.
// Called from HemvoApp.init() before any ViewModel or View loads.

internal import Foundation
internal import UserNotifications

enum UserDefaultsMigration {

    private static let migrationKey = "hemvo_migrated_v1"

    static func runIfNeeded() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: migrationKey) else { return }

        // 1. Rename every hb_* UserDefaults key to hemvo_* in one pass.
        //    Handles both simple keys ("hb_meals") and compound ones
        //    ("hb_meals_hh_A3KZ9P", "hb_meals_user_<uuid>").
        let snapshot = ud.dictionaryRepresentation()
        for (oldKey, value) in snapshot where oldKey.hasPrefix("hb_") {
            let newKey = "hemvo_" + oldKey.dropFirst("hb_".count)
            ud.set(value, forKey: newKey)
            ud.removeObject(forKey: oldKey)
        }

        // 2. Move APNs token from the renamed UserDefaults entry to Keychain.
        //    PushNotificationService now reads/writes from Keychain exclusively.
        if let token = ud.string(forKey: "hemvo_apns_token") {
            KeychainHelper.shared.saveString(token, key: "hemvo_apns_token", iCloudSync: false)
            ud.removeObject(forKey: "hemvo_apns_token")
        }

        // 3. Cancel all pending local notifications — their request identifiers
        //    change from hb_ to hemvo_ prefix. The app reschedules them on the
        //    next scheduleTomorrowReminders() call at the end of HemvoApp.init().
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        ud.set(true, forKey: migrationKey)
    }
}
