// AuthService.swift — Hemvo
// All auth operations go through Supabase.
// login() accepts email OR username — if no "@" is present it resolves
// the username to an email via the profiles table first.

internal import Foundation
internal import Supabase

@MainActor
final class AuthService {

    // MARK: - Singleton
    static let shared = AuthService()
    private init() {}

    // MARK: - Sign Up
    /// Creates a new account via the `create-account` Edge Function.
    /// The Edge Function uses the admin API so GoTrue's SMTP path is never
    /// triggered — the root cause of the previous "user created then deleted"
    /// bug. Confirmation email is sent by the function via Resend.
    func createAccount(email: String, password: String,
                       fullName: String, username: String) async throws {
        guard try await isUsernameAvailable(username) else {
            throw AuthError.usernameTaken
        }
        struct Payload: Encodable {
            let email, password, username: String
            let fullName: String
            enum CodingKeys: String, CodingKey {
                case email, password, username
                case fullName = "full_name"
            }
        }
        try await supabase.functions.invoke(
            "create-account",
            options: FunctionInvokeOptions(body: Payload(
                email:    email,
                password: password,
                username: username.lowercased().trimmingCharacters(in: .whitespaces),
                fullName: fullName
            ))
        )
    }

    // MARK: - Login (email or username)
    func login(emailOrUsername: String, password: String) async throws {
        let email: String
        if emailOrUsername.contains("@") {
            email = emailOrUsername.lowercased().trimmingCharacters(in: .whitespaces)
        } else {
            email = try await emailForUsername(emailOrUsername)
        }
        try await supabase.auth.signIn(email: email, password: password)
    }

    // MARK: - Sign Out
    func signOut() async throws {
        try await supabase.auth.signOut()
    }

    // MARK: - Current User ID
    // nonisolated — same reason as changePassword: calling supabase.auth.session
    // from the main actor can deadlock when a token refresh network call is needed.
    nonisolated func currentUserID() async -> UUID? {
        try? await supabase.auth.session.user.id
    }

    // MARK: - Current User Email
    nonisolated func currentUserEmail() async -> String? {
        try? await supabase.auth.session.user.email
    }

    // MARK: - Session Restore
    // nonisolated — Supabase token refresh posts callbacks that may need the main
    // actor; calling this FROM the main actor causes a deadlock in those cases.
    nonisolated func restoreSession() async -> Bool {
        do {
            _ = try await supabase.auth.session
            return true
        } catch {
            return false
        }
    }

    // MARK: - Change Password (authenticated user, requires current password)
    // Uses a SECURITY DEFINER RPC instead of supabase.auth.signIn + auth.update.
    // auth.updateUser triggers Supabase's secure_password_change enforcement which
    // requires an OTP reauthenticate() flow — not a plain signIn. The RPC verifies
    // the current password via pgcrypto and updates auth.users atomically on the
    // server, which works regardless of that project setting.
    // nonisolated so this runs off the main actor; the Supabase SDK dispatches
    // session callbacks to the main actor internally, and calling these methods
    // from the main actor causes a deadlock.
    nonisolated func changePassword(currentPassword: String, to newPassword: String) async throws {
        guard await currentUserID() != nil else {
            throw AuthError.notLoggedIn
        }
        try await supabase
            .rpc("change_user_password", params: [
                "current_pw": currentPassword,
                "new_pw":     newPassword
            ])
            .execute()
        await sendPasswordChangedNotification()
    }

    // nonisolated — called from nonisolated changePassword; errors are
    // swallowed here so they never surface to the caller.
    private nonisolated func sendPasswordChangedNotification() async {
        struct Empty: Encodable {}
        _ = try? await supabase.functions.invoke(
            "send-password-changed-email",
            options: FunctionInvokeOptions(body: Empty())
        )
    }

