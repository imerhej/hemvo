
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
//
// KEYCHAIN STORAGE:
// Sensitive flags (biometric, locked-out, trial date, grace period) are stored
// in the Keychain instead of UserDefaults so they survive app reinstalls and
// cannot be read by other apps or inspected on jailbroken devices.

internal import SwiftUI
internal import LocalAuthentication
internal import Foundation
internal import Combine
internal import CoreData
internal import UserNotifications
internal import Supabase
internal import Auth
internal import OSLog

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
    /// True from the moment isLoggedIn becomes true until refreshSubscriptionStatus()
    /// (or startTrial()) completes.  Prevents RootView from evaluating
    /// trialExpired/paywall state before subscription status is loaded.
    @Published var isResolvingAccess:    Bool          = false
    /// Set to true when Supabase fires a .passwordRecovery event (user tapped
    /// the reset-password deep link). RootView presents ResetPasswordView.
    @Published var showResetPassword:    Bool          = false

    // MARK: - Dependencies
    private let auth     = AuthService.shared
    private let storeKit = StoreKitService.shared

    // MARK: - Keychain Keys (sensitive data — never UserDefaults)
    private enum KC {
        static let biometricEnabled = "hemvo_biometricEnabled"
        static let lockedOut        = "hemvo_lockedOut"
        static let trialEndDate     = "hemvo_trialEndDate"
        static let notBefore        = "hemvo_notBefore"
        static func gracePeriod(householdID: String) -> String {
            "hemvo_ownerLapsedAt_\(householdID)"
        }
    }

    // MARK: - Keychain helpers

    private static func kcBool(_ key: String) -> Bool {
        KeychainHelper.shared.loadString(key: key, iCloudSync: false) == "1"
    }
    private static func setKCBool(_ key: String, _ value: Bool) {
        KeychainHelper.shared.saveString(value ? "1" : "0", key: key, iCloudSync: false)
    }
    private static func deleteKCBool(_ key: String) {
        KeychainHelper.shared.delete(key: key, iCloudSync: false)
    }

    private static func kcDate(_ key: String, iCloudSync: Bool = false) -> Date? {
        KeychainHelper.shared.load(Date.self, key: key, iCloudSync: iCloudSync)
    }
    private static func setKCDate(_ key: String, _ date: Date, iCloudSync: Bool = false) {
        KeychainHelper.shared.save(date, key: key, iCloudSync: iCloudSync)
    }
    private static func deleteKCDate(_ key: String, iCloudSync: Bool = false) {
        KeychainHelper.shared.delete(key: key, iCloudSync: iCloudSync)
    }

    /// Returns the later of the device clock and the highest timestamp this
    /// device has ever observed, persisting the result. Trial expiry is
    /// compared against this instead of raw `Date()` so winding the system
    /// clock backward can't un-expire a trial once real elapsed time has
    /// already carried the anchor past `trialEndDate`.
    private static func advancingNotBeforeAnchor() -> Date {
        let now    = Date()
        let stored = kcDate(KC.notBefore)
        let anchor = max(now, stored ?? .distantPast)
        if stored == nil || anchor > stored! {
            setKCDate(KC.notBefore, anchor)
        }
        return anchor
    }

    // MARK: - One-time migration: UserDefaults → Keychain
    // Runs once on first launch after upgrade. Values are moved then removed
    // from UserDefaults so they are no longer readable unencrypted.
    private func migrateSensitiveDefaultsToKeychain() {
        let ud = UserDefaults.standard

        if !KeychainHelper.shared.exists(key: KC.biometricEnabled, iCloudSync: false) {
            let val = ud.bool(forKey: KC.biometricEnabled)
            Self.setKCBool(KC.biometricEnabled, val)
            ud.removeObject(forKey: KC.biometricEnabled)
        } else {
            ud.removeObject(forKey: KC.biometricEnabled)
        }

        if !KeychainHelper.shared.exists(key: KC.lockedOut, iCloudSync: false) {
            if ud.bool(forKey: KC.lockedOut) {
                Self.setKCBool(KC.lockedOut, true)
            }
            ud.removeObject(forKey: KC.lockedOut)
        } else {
            ud.removeObject(forKey: KC.lockedOut)
        }

        if !KeychainHelper.shared.exists(key: KC.trialEndDate, iCloudSync: true) {
            if let date = ud.object(forKey: KC.trialEndDate) as? Date {
                Self.setKCDate(KC.trialEndDate, date, iCloudSync: true)
            }
            ud.removeObject(forKey: KC.trialEndDate)
        } else {
            ud.removeObject(forKey: KC.trialEndDate)
        }
    }

    // MARK: - Init
    init() {
        migrateSensitiveDefaultsToKeychain()
        isBiometricEnabled = Self.kcBool(KC.biometricEnabled)
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
                isLoggedIn        = true
                isResolvingAccess = true
                userID     = session?.user.id
                Self.deleteKCBool(KC.lockedOut)
                await loadProfile()
                if profile == nil {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await loadProfile()
                }
                await refreshSubscriptionStatus()
                isResolvingAccess = false
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
    /// Returns false when not logged in so no subscription UI flashes during sign-out.
    var isOwner: Bool {
        guard isLoggedIn else { return false }
        guard let uid = userID?.uuidString,
              let h   = HouseholdService.shared.household else { return true }
        return h.ownerUserID == uid
    }

    // MARK: - Trial helpers
    var trialHasStarted: Bool {
        Self.kcDate(KC.trialEndDate, iCloudSync: true) != nil
    }

    /// Only owners need a personal active subscription or trial.
    /// Members are covered by the owner — their own trial expiry is irrelevant.
    var trialExpired: Bool {
        guard isLoggedIn else { return false }
        guard isOwner else { return false }
        guard !isSubscriptionActive else { return false }
        if let end = Self.kcDate(KC.trialEndDate, iCloudSync: true) {
            return end < Self.advancingNotBeforeAnchor()
        }
        return false
    }

    // MARK: - Session restore on launch
    func checkSession() async {
        // If the user explicitly signed out, respect that — don't auto-restore.
        // Biometric login clears this flag to re-enter without a password.
        guard !Self.kcBool(KC.lockedOut) else { return }
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
            // Reconcile the local trial-end cache to the server's value.
            // trial_end_date is guarded server-side (settable at most once,
            // never regressed), so it's always safe — and necessary — to
            // overwrite the local copy rather than only filling in a nil.
            // Otherwise a stale Keychain value left over from a previous
            // account on this device (e.g. after account deletion) could
            // silently apply to a newly created account.
            if let serverEnd = loaded.trialEndDate {
                Self.setKCDate(KC.trialEndDate, serverEnd, iCloudSync: true)
            }
        } catch {
            // Not fatal — profile may not exist yet for brand new users
            Logger.auth.error("Profile load error: \(error.localizedDescription)")
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
        // Edge Functions return {"error": "..."} with non-2xx codes, but
        // FunctionsError.httpError's localizedDescription is only
        // "Edge Function returned a non-2xx status code: N" — the real message
        // is in the response body, so decode it before keyword matching.
        let message = Self.edgeFunctionMessage(from: error) ?? error.localizedDescription
        let raw = message.lowercased()
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
        return message
    }

    private static func edgeFunctionMessage(from error: Error) -> String? {
        guard case let FunctionsError.httpError(_, data) = error else { return nil }
        struct Body: Decodable { let error: String?; let message: String? }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
        return body.error ?? body.message
    }

    // MARK: - Login
    func login(emailOrUsername: String, password: String) async {
        isLoading    = true
        errorMessage = nil
        do {
            try await auth.login(emailOrUsername: emailOrUsername, password: password)
            isLoggedIn        = true
            isResolvingAccess = true
            Self.deleteKCBool(KC.lockedOut)
            userID = await auth.currentUserID()
            await loadProfile()
            // Retry once — the DB trigger that creates the profiles row
            // runs asynchronously and may not have finished yet.
            if profile == nil {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await loadProfile()
            }
            await refreshSubscriptionStatus()
            isResolvingAccess = false
            PushNotificationService.shared.refreshToken()
            // Start trial only for genuinely new accounts — i.e. no trial in
            // Keychain (restored from Supabase above if it existed) AND
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
                Self.deleteKCBool(KC.lockedOut)
                let restored = await auth.restoreSession()
                if restored {
                    isLoggedIn        = true
                    isResolvingAccess = true
                    userID = await auth.currentUserID()
                    await loadProfile()
                    await refreshSubscriptionStatus()
                    isResolvingAccess = false
                    PushNotificationService.shared.refreshToken()
                } else {
                    // Session truly expired (refresh token invalidated or device restored).
                    // Disable biometrics so the button disappears until next password login.
                    isBiometricEnabled = false
                    Self.setKCBool(KC.biometricEnabled, false)
                    Self.setKCBool(KC.lockedOut, true)
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
            Self.setKCBool(KC.biometricEnabled, true)
        }
        return success
    }

    func disableBiometrics() {
        isBiometricEnabled = false
        Self.setKCBool(KC.biometricEnabled, false)
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
            Self.setKCBool(KC.biometricEnabled, true)
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
        Self.setKCDate(KC.trialEndDate, end, iCloudSync: true)
        trialDaysRemaining   = AppConstants.trialDurationDays
        isSubscriptionActive = true
        // Persist to Supabase so the trial survives full device wipes where
        // iCloud Keychain is unavailable — loadProfile() restores it on next login.
        await auth.updateTrialEndDate(end)
    }

    // MARK: - Subscription

    func refreshSubscriptionStatus() async {
        let hasSub = await storeKit.hasActiveSubscription()
        let isTrialActive: Bool
        if hasSub {
            isSubscriptionActive = true
            trialDaysRemaining   = 0
            isTrialActive        = false
        } else if let end = Self.kcDate(KC.trialEndDate, iCloudSync: true) {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
            trialDaysRemaining   = max(days, 0)
            isSubscriptionActive = end > Date()
            isTrialActive        = end > Date()
        } else {
            isSubscriptionActive = false
            trialDaysRemaining   = 0
            isTrialActive        = false
        }

        if isOwner {
            // Push owner's current status to Supabase so members can read it.
            // A real subscription is confirmed with Apple before it can flip the
            // column to `active`; trial activation is bounded by the server's own
            // trial_end_date. Neither path lets the client set `active` for free.
            switch SubscriptionDecision.ownerServerSync(
                hasSub: hasSub,
                transactionID: storeKit.currentTransactionID,
                isTrialActive: isTrialActive
            ) {
            case .verifyTransaction(let transactionID):
                switch SubscriptionDecision.followUp(for: await auth.verifySubscription(transactionID: transactionID)) {
                case .confirmed:
                    if profile?.subscriptionLapsedAt != nil {
                        await loadProfile()
                    }
                case .downgrade:
                    await auth.expireSubscriptionStatus()
                    await loadProfile()
                case .leaveUnchanged:
                    break
                }
            case .leaveUnchanged:
                break
            case .activateTrial:
                await auth.activateTrialSubscription()
            case .expire:
                await auth.expireSubscriptionStatus()
                await loadProfile()
            }
        } else {
            // Member: check whether the owner is still paying.
            await checkOwnerSubscriptionStatus()
        }
    }

    // MARK: - Grace Period (members only)

    private func checkOwnerSubscriptionStatus() async {
        guard let h = HouseholdService.shared.household, !h.ownerUserID.isEmpty else { return }
        let state = await auth.fetchOwnerSubscriptionState(ownerID: h.ownerUserID)
        if state.isActive {
            // Clean up the legacy per-device Keychain grace clock.
            Self.deleteKCDate(KC.gracePeriod(householdID: h.id))
            ownerSubscriptionLapsed  = false
            gracePeriodDaysRemaining = 0
        } else {
            // The countdown derives from the server-stamped lapse moment, so
            // every member device shows the same number of days. nil only
            // happens transiently (status flipped before the migration ran);
            // treat it as "just lapsed" — the server value takes over on the
            // next refresh.
            let remaining = Self.graceDaysRemaining(since: state.lapsedAt ?? Date())
            gracePeriodDaysRemaining = remaining
            ownerSubscriptionLapsed  = remaining == 0
        }
    }

    /// Whole 24-hour periods, deliberately timezone-independent so all member
    /// devices compute the identical days-left from the shared server timestamp.
    static func graceDaysRemaining(since lapsedAt: Date) -> Int {
        let elapsedDays = Int(Date().timeIntervalSince(lapsedAt) / 86_400)
        return max(0, AppConstants.gracePeriodDays - elapsedDays)
    }

    /// Owner-side view of the same countdown: days their household members
    /// keep access after the owner's own subscription lapsed. 0 when N/A.
    var memberGraceDaysRemaining: Int {
        guard let lapsedAt = profile?.subscriptionLapsedAt else { return 0 }
        return Self.graceDaysRemaining(since: lapsedAt)
    }

    // MARK: - Sign Out
    func signOut() {
        isLoggedIn               = false
        isResolvingAccess        = false
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
        Self.setKCBool(KC.lockedOut, true)
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
            Logger.auth.error("deleteAccount RPC error: \(error.localizedDescription)")
            return "Account deletion failed: \(error.localizedDescription). Please try again or contact support."
        }

        // 2. Clear local UserDefaults cache (non-sensitive data only)
        let keysToRemove: [String] = [
            "hemvo_meals", "hemvo_expenses", "hemvo_events", "hemvo_tasks",
            "hemvo_members", "hemvo_maintenanceItems", "hemvo_maintenanceHistory",
            "hemvo_paymentCards", "hemvo_avatarColor",
            "notif_bills", "notif_meals", "notif_schedule", "notif_maintenance",
            "hemvo_groceryItems", "hemvo_shoppingLists", "hemvo_budget",
            "hemvo_seasonalCompleted", "hemvo_seasonalItemsV3",
            "hemvo_household_v2", "hemvo_householdInvites_v2",
        ]
        let ud = UserDefaults.standard
        keysToRemove.forEach { ud.removeObject(forKey: $0) }
        // APNs token is now in Keychain; clear it so the next login re-registers the device.
        KeychainHelper.shared.delete(key: "hemvo_apns_token", iCloudSync: false)

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
        //    KeychainAuthStorage, plus all sensitive flags migrated above).
        //    This ensures no stale credentials remain.
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

// MARK: - Subscription reconciliation decisions
//
// Pure decision logic factored out of the @MainActor AuthViewModel so it carries
// no actor isolation and can be unit-tested directly, without StoreKit, the
// network, or the Keychain. `refreshSubscriptionStatus()` executes the side
// effects these functions choose.
//
// `nonisolated` (the project defaults every type to MainActor isolation): keeps
// these pure and their synthesized Equatable conformances usable from any
// context — including Swift Testing's nonisolated comparison closures.
nonisolated enum SubscriptionDecision {

    /// How an owner's device should reconcile the server `subscription_status`
    /// column after checking its local StoreKit entitlement.
    nonisolated enum OwnerServerSync: Equatable {
        /// Live entitlement + a real transaction id → confirm it with Apple.
        case verifyTransaction(UInt64)
        /// Live entitlement but no transaction id (simulator dev bypass, which
        /// returns hasSub == true without loading entitlements). Leave the row
        /// alone rather than expiring it, which would start members' grace clock
        /// from a state that doesn't reflect a real device.
        case leaveUnchanged
        /// No entitlement but the trial window is still open.
        case activateTrial
        /// No entitlement and no trial → downgrade.
        case expire
    }

    static func ownerServerSync(
        hasSub: Bool, transactionID: UInt64?, isTrialActive: Bool
    ) -> OwnerServerSync {
        guard hasSub else { return isTrialActive ? .activateTrial : .expire }
        if let transactionID { return .verifyTransaction(transactionID) }
        return .leaveUnchanged
    }

    /// What to do with the server row + local profile after Apple verification.
    nonisolated enum VerificationFollowUp: Equatable {
        /// `.active` — verify-subscription already set the row `active` and the
        /// guard trigger cleared subscription_lapsed_at; only a local reload is
        /// ever needed (to clear the owner's own paywall grace copy after a lapse).
        case confirmed
        /// `.invalid` — Apple says the transaction is genuinely not valid; expire.
        case downgrade
        /// `.unverifiable` — couldn't reach Apple/the edge function. Keep the row
        /// unchanged and retry next foreground; a transient blip must never expire
        /// a paying owner and strand household members on the grace popup.
        case leaveUnchanged
    }

    static func followUp(
        for verification: AuthService.SubscriptionVerification
    ) -> VerificationFollowUp {
        switch verification {
        case .active:       return .confirmed
        case .invalid:      return .downgrade
        case .unverifiable: return .leaveUnchanged
        }
    }
}
