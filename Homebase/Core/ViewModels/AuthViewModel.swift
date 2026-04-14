//  AuthViewModel.swift
//  HomeBase
//  Manages authentication state, trial timer, subscription, and biometric login.

internal import SwiftUI
internal import StoreKit
internal import Combine
internal import LocalAuthentication

@MainActor
final class AuthViewModel: ObservableObject {

    // MARK: - Published
    @Published var isLoggedIn: Bool           = false
    @Published var isSubscriptionActive: Bool = false
    @Published var trialDaysRemaining: Int    = 0
    @Published var currentUser: User?
    @Published var isLoading: Bool            = false
    @Published var errorMessage: String?

    // Biometric — stored in UserDefaults, surfaced as @Published so views update
    @Published var isBiometricEnabled: Bool = UserDefaults.standard.bool(forKey: "hb_biometricEnabled") {
        didSet { UserDefaults.standard.set(isBiometricEnabled, forKey: "hb_biometricEnabled") }
    }

    // MARK: - Dependencies
    private let authService = AuthService()
    private let storeKit    = StoreKitService.shared

    // MARK: - Init
    init() { checkSession() }

    // MARK: - Session Check
    func checkSession() {
        if let user = authService.loadStoredUser() {
            currentUser = user
            isLoggedIn  = true
        }
    }

    // MARK: - Sign Up
    func signUp(name: String, email: String, password: String) async {
        isLoading    = true
        errorMessage = nil
        do {
            let user = try await authService.createAccount(name: name, email: email, password: password)
            currentUser = user
            isLoggedIn  = true
            startTrial()
            // Offer to enable biometrics after successful registration
            await offerBiometricEnrollment()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Login
    func login(email: String, password: String) async {
        isLoading    = true
        errorMessage = nil
        do {
            let user = try await authService.login(email: email, password: password)
            currentUser = user
            isLoggedIn  = true
            await refreshSubscriptionStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Change Password
    func changePassword(current: String, new: String) async -> Bool {
        guard let userID = currentUser?.id else { return false }
        do {
            try authService.changePassword(for: userID, current: current, new: new)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Sign in with Apple
    func loginWithApple() {
        Task {
            isLoading    = true
            errorMessage = nil
            do {
                let result = try await SocialAuthService.shared.signInWithApple()
                await completeSocialLogin(result)
            } catch {
                // ASAuthorizationError.canceled == user dismissed — stay silent
                let nsErr = error as NSError
                if nsErr.domain == "com.apple.AuthenticationServices.AuthorizationError",
                   nsErr.code == 1001 {
                    // user cancelled — no error shown
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }

    // MARK: - Sign in with Google
    func loginWithGoogle() {
        // VC lookup is safe here — AuthViewModel is @MainActor
        let vc = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController

        guard let vc else { return }

        Task {
            isLoading    = true
            errorMessage = nil
            do {
                let result = try await SocialAuthService.shared.signInWithGoogle(
                    presentingViewController: vc
                )
                await completeSocialLogin(result)
            } catch let err as SocialAuthError where err == .cancelled {
                // silent
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Shared social completion
    /// Creates or finds an existing account for the social user and logs them in.
    private func completeSocialLogin(_ result: SocialAuthResult) async {
        let authService = AuthService()
        let users       = authService.loadAllUsers()

        if let existing = users.first(where: {
            $0.email.lowercased() == result.email.lowercased()
        }) {
            // Returning user — restore session
            authService.saveCurrentUserPublic(existing)
            currentUser = existing
            isLoggedIn  = true
            await refreshSubscriptionStatus()
        } else {
            // New social user — create account with random password
            let tempPassword = UUID().uuidString
            do {
                let user = try await authService.createAccount(
                    name:     result.name,
                    email:    result.email,
                    password: tempPassword
                )
                currentUser = user
                isLoggedIn  = true
                startTrial()
                await offerBiometricEnrollment()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    func loginWithBiometrics() {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &error
        ) else {
            errorMessage = "Biometric authentication is not available on this device."
            return
        }

        Task {
            let success = await Self.evaluateBiometricPolicy(context: context)
            if success {
                if let user = authService.loadStoredUser() {
                    currentUser = user
                    isLoggedIn  = true
                    await refreshSubscriptionStatus()
                } else {
                    errorMessage = "No saved session found. Please sign in with your password first."
                }
            } else {
                // User cancelled or failed — stay silent unless there's a real error
            }
        }
    }

    // MARK: - Offer Biometric Enrollment (after sign-up)
    private func offerBiometricEnrollment() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return }
        // Auto-enable after first registration — user can turn off in Profile > Security
        isBiometricEnabled = true
    }

    // MARK: - Enable / Disable Biometrics (called from ProfileView)
    func enableBiometrics() async -> Bool {
        let context = LAContext()
        var nsError: NSError?

        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &nsError
        ) else {
            errorMessage = "Face ID / Touch ID is not available on this device."
            return false
        }

        // evaluatePolicy must NOT be called while holding the MainActor lock.
        // We hop off MainActor first, await the result, then hop back.
        let success = await Self.evaluateBiometricPolicy(context: context)

        if success { isBiometricEnabled = true }
        return success
    }

    /// Runs completely outside the MainActor so LAContext can call its
    /// completion handler freely without deadlocking.
    private static func evaluateBiometricPolicy(context: LAContext) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Enable biometric login for HomeBase"
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    func disableBiometrics() {
        isBiometricEnabled = false
    }

    // MARK: - Biometric availability
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

    // MARK: - Trial
    private func startTrial() {
        let end = Calendar.current.date(
            byAdding: .day, value: AppConstants.trialDurationDays, to: Date()
        ) ?? Date()
        UserDefaults.standard.set(end, forKey: UserDefaultsKeys.trialEndDate)
        trialDaysRemaining   = AppConstants.trialDurationDays
        isSubscriptionActive = true
    }

    // MARK: - Subscription Refresh
    func refreshSubscriptionStatus() async {
        let hasSub = await storeKit.hasActiveSubscription()
        if hasSub {
            isSubscriptionActive = true
            trialDaysRemaining   = 0
            return
        }
        if let end = UserDefaults.standard.object(forKey: UserDefaultsKeys.trialEndDate) as? Date {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
            trialDaysRemaining   = max(days, 0)
            isSubscriptionActive = days > 0
        } else {
            isSubscriptionActive = false
            trialDaysRemaining   = 0
        }
    }

    // MARK: - Sign Out
    func signOut() {
        authService.clearSession()
        isLoggedIn           = false
        isSubscriptionActive = false
        trialDaysRemaining   = 0
        currentUser          = nil
    }
}

// MARK: - UserDefaults Keys
private enum UserDefaultsKeys {
    static let trialEndDate = "hb_trialEndDate"
}