    // MARK: - Reset Password (deep-link recovery session, no current password needed)
    // Called from ResetPasswordView after Supabase has validated the reset token.
    // Uses the reset-user-password Edge Function (admin API) to bypass
    // secure_password_change — same reason changePassword uses a custom RPC.
    // nonisolated for the same reason as changePassword above.
    nonisolated func resetPassword(to newPassword: String) async throws {
        struct Payload: Encodable { let newPassword: String }
        try await supabase.functions.invoke(
            "reset-user-password",
            options: FunctionInvokeOptions(body: Payload(newPassword: newPassword))
        )
    }

    // MARK: - Delete Account
    // Deletes all rows owned by the current user across every table that holds a
    // foreign-key reference to auth.users, then calls the `delete_my_account` RPC
    // (SECURITY DEFINER) which removes the profile and the auth.users row.
    // The client-side cleanup is a safety net: ideally the RPC itself should CASCADE
    // these deletes, but until the DB function is updated this prevents FK violations.
    func deleteAccount() async throws {
        guard let uid = await currentUserID() else { throw AuthError.notLoggedIn }

        let tables: [(table: String, column: String)] = [
            ("expenses",       "created_by"),
            ("events",         "created_by"),
            ("meals",          "created_by"),
            ("house_tasks",    "created_by"),
            ("grocery_items",  "created_by"),
            ("shopping_items", "created_by"),
            ("shopping_lists", "created_by"),
            ("device_tokens",  "user_id"),
        ]

        for entry in tables {
            _ = try? await supabase
                .from(entry.table)
                .delete()
                .eq(entry.column, value: uid)
                .execute()
        }

        // If this user owns a household, delete it before the auth.users row is
        // removed. The RLS policy (owner_id = auth.uid()) allows this with the
        // user's own JWT. Deleting the household cascades to events, house_tasks,
        // notification_schedule, and sets profiles.household_id = NULL for any
        // remaining members — so no FK violation reaches delete_my_account.
        if let hh = HouseholdService.shared.household,
           hh.ownerUserID == uid.uuidString {
            _ = try? await supabase
                .from("households")
                .delete()
                .eq("id", value: hh.id)
                .execute()
        }

        try await supabase.rpc("delete_my_account").execute()
    }

    // MARK: - Password Reset Email
    // Calls the send-password-reset-email Edge Function instead of Supabase's
    // built-in email so the message is delivered via Resend from noreply@hemvo.app.
    // The Edge Function uses the service role to generate the recovery link and
    // sends { sent: true } regardless of whether the email exists (prevent enumeration).
    func sendPasswordReset(to email: String) async throws {
        struct Payload: Encodable { let email: String }
        try await supabase.functions.invoke(
            "send-password-reset-email",
            options: FunctionInvokeOptions(body: Payload(email: email))
        )
    }

