internal import Foundation

/// Generates the correct UserDefaults storage key for any piece of shared data.
///
/// **Usage inside a ViewModel:**
/// ```swift
/// private var mealsKey: String {
///     SharedDataKey.make("hemvo_meals", householdService: householdService, userID: currentUserID)
/// }
/// ```
///
/// When the user is in a household → key is `hb_meals_hh_HH-A3KZ9P`
/// When the user is solo           → key is `hb_meals_user_<uuid>`
///
/// This means all household members read/write to the same key, so any data
/// saved by one member is immediately visible to the others (and synced via
/// iCloud/CloudKit across devices).

enum SharedDataKey {

    /// Returns a namespaced key.
    /// - Parameters:
    ///   - base: The base key string, e.g. `"hemvo_meals"`.
    ///   - householdService: The shared HouseholdService singleton.
    ///   - userID: The current user's ID (fallback when no household exists).
    static func make(
        _ base: String,
        householdService: HouseholdService,
        userID: String
    ) -> String {
        householdService.storageKey(base: base, userID: userID)
    }
}

// MARK: - Keyed Base Strings

/// Centralised list of all base key strings used across the app.
/// Update these here rather than in each ViewModel individually.
extension SharedDataKey {
    static let meals        = "hemvo_meals"
    static let groceryItems = "hemvo_groceryItems"
    static let expenses     = "hemvo_expenses"
    static let budget       = "hemvo_budget"
    static let calendarEvents = "hemvo_calendarEvents"
    static let houseTasks   = "hemvo_houseTasks"
    static let maintenance  = "hemvo_maintenance"
    static let householdMembers = "hemvo_householdMembers"
}
