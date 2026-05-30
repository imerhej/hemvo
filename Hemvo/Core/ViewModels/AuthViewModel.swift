
// AuthViewModel.swift
// Hemvo
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
internal import Supabase
internal import Auth

@MainActor
final class AuthViewModel: ObservableObject {

    // MARK: - Published state
    @Published var isLoggedIn:              Bool          = false
    @Published var isSubscriptionActive:    Bool          = false
    @Published var trialDaysRemaining:      Int           = 0
    /// True only after the owner's grace period has fully expired (members only).
    @Published var ownerSubscriptionLapsed: Bool          = false
    /// Days left in the grace window after the owner's sub lapsed (0 when expired or N/A).
    @Published var gracePeriodDaysRemaining: Int          = 0
    @Published var profile:              HemvoProfile? = nil
    /// User UUID read directly from the Supabase session token.
    /// Available immediately after sign-in — does NOT require the profiles
    /// table round-trip that populates `profile`. Use this wherever only the
    /// ID is needed (household creation, member lookup, etc.).
    @Published var userID:               UUID?         = nil
    @Published var isLoading:            Bool          = false
    @Published var errorMessage:         String?       = nil
    @Published var isBiometricEnabled:   Bool          = false
    /// True while the initial Supabase session check is in flight.
    /// RootView shows a splash screen until this is false so the router
    /// never evaluates household/paywall state before auth is known.
    @Published var isCheckingSession:    Bool          = true
    /// Set to true when Supabase fires a .passwordRecovery event (user tapped
    /// the reset-password deep link). RootView presents ResetPasswordView.
    @Published var showResetPassword:    Bool          = false

    // MARK: - Dependencies
    private let auth     = AuthService.shared
    private let storeKit = StoreKitService.shared

    // MARK: - Init
    init() {
        isBiometricEnabled = UserDefaults.standard.bool(forKey: "hemvo_biometricEnabled")
        Task {
            await checkSession()
            isCheckingSession = false
        }
        Task { await observeAuthStateChanges() }
    }

    // Listens for auth events fired after HemvoApp processes a deep-link URL.
    // .passwordRecovery → show ResetPasswordView
    // .signedIn (while logged out) → magic-link email confirmation tapped; log in directly
    private func observeAuthStateChanges() async {
        for await (event, session) in supabase.auth.authStateChanges {
            switch event {
            case .passwordRecovery:
                showResetPassword = true
            case .signedIn where !isLoggedIn:
                isLoggedIn = true
                userID     = session?.user.id
                UserDefaults.standard.removeObject(forKey: "hemvo_lockedOut")
                await loadProfile()
                if profile == nil {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await loadProfile()
                }
                await refreshSubscriptionStatus()
                PushNotificationService.shared.refreshToken()
                if !trialHasStarted && profile?.trialEndDate == nil {
                    await startTrial()
                }
            case .signedOut where isLoggedIn:
                // Fired when the SDK can't refresh the token (e.g. account banned).
                signOut()
            default:
                break
            }
        }
    }

    // MARK: - Convenience: current user ID
    var currentUserID: UUID? {
        get async { await auth.currentUserID() }
    }

    // MARK: - Role helpers

    /// True when the current user owns their household (or has no household yet).
    /// Defaults to true so new users without a household still hit the regular paywall.
    var isOwner: Bool {
        guard let uid = userID?.uuidString,
              let h   = HouseholdService.shared.household else { return true }
        return h.ownerUserID == uid
    }

    // MARK: - Trial helpers
    var trialHasStarted: Bool {
        UserDefaults.standard.object(forKey: "hemvo_trialEndDate") as? Date != nil
    }

    /// Only owners need a personal active subscription or trial.
    /// Members are covered by the owner — their own trial expiry is irrelevant.
    var trialExpired: Bool {
        guard isOwner else { return false }
        guard !isSubscriptionActive else { return false }
        if let end = UserDefaults.standard.object(forKey: "hemvo_trialEndDate") as? Date {
            return end < Date()
        }
        return false
    }

    // MARK: - Session restore on launch
    func checkSession() async {
        // If the user explicitly signed out, respect that — don't auto-restore.
        // Biometric login clears this flag to re-enter without a password.
        guard !UserDefaults.standard.bool(forKey: "hemvo_lockedOut") else { return }
        let active = await auth.restoreSession()
        if active {
            isLoggedIn = true
            userID = await auth.currentUserID()
            await loadProfile()
            if profile == nil {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await loadProfile()
            }
            await refreshSubscriptionStatus()
            PushNotificationService.shared.refreshToken()
        }
    }

