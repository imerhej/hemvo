
// AuthViewModel.swift
// Homvi
//
// Rewritten to use Supabase AuthService.
// All session management, user storage, and password handling
// now goes through Supabase — no more UserDefaults user store.
//
// BIOMETRIC SAFETY (carried forward):
// • evaluateBiometric is `private nonisolated static` + wrapped in
//   withCheckedContinuation so it never runs on MainActor.
// • isBiometricEnabled is plain @Published, loaded in init(), saved manually.
// • biometricType is a plain computed var — lazy var is not actor-safe.

internal import SwiftUI
internal import LocalAuthentication
internal import Foundation
internal import Combine
internal import CoreData
internal import UserNotifications

@MainActor
final class AuthViewModel: ObservableObject {

    // MARK: - Published state
    @Published var isLoggedIn:           Bool          = false
    @Published var isSubscriptionActive: Bool          = false
    @Published var trialDaysRemaining:   Int           = 0
    @Published var profile:              HomviProfile? = nil
    @Published var isLoading:            Bool          = false
    @Published var errorMessage:         String?       = nil
    @Published var isBiometricEnabled:   Bool          = false
    /// True while the initial Supabase session check is in flight.
    /// RootView shows a splash screen until this is false so the router
    /// never evaluates household/paywall state before auth is known.
    @Published var isCheckingSession:    Bool          = true

    // MARK: - Dependencies
    private let auth     = AuthService.shared
    private let storeKit = StoreKitService.shared

    // MARK: - Init
    init() {
        isBiometricEnabled = UserDefaults.standard.bool(forKey: "homvi_biometricEnabled")
        Task {
            await checkSession()
            isCheckingSession = false
        }
    }

    // MARK: - Convenience: current user ID
    var currentUserID: UUID? {
        get async { await auth.currentUserID() }
    }

    // MARK: - Trial helpers
    var trialHasStarted: Bool {
        UserDefaults.standard.object(forKey: "homvi_trialEndDate") as? Date != nil
    }

    var trialExpired: Bool {
        guard !isSubscriptionActive else { return false }
        if let end = UserDefaults.standard.object(forKey: "homvi_trialEndDate") as? Date {
            return end < Date()
        }
        return false
    }

    // MARK: - Session restore on launch
    func checkSession() async {
        let active = await auth.restoreSession()
        if active {
            isLoggedIn = true
            await loadProfile()
            if profile == nil {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await loadProfile()
            }
            await refreshSubscriptionStatus()
        }
    }

    // MARK: - Load profile from Supabase
    func loadProfile() async {
        do {
            profile = try await auth.loadProfile()
        } catch {
            // Not fatal — profile may not exist yet for brand new users
            print("Profile load error: \(error.localizedDescription)")
        }
    }

    // MARK: - Sign Up
    // Supabase sends a confirmation email automatically.
    // The user must tap the link in their email before they can log in.
    // We do NOT set isLoggedIn = true here — the user isn't verified yet.
    // Returns true on success so the caller can show a dedicated success state.
    @discardableResult
    func signUp(name: String, email: String, username: String, password: String) async -> Bool {
        isLoading    = true
        errorMessage = nil
        do {
            try await auth.createAccount(
                email:    email,
                password: password,
                fullName: name,
                username: username
            )
            isLoading = false
            return true
        } catch {
            errorMessage = friendlyAuthError(error)
            isLoading = false
            return false
        }
    }

    // MARK: - Friendly error messages
    private func friendlyAuthError(_ error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("rate limit") || raw.contains("too many") || raw.contains("429") {
            return "Too many sign-up attempts. Please wait a few minutes and try again."
        }
        if raw.contains("already registered") || raw.contains("already been registered") {
            return "An account with this email already exists. Please sign in instead."
        }
        if raw.contains("invalid email") {
            return "Please enter a valid email address."
        }
        if raw.contains("weak password") || raw.contains("password should be") {
            return "Password must be at least 8 characters with an uppercase letter and a number."
        }
        if raw.contains("invalid login credentials") || raw.contains("invalid credentials") {
            return "Incorrect email/username or password. Please try again."
        }
        if raw.contains("email not confirmed") {
            return "Please confirm your email first. Check your inbox for a confirmation link."
        }
        if raw.contains("network") || raw.contains("offline") || raw.contains("connection") {
            return "No internet connection. Please check your network and try again."
        }
        return error.localizedDescription
    }

