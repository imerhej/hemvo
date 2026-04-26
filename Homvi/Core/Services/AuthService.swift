// AuthService.swift — Homvi
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
    /// Creates a new Supabase auth user. Username is stored in user_metadata
    /// so the `handle_new_user` DB trigger can write it to the profiles table.
    func createAccount(email: String, password: String,
                       fullName: String, username: String) async throws {
        // Reject immediately if the username is already taken (avoids a
        // partial-failure where auth.users gets a row but profiles doesn't).
        guard try await isUsernameAvailable(username) else {
            throw AuthError.usernameTaken
        }
        try await supabase.auth.signUp(
            email: email,
            password: password,
            data: [
                "full_name": .string(fullName),
                "username":  .string(username.lowercased().trimmingCharacters(in: .whitespaces))
            ]
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
    func currentUserID() async -> UUID? {
        try? await supabase.auth.session.user.id
    }

    // MARK: - Current User Email
    func currentUserEmail() async -> String? {
        try? await supabase.auth.session.user.email
    }

    // MARK: - Session Restore
    func restoreSession() async -> Bool {
        do {
            _ = try await supabase.auth.session
            return true
        } catch {
            return false
        }
    }

    // MARK: - Change Password
    func changePassword(to newPassword: String) async throws {
        try await supabase.auth.update(user: UserAttributes(password: newPassword))
    }

    // MARK: - Delete Account
    // Calls the `delete_my_account` Postgres RPC (SECURITY DEFINER) which
    // deletes the profile row, cascades household data if the user is the
    // sole member, and removes the auth.users entry — all in one transaction.
    func deleteAccount() async throws {
        try await supabase.rpc("delete_my_account").execute()
    }

    // MARK: - Password Reset Email
    func sendPasswordReset(to email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email)
    }

    // MARK: - Load Profile
    func loadProfile() async throws -> HomviProfile {
        guard let uid = await currentUserID() else { throw AuthError.notLoggedIn }
        let profile: HomviProfile = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: uid)
            .single()
            .execute()
            .value
        return profile
    }

    // MARK: - Update Profile
    func updateProfile(fullName: String, avatarColor: String) async throws {
        guard let uid = await currentUserID() else { throw AuthError.notLoggedIn }
        try await supabase
            .from("profiles")
            .update(["full_name": fullName, "avatar_color": avatarColor])
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

// MARK: - HomviProfile Model
struct HomviProfile: Codable, Identifiable {
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