    // MARK: - Load Profile
    func loadProfile() async throws -> HemvoProfile {
        guard let uid = await currentUserID() else { throw AuthError.notLoggedIn }
        let profile: HemvoProfile = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: uid)
            .single()
            .execute()
            .value
        return profile
    }

    // MARK: - Trial End Date Sync
    func updateTrialEndDate(_ date: Date) async {
        guard let uid = await currentUserID() else { return }
        struct Payload: Encodable {
            let trialEndDate: Date
            enum CodingKeys: String, CodingKey { case trialEndDate = "trial_end_date" }
        }
        _ = try? await supabase
            .from("profiles")
            .update(Payload(trialEndDate: date))
            .eq("id", value: uid)
            .execute()
    }

    // MARK: - Subscription Status Sync

    /// Writes the owner's current subscription state to their Supabase profile row so
    /// members on other devices can read it without needing StoreKit access.
    func updateSubscriptionStatus(isActive: Bool) async {
        guard let uid = await currentUserID() else { return }
        let status = isActive ? "active" : "expired"
        _ = try? await supabase
            .from("profiles")
            .update(["subscription_status": status])
            .eq("id", value: uid.uuidString)
            .execute()
    }

    /// Reads `subscription_status` from the owner's profile row.
    /// Returns `true` (fail-open) on any network error so members aren't wrongly locked out.
    func fetchOwnerSubscriptionStatus(ownerID: String) async -> Bool {
        struct StatusRow: Decodable {
            let subscriptionStatus: String?
            enum CodingKeys: String, CodingKey {
                case subscriptionStatus = "subscription_status"
            }
        }
        guard let row: StatusRow = try? await supabase
            .from("profiles")
            .select("subscription_status")
            .eq("id", value: ownerID)
            .single()
            .execute()
            .value
        else { return true }
        let s = row.subscriptionStatus
        return s == "active" || s == "trial"
    }

    // MARK: - Update Profile
    func updateProfile(fullName: String, username: String, avatarColor: String) async throws {
        guard let uid = await currentUserID() else { throw AuthError.notLoggedIn }
        let trimmedUsername = username.lowercased().trimmingCharacters(in: .whitespaces)
        var payload: [String: String] = ["full_name": fullName, "avatar_color": avatarColor]
        if !trimmedUsername.isEmpty { payload["username"] = trimmedUsername }
        try await supabase
            .from("profiles")
            .update(payload)
            .eq("id", value: uid)
            .execute()
    }

    // MARK: - Username helpers (private)

    /// Calls the `is_username_available` Postgres function (security definer,
    /// so it bypasses RLS and works for unauthenticated callers).
    private func isUsernameAvailable(_ username: String) async throws -> Bool {
        let available: Bool = try await supabase
            .rpc("is_username_available",
                 params: ["p_username": username.lowercased().trimmingCharacters(in: .whitespaces)])
            .execute()
            .value
        return available
    }

    /// Looks up the email address for a given username.
    /// Throws `AuthError.usernameNotFound` if no match.
    private func emailForUsername(_ username: String) async throws -> String {
        struct Row: Decodable { let email: String? }
        let rows: [Row] = try await supabase
            .from("profiles")
            .select("email")
            .eq("username", value: username.lowercased().trimmingCharacters(in: .whitespaces))
            .limit(1)
            .execute()
            .value
        guard let email = rows.first?.email else {
            throw AuthError.usernameNotFound
        }
        return email
    }
}

// MARK: - HemvoProfile Model
struct HemvoProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var fullName: String?
    var email: String?
    var username: String?
    var avatarColor: String?
    var householdId: UUID?
    var role: String?
    var subscriptionStatus: String?
    var trialEndDate: Date?
    var createdAt: Date?
    /// Per-member notification permissions stored as JSONB in Supabase.
    /// nil = use role-based defaults (MemberPermissions.defaults(for:)).
    var permissions: MemberPermissions?
    var disabled: Bool?
    // Notification preferences — nil before migration runs, treated as true.
    var notifBills: Bool?
    var notifMeals: Bool?
    var notifSchedule: Bool?
    var notifMaintenance: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName           = "full_name"
        case email
        case username
        case avatarColor        = "avatar_color"
        case householdId        = "household_id"
        case role
        case subscriptionStatus = "subscription_status"
        case trialEndDate       = "trial_end_date"
        case createdAt          = "created_at"
        case permissions
        case disabled
        case notifBills         = "notif_bills"
        case notifMeals         = "notif_meals"
        case notifSchedule      = "notif_schedule"
        case notifMaintenance   = "notif_maintenance"
    }

    var isInTrial: Bool {
        guard subscriptionStatus == "trial", let end = trialEndDate else { return false }
        return end > Date.now
    }

    var isSubscriptionActive: Bool {
        if isInTrial { return true }
        return subscriptionStatus == "active"
    }

    var trialDaysRemaining: Int {
        guard let end = trialEndDate, isInTrial else { return 0 }
        return Calendar.current.dateComponents([.day], from: .now, to: end).day ?? 0
    }
}

// MARK: - Auth Errors
enum AuthError: LocalizedError {
    case notLoggedIn
    case profileNotFound
    case usernameTaken
    case usernameNotFound

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:      return "You are not logged in."
        case .profileNotFound:  return "Your profile could not be found."
        case .usernameTaken:    return "That username is already taken. Please choose another."
        case .usernameNotFound: return "No account found with that username. Check your spelling or sign in with your email."
        }
    }
}