    // MARK: - Load profile from Supabase
    func loadProfile() async {
        do {
            let loaded = try await auth.loadProfile()
            if loaded.disabled ?? false {
                signOut()
                errorMessage = "Your account is disabled, contact the Owner."
                return
            }
            profile = loaded
            UserPreferences.shared.seed(from: loaded)
            await HouseholdService.shared.syncWithProfile(loaded)
            // Restore trial end date from Supabase if UserDefaults lost it
            // (e.g. after reinstall or device migration) so the trial guard
            // in login() can see the existing trial and not start a new one.
            if UserDefaults.standard.object(forKey: "hemvo_trialEndDate") as? Date == nil,
               let serverEnd = loaded.trialEndDate {
                UserDefaults.standard.set(serverEnd, forKey: "hemvo_trialEndDate")
            }
        } catch {
            // Not fatal — profile may not exist yet for brand new users
            print("Profile load error: \(error.localizedDescription)")
        }
    }

    // MARK: - Sign Up
    // AuthService sends a confirmation email via Resend after creating the account.
    // The user must tap the link before they can log in.
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
        if raw.contains("rate limit") || raw.contains("too many") || raw.contains("429")
            || raw.contains("over_email_send_rate_limit") || raw.contains("email rate limit") {
            return "Too many sign-up attempts. Please wait a few minutes and try again."
        }
        if raw.contains("error sending") || raw.contains("sending confirmation")
            || raw.contains("email could not") || raw.contains("failed to send") {
            return "We couldn't send a confirmation email right now. Please try again in a moment."
        }
        if raw.contains("already registered") || raw.contains("already been registered")
            || raw.contains("user already exists") || raw.contains("already exists") {
            return "An account with this email already exists. Please sign in instead."
        }
        if raw.contains("invalid email") {
            return "Please enter a valid email address."
        }
        if raw.contains("weak password") || raw.contains("password should be") {
            return "Password must be at least 8 characters with an uppercase letter and a number."
        }
        if raw.contains("user_banned") || raw.contains("banned") || raw.contains("user is banned") {
            return "Your account is disabled. Contact the Owner."
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
            UserDefaults.standard.removeObject(forKey: "hemvo_lockedOut")
            userID = await auth.currentUserID()
            await loadProfile()
            // Retry once — the DB trigger that creates the profiles row
            // runs asynchronously and may not have finished yet.
            if profile == nil {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await loadProfile()
            }
            await refreshSubscriptionStatus()
            PushNotificationService.shared.refreshToken()
            // Start trial only for genuinely new accounts — i.e. no trial in
            // UserDefaults (restored from Supabase above if it existed) AND
            // no trial recorded server-side. This prevents a password change
            // or reinstall from resetting the trial clock.
            if !trialHasStarted && profile?.trialEndDate == nil {
                await startTrial()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await offerBiometricEnrollment()
                }
            }
        } catch {
            errorMessage = friendlyAuthError(error)
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
                errorMessage = friendlyAuthError(error)
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
                errorMessage = friendlyAuthError(error)
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
            UserDefaults.standard.removeObject(forKey: "hemvo_lockedOut")
            userID = await auth.currentUserID()
            await loadProfile()
            await refreshSubscriptionStatus()
            PushNotificationService.shared.refreshToken()
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
                UserDefaults.standard.removeObject(forKey: "hemvo_lockedOut")
                userID = await auth.currentUserID()
                await startTrial()
                await loadProfile()
                PushNotificationService.shared.refreshToken()
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
            let success  = await Self.evaluateBiometric(reason: "Sign in to Hemvo")
            if success {
                // Clear the locked-out flag so the session can be restored
                UserDefaults.standard.removeObject(forKey: "hemvo_lockedOut")
                let restored = await auth.restoreSession()
                if restored {
                    isLoggedIn = true
                    userID = await auth.currentUserID()
                    await loadProfile()
                    await refreshSubscriptionStatus()
                    PushNotificationService.shared.refreshToken()
                } else {
                    // Session truly expired (refresh token invalidated or device restored).
                    // Disable biometrics so the button disappears until next password login.
                    isBiometricEnabled = false
                    UserDefaults.standard.set(false, forKey: "hemvo_biometricEnabled")
                    UserDefaults.standard.set(true, forKey: "hemvo_lockedOut")
                    errorMessage = "Session expired. Please sign in with your password."
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
            reason: "Enable \(biometricLabel) for Hemvo")
        if success {
            isBiometricEnabled = true
            UserDefaults.standard.set(true, forKey: "hemvo_biometricEnabled")
        }
        return success
    }

    func disableBiometrics() {
        isBiometricEnabled = false
        UserDefaults.standard.set(false, forKey: "hemvo_biometricEnabled")
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
            reason: "Enable biometric login for Hemvo")
        if enrolled {
            isBiometricEnabled = true
            UserDefaults.standard.set(true, forKey: "hemvo_biometricEnabled")
        }
    }

    // MARK: - Convenience: current username
    var currentUsername: String? { profile?.username }

    // MARK: - Password change
    func changePassword(currentPassword: String, newPassword: String) async -> Bool {
        do {
            try await auth.changePassword(currentPassword: currentPassword, to: newPassword)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Trial
    private func startTrial() async {
        let end = Calendar.current.date(
            byAdding: .day,
            value: AppConstants.trialDurationDays,
            to: Date()
        ) ?? Date()
        UserDefaults.standard.set(end, forKey: "hemvo_trialEndDate")
        trialDaysRemaining   = AppConstants.trialDurationDays
        isSubscriptionActive = true
        // Persist to Supabase so the trial survives reinstalls and device
        // migrations — loadProfile() restores it to UserDefaults on next login.
        await auth.updateTrialEndDate(end)
    }

    // MARK: - Subscription

    func refreshSubscriptionStatus() async {
        let hasSub = await storeKit.hasActiveSubscription()
        let isActive: Bool
        if hasSub {
            isSubscriptionActive = true
            trialDaysRemaining   = 0
            isActive             = true
        } else if let end = UserDefaults.standard.object(forKey: "hemvo_trialEndDate") as? Date {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
            trialDaysRemaining   = max(days, 0)
            isSubscriptionActive = end > Date()
            isActive             = end > Date()
        } else {
            isSubscriptionActive = false
            trialDaysRemaining   = 0
            isActive             = false
        }

        if isOwner {
            // Push owner's current status to Supabase so members can read it.
            await auth.updateSubscriptionStatus(isActive: isActive)
        } else {
            // Member: check whether the owner is still paying.
            await checkOwnerSubscriptionStatus()
        }
    }

    // MARK: - Grace Period (members only)

    private func checkOwnerSubscriptionStatus() async {
        guard let h = HouseholdService.shared.household, !h.ownerUserID.isEmpty else { return }
        let ownerActive = await auth.fetchOwnerSubscriptionStatus(ownerID: h.ownerUserID)
        if ownerActive {
            clearOwnerGracePeriod()
            ownerSubscriptionLapsed  = false
            gracePeriodDaysRemaining = 0
        } else {
            startOrCheckGracePeriod(householdID: h.id)
        }
    }

    private func startOrCheckGracePeriod(householdID: String) {
        let key = "hemvo_ownerLapsedAt_\(householdID)"
        let lapsedAt: Date
        if let stored = UserDefaults.standard.object(forKey: key) as? Date {
            lapsedAt = stored
        } else {
            lapsedAt = Date()
            UserDefaults.standard.set(lapsedAt, forKey: key)
        }
        let elapsed   = Calendar.current.dateComponents([.day], from: lapsedAt, to: Date()).day ?? 0
        let remaining = max(0, AppConstants.gracePeriodDays - elapsed)
        gracePeriodDaysRemaining = remaining
        ownerSubscriptionLapsed  = remaining == 0
    }

    private func clearOwnerGracePeriod() {
        guard let h = HouseholdService.shared.household else { return }
        UserDefaults.standard.removeObject(forKey: "hemvo_ownerLapsedAt_\(h.id)")
    }

    // MARK: - Sign Out
    func signOut() {
        isLoggedIn               = false
        isSubscriptionActive     = false
        trialDaysRemaining       = 0
        ownerSubscriptionLapsed  = false
        gracePeriodDaysRemaining = 0
        profile                  = nil
        userID                   = nil
        errorMessage             = nil
        // Mark the app as locked rather than fully signing out the Supabase session.
        // This keeps the refresh token in the keychain so biometric login can restore
        // the session without re-entering a password. checkSession() skips auto-login
        // while this flag is set. deleteAccount() still calls auth.signOut() to fully
        // invalidate the server session when the account is permanently removed.
        UserDefaults.standard.set(true, forKey: "hemvo_lockedOut")
    }

    // MARK: - Delete Account
    // Returns nil on success, or an error message string if deletion failed.
    // The caller must NOT clear local state if this returns a non-nil message —
    // the account still exists in Supabase and the user should be told to retry.
    func deleteAccount() async -> String? {
        // 1. Delete from Supabase — removes auth.users + profile + household data
        //    via the `delete_my_account` RPC (SECURITY DEFINER Postgres function).
        //    We must NOT clear local state if this fails, otherwise the email
        //    stays in auth.users but the user thinks the account is gone.
        do {
            try await auth.deleteAccount()
        } catch {
            print("[Auth] deleteAccount RPC error: \(error.localizedDescription)")
            return "Account deletion failed: \(error.localizedDescription). Please try again or contact support."
        }

        // 2. Clear local UserDefaults cache
        let keysToRemove: [String] = [
            "hemvo_trialEndDate", "hemvo_biometricEnabled", "hemvo_lockedOut",
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

        // Clear iCloud KV store preference keys so they don't bleed into a new account
        UserPreferences.shared.clearAll()

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

        // 5. Sign out to invalidate the server session, then wipe the entire
        //    Keychain (including the Supabase session token stored via
        //    KeychainAuthStorage). This ensures no stale credentials remain
        //    that could interfere with a future sign-up for the same email.
        try? await auth.signOut()
        KeychainHelper.shared.deleteAll()

        isLoggedIn               = false
        isSubscriptionActive     = false
        trialDaysRemaining       = 0
        ownerSubscriptionLapsed  = false
        gracePeriodDaysRemaining = 0
        profile                  = nil
        userID                   = nil
        return nil
    }
}