    // MARK: - Login
    func login(emailOrUsername: String, password: String) async {
        isLoading    = true
        errorMessage = nil
        do {
            try await auth.login(emailOrUsername: emailOrUsername, password: password)
            isLoggedIn = true
            await loadProfile()
            // Retry once — the DB trigger that creates the profiles row
            // runs asynchronously and may not have finished yet.
            if profile == nil {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await loadProfile()
            }
            await refreshSubscriptionStatus()
            // Start trial on first ever login if not already started
            if !trialHasStarted {
                startTrial()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await offerBiometricEnrollment()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Sign in with Apple
    func loginWithApple() {
        Task {
            isLoading    = true
            errorMessage = nil
            do {
                let result = try await SocialAuthService.shared.signInWithApple()
                await completeSocialLogin(result)
            } catch let err as SocialAuthError where err == .cancelled {
                // Silent — user dismissed the sheet
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Sign in with Google
    func loginWithGoogle() {
        let vc = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController
        guard let vc else { return }

        Task {
            isLoading    = true
            errorMessage = nil
            do {
                let result = try await SocialAuthService.shared.signInWithGoogle(
                    presentingViewController: vc)
                await completeSocialLogin(result)
            } catch let err as SocialAuthError where err == .cancelled {
                // Silent
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Social login completion
    private func completeSocialLogin(_ result: SocialAuthResult) async {
        do {
            // Try signing in first — account may already exist
            try await auth.login(emailOrUsername: result.email, password: result.email)
            isLoggedIn = true
            await loadProfile()
            await refreshSubscriptionStatus()
        } catch {
            // Account doesn't exist — create it with a random password
            // (social users authenticate via Apple/Google, not this password)
            let username = result.email
                .components(separatedBy: "@").first?
                .replacingOccurrences(of: ".", with: "_")
                ?? UUID().uuidString
            do {
                try await auth.createAccount(
                    email:    result.email,
                    password: UUID().uuidString,
                    fullName: result.name,
                    username: username
                )
                isLoggedIn = true
                startTrial()
                await loadProfile()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await offerBiometricEnrollment()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Biometrics
    func loginWithBiometrics() {
        guard !isLoading else { return }
        guard Self.biometricHardwareAvailable() else {
            errorMessage = "\(biometricLabel) is not available on this device."
            return
        }
        Task {
            isLoading    = true
            errorMessage = nil
            let success  = await Self.evaluateBiometric(reason: "Sign in to Homvi")
            if success {
                // Restore the existing Supabase session
                let restored = await auth.restoreSession()
                if restored {
                    isLoggedIn = true
                    await loadProfile()
                    await refreshSubscriptionStatus()
                } else {
                    errorMessage = "No saved session. Please sign in with your password."
                }
            }
            isLoading = false
        }
    }

    func enableBiometrics() async -> Bool {
        guard Self.biometricHardwareAvailable() else {
            errorMessage = "\(biometricLabel) is not available on this device."
            return false
        }
        let success = await Self.evaluateBiometric(
            reason: "Enable \(biometricLabel) for Homvi")
        if success {
            isBiometricEnabled = true
            UserDefaults.standard.set(true, forKey: "homvi_biometricEnabled")
        }
        return success
    }

    func disableBiometrics() {
        isBiometricEnabled = false
        UserDefaults.standard.set(false, forKey: "homvi_biometricEnabled")
    }

    private nonisolated static func evaluateBiometric(reason: String) async -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Use Password"
        return await withCheckedContinuation { cont in
            ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, _ in
                cont.resume(returning: success)
            }
        }
    }

    nonisolated static func biometricHardwareAvailable() -> Bool {
        var error: NSError?
        let ctx = LAContext()
        return ctx.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    var biometricType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    var biometricLabel: String {
        switch biometricType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        default:       return "Biometrics"
        }
    }

    var biometricIcon: String {
        switch biometricType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        default:       return "lock.shield.fill"
        }
    }

    private func offerBiometricEnrollment() async {
        guard Self.biometricHardwareAvailable() else { return }
        let enrolled = await Self.evaluateBiometric(
            reason: "Enable biometric login for Homvi")
        if enrolled {
            isBiometricEnabled = true
            UserDefaults.standard.set(true, forKey: "homvi_biometricEnabled")
        }
    }

    // MARK: - Convenience: current username
    var currentUsername: String? { profile?.username }

    // MARK: - Password change
    func changePassword(currentPassword: String, newPassword: String) async -> Bool {
        do {
            try await auth.changePassword(to: newPassword)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Trial
    private func startTrial() {
        let end = Calendar.current.date(
            byAdding: .day,
            value: AppConstants.trialDurationDays,
            to: Date()
        ) ?? Date()
        UserDefaults.standard.set(end, forKey: "homvi_trialEndDate")
        trialDaysRemaining   = AppConstants.trialDurationDays
        isSubscriptionActive = true
    }

    // MARK: - Subscription
    func refreshSubscriptionStatus() async {
        // First check StoreKit for active paid subscription
        let hasSub = await storeKit.hasActiveSubscription()
        if hasSub {
            isSubscriptionActive = true
            trialDaysRemaining   = 0
            return
        }
        // Fall back to local trial end date
        if let end = UserDefaults.standard.object(
            forKey: "homvi_trialEndDate") as? Date {
            let days = Calendar.current.dateComponents(
                [.day], from: Date(), to: end).day ?? 0
            trialDaysRemaining   = max(days, 0)
            isSubscriptionActive = days > 0
        } else {
            isSubscriptionActive = false
            trialDaysRemaining   = 0
        }
    }

    // MARK: - Sign Out
    func signOut() {
        Task {
            try? await auth.signOut()
        }
        isLoggedIn           = false
        isSubscriptionActive = false
        trialDaysRemaining   = 0
        profile              = nil
    }

    // MARK: - Delete Account
    func deleteAccount() async {
        // 1. Delete from Supabase — removes auth.users + profile + household data
        //    via the `delete_my_account` RPC (SECURITY DEFINER Postgres function).
        //    If the RPC fails (no network, already deleted, etc.) we still clear
        //    local data and sign the user out so they are not left stuck.
        do {
            try await auth.deleteAccount()
        } catch {
            print("[Auth] deleteAccount RPC error: \(error.localizedDescription)")
        }

        // 2. Clear local UserDefaults cache
        let keysToRemove: [String] = [
            "homvi_trialEndDate", "homvi_biometricEnabled",
            "hb_meals", "hb_expenses", "hb_events", "hb_tasks",
            "hb_members", "hb_maintenanceItems", "hb_maintenanceHistory",
            "hb_paymentCards", "hb_avatarColor",
            "notif_bills", "notif_meals", "notif_schedule", "notif_maintenance",
            "hb_groceryItems", "hb_shoppingLists", "hb_budget",
            "hb_seasonalCompleted", "hb_seasonalItemsV3",
            "hb_household_v2", "hb_householdInvites_v2",
        ]
        let ud = UserDefaults.standard
        keysToRemove.forEach { ud.removeObject(forKey: $0) }

        // 3. Clear CoreData
        let context     = PersistenceService.shared.container.viewContext
        let entityNames = PersistenceService.shared.container
            .managedObjectModel.entities.compactMap { $0.name }
        for name in entityNames {
            let fetch  = NSFetchRequest<NSFetchRequestResult>(entityName: name)
            let delete = NSBatchDeleteRequest(fetchRequest: fetch)
            _ = try? context.execute(delete)
        }
        try? context.save()

        // 4. Clear local notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        // 5. The RPC already deleted the auth.users row, so the session is
        //    invalidated server-side. Sign out locally to clear the token cache.
        try? await auth.signOut()

        isLoggedIn           = false
        isSubscriptionActive = false
        trialDaysRemaining   = 0
        profile              = nil
    }
}
