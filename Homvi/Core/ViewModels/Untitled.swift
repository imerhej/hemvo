////
////  Untitled.swift
////  Homvi
////
////  Created by Issam Merhej on 4/19/26.
////
//
////  AuthViewModel.swift
////  Homvi
////  Manages authentication state, 7-day trial timer, and subscription status.
//
//internal import SwiftUI
//internal import LocalAuthentication
//internal import StoreKit
//internal import Foundation
//internal import Combine
//internal import CoreData
//internal import UserNotifications
//
//@MainActor
//final class AuthViewModel: ObservableObject {
//
//    // MARK: - Published
//    @Published var isLoggedIn:           Bool   = false
//    @Published var isSubscriptionActive: Bool   = false
//    @Published var trialDaysRemaining:   Int    = 0
//    @Published var currentUser:          User?
//    @Published var isLoading:            Bool   = false
//    @Published var errorMessage:         String?
//
//    // Biometric enabled flag — persisted in UserDefaults
//    @Published var isBiometricEnabled: Bool = UserDefaults.standard.bool(forKey: "hb_biometricEnabled") {
//        didSet { UserDefaults.standard.set(isBiometricEnabled, forKey: "hb_biometricEnabled") }
//    }
//
//    // MARK: - Dependencies
//    let authService = AuthService()
//    private let storeKit = StoreKitService.shared
//
//    // MARK: - Trial state helpers
//
//    /// True when the user has ever started a trial (end date key exists).
//    var trialHasStarted: Bool {
//        UserDefaults.standard.object(forKey: "hb_trialEndDate") as? Date != nil
//    }
//
//    /// True only when the trial was started AND has expired AND there is no
//    /// active paid subscription. Brand-new users (no trial key) return false.
//    var trialExpired: Bool {
//        guard !isSubscriptionActive else { return false }
//        if let end = UserDefaults.standard.object(forKey: "hb_trialEndDate") as? Date {
//            return end < Date()
//        }
//        return false   // trial never started → not expired
//    }
//
//    // MARK: - Init
//    init() { checkSession() }
//
//    // MARK: - Session
//    func checkSession() {
//        if let user = authService.loadStoredUser() {
//            currentUser = user
//            isLoggedIn  = true
//        }
//    }
//
//    // MARK: - Sign Up
//    func signUp(name: String, username: String, email: String, password: String) async {
//        isLoading    = true
//        errorMessage = nil
//        do {
//            let user = try await authService.createAccount(
//                name: name, username: username, email: email, password: password)
//            currentUser = user
//            isLoggedIn  = true
//            startTrial()
//            await offerBiometricEnrollment()
//        } catch {
//            errorMessage = error.localizedDescription
//        }
//        isLoading = false
//    }
//
//    // MARK: - Login
//    func login(username: String, password: String) async {
//        isLoading    = true
//        errorMessage = nil
//        do {
//            let user = try await authService.login(username: username, password: password)
//            currentUser = user
//            isLoggedIn  = true
//            await refreshSubscriptionStatus()
//        } catch {
//            errorMessage = error.localizedDescription
//        }
//        isLoading = false
//    }
//
//    // MARK: - Sign in with Apple
//    func loginWithApple() {
//        Task {
//            isLoading    = true
//            errorMessage = nil
//            do {
//                let result = try await SocialAuthService.shared.signInWithApple()
//                await completeSocialLogin(result)
//            } catch let err as SocialAuthError where err == .cancelled {
//                // silent — user dismissed
//            } catch {
//                errorMessage = error.localizedDescription
//            }
//            isLoading = false
//        }
//    }
//
//    // MARK: - Sign in with Google
//    func loginWithGoogle() {
//        let vc = UIApplication.shared.connectedScenes
//            .compactMap { $0 as? UIWindowScene }
//            .flatMap { $0.windows }
//            .first(where: { $0.isKeyWindow })?.rootViewController
//        guard let vc else { return }
//
//        Task {
//            isLoading    = true
//            errorMessage = nil
//            do {
//                let result = try await SocialAuthService.shared.signInWithGoogle(
//                    presentingViewController: vc)
//                await completeSocialLogin(result)
//            } catch let err as SocialAuthError where err == .cancelled {
//                // silent
//            } catch {
//                errorMessage = error.localizedDescription
//            }
//            isLoading = false
//        }
//    }
//
//    // MARK: - Shared social login completion
//    private func completeSocialLogin(_ result: SocialAuthResult) async {
//        let users = authService.loadAllUsers()
//        if let existing = users.first(where: {
//            $0.email.lowercased() == result.email.lowercased()
//        }) {
//            authService.saveCurrentUserPublic(existing)
//            currentUser = existing
//            isLoggedIn  = true
//            await refreshSubscriptionStatus()
//        } else {
//            let tempPassword = UUID().uuidString
//            let derivedUsername = result.email.components(separatedBy: "@").first ?? result.email
//            do {
//                let user = try await authService.createAccount(
//                    name: result.name, username: derivedUsername, email: result.email, password: tempPassword)
//                currentUser = user
//                isLoggedIn  = true
//                startTrial()
//                await offerBiometricEnrollment()
//            } catch {
//                errorMessage = error.localizedDescription
//            }
//        }
//    }
//
//    // MARK: - Biometric login
//    func loginWithBiometrics() {
//        let context = LAContext()
//        var error: NSError?
//        guard context.canEvaluatePolicy(
//            .deviceOwnerAuthenticationWithBiometrics, error: &error) else {
//            errorMessage = "Biometric authentication is not available on this device."
//            return
//        }
//
//        Task.detached(priority: .userInitiated) { [weak self] in
//            guard let self else { return }
//            let success = await AuthViewModel.performBiometricEvaluation(
//                context: context, reason: "Sign in to Homvi")
//            await MainActor.run {
//                if success {
//                    if let user = self.authService.loadStoredUser() {
//                        self.currentUser = user
//                        self.isLoggedIn  = true
//                    } else {
//                        self.errorMessage = "No saved session. Please sign in with your password."
//                    }
//                }
//            }
//            if success { await self.refreshSubscriptionStatus() }
//        }
//    }
//
//    // MARK: - Enable / Disable Biometrics
//    func enableBiometrics() async -> Bool {
//        let context = LAContext()
//        var nsError: NSError?
//        guard context.canEvaluatePolicy(
//            .deviceOwnerAuthenticationWithBiometrics, error: &nsError) else {
//            errorMessage = "Face ID / Touch ID is not available on this device."
//            return false
//        }
//
//        let success = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
//            Task.detached(priority: .userInitiated) {
//                let result = await AuthViewModel.performBiometricEvaluation(
//                    context: context,
//                    reason: "Enable biometric login for Homvi")
//                cont.resume(returning: result)
//            }
//        }
//
//        if success { isBiometricEnabled = true }
//        return success
//    }
//
//    func disableBiometrics() {
//        isBiometricEnabled = false
//    }
//
//    // Core biometric evaluation — fully nonisolated so LAContext callback is safe
//    private nonisolated static func performBiometricEvaluation(
//        context: LAContext, reason: String) async -> Bool {
//        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
//            context.evaluatePolicy(
//                .deviceOwnerAuthenticationWithBiometrics,
//                localizedReason: reason
//            ) { success, _ in
//                cont.resume(returning: success)
//            }
//        }
//    }
//
//    // MARK: - Biometric availability
//    var biometricType: LABiometryType {
//        let ctx = LAContext()
//        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
//        return ctx.biometryType
//    }
//    var biometricLabel: String {
//        switch biometricType {
//        case .faceID:  return "Face ID"
//        case .touchID: return "Touch ID"
//        default:       return "Biometrics"
//        }
//    }
//    var biometricIcon: String {
//        switch biometricType {
//        case .faceID:  return "faceid"
//        case .touchID: return "touchid"
//        default:       return "lock.shield.fill"
//        }
//    }
//
//    // MARK: - Password change
//    func changePassword(currentPassword: String, newPassword: String) async -> Bool {
//        guard let user = currentUser else { return false }
//        do {
//            try authService.changePassword(
//                for: user.id, current: currentPassword, new: newPassword)
//            return true
//        } catch {
//            errorMessage = error.localizedDescription
//            return false
//        }
//    }
//
//    // MARK: - Trial
//    private func startTrial() {
//        let end = Calendar.current.date(
//            byAdding: .day, value: AppConstants.trialDurationDays, to: Date()) ?? Date()
//        UserDefaults.standard.set(end, forKey: "hb_trialEndDate")
//        trialDaysRemaining   = AppConstants.trialDurationDays
//        isSubscriptionActive = true
//    }
//
//    private func offerBiometricEnrollment() async {
//        let context = LAContext()
//        var error: NSError?
//        guard context.canEvaluatePolicy(
//            .deviceOwnerAuthenticationWithBiometrics, error: &error) else { return }
//        isBiometricEnabled = true
//    }
//
//    // MARK: - Subscription refresh
//    func refreshSubscriptionStatus() async {
//        let hasSub = await storeKit.hasActiveSubscription()
//        if hasSub {
//            isSubscriptionActive = true
//            trialDaysRemaining   = 0
//            return
//        }
//        if let end = UserDefaults.standard.object(forKey: "hb_trialEndDate") as? Date {
//            let days = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
//            trialDaysRemaining   = max(days, 0)
//            isSubscriptionActive = days > 0
//        } else {
//            isSubscriptionActive = false
//            trialDaysRemaining   = 0
//        }
//    }
//
//    // MARK: - Sign Out
//    func signOut() {
//        authService.clearSession()
//        isLoggedIn           = false
//        isSubscriptionActive = false
//        trialDaysRemaining   = 0
//        currentUser          = nil
//    }
//
//    // MARK: - Delete Account
//    /// Wipes all user data from the Keychain, UserDefaults, CoreData, and
//    /// local notifications, then signs the user out.
//    func deleteAccount() {
//        guard let user = currentUser else { return }
//
//        // 1. Keychain — credentials and user records
//        authService.deleteAccount(userID: user.id)
//
//        // 2. UserDefaults — all Homvi keys
//        let keysToRemove: [String] = [
//            "hb_trialEndDate",
//            "hb_biometricEnabled",
//            "hb_meals",
//            "hb_expenses",
//            "hb_calendarEvents",
//            "hb_maintenanceItems",
//            "hb_paymentCards",
//            "hb_avatarColor",
//            "notif_bills",
//            "notif_meals",
//            "notif_schedule",
//            "notif_maintenance",
//            "hb_keychain_migration_v1",
//            "hb_groceryItems",
//            "hb_budgetLimit",
//            "hb_seasonalChecklist",
//        ]
//        let ud = UserDefaults.standard
//        keysToRemove.forEach { ud.removeObject(forKey: $0) }
//
//        // 3. CoreData — wipe every entity in the persistent store
//        let context = PersistenceService.shared.container.viewContext
//        let entityNames = PersistenceService.shared.container
//            .managedObjectModel.entities.compactMap { $0.name }
//        for name in entityNames {
//            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: name)
//            let delete = NSBatchDeleteRequest(fetchRequest: fetch)
//            _ = try? context.execute(delete)
//        }
//        try? context.save()
//
//        // 4. Pending local notifications
//        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
//        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
//
//        // 5. Reset VM state
//        isLoggedIn           = false
//        isSubscriptionActive = false
//        trialDaysRemaining   = 0
//        currentUser          = nil
//    }
//}
