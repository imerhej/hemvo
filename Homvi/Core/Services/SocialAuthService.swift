//  SocialAuthService.swift
//  Homvi
//  Handles Sign in with Apple (native) and Google Sign-In (GoogleSignIn SDK).
//
//  SETUP REQUIRED:
//  ─────────────────────────────────────────────────────────────────────────────
//  Sign in with Apple:
//    1. Xcode → Target → Signing & Capabilities → + Capability → Sign in with Apple
//
//  Sign in with Google:
//    1. File → Add Package → https://github.com/google/GoogleSignIn-iOS
//    2. Add GoogleSignIn and GoogleSignInSwift targets to your app
//    3. In Info.plist add your reversed client ID as a URL scheme:
//       URL types → Item 0 → URL Schemes → com.googleusercontent.apps.YOUR_CLIENT_ID
//    4. Replace "YOUR_GOOGLE_CLIENT_ID" below with your actual client ID from
//       Google Cloud Console → APIs & Services → Credentials
//  ─────────────────────────────────────────────────────────────────────────────

internal import Foundation
internal import AuthenticationServices
internal import CryptoKit

// MARK: - SocialAuthResult
struct SocialAuthResult {
    let name:     String
    let email:    String
    let provider: String     // "apple" | "google"
}

// MARK: - SocialAuthService
@MainActor
final class SocialAuthService: NSObject {

    static let shared = SocialAuthService()

    // Continuation held while waiting for ASAuthorizationController callback
    private var appleSignInContinuation: CheckedContinuation<SocialAuthResult, Error>?
    private var currentNonce: String = ""

    // MARK: - Sign in with Apple
    func signInWithApple() async throws -> SocialAuthResult {
        currentNonce = randomNonce()
        let hashedNonce = sha256(currentNonce)

        let provider = ASAuthorizationAppleIDProvider()
        let request  = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        return try await withCheckedThrowingContinuation { continuation in
            self.appleSignInContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate              = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - Sign in with Google
    // Requires the GoogleSignIn SDK package. If you haven't added it yet,
    // this method returns a clear error rather than crashing.
    func signInWithGoogle(presentingViewController: UIViewController) async throws -> SocialAuthResult {
        // Dynamic lookup so the project compiles even without the Google SDK added yet.
        // Once you add the package, this will resolve at runtime automatically.
        guard
            let gidClass      = NSClassFromString("GIDSignIn") as? NSObject.Type,
            let sharedInstance = gidClass.value(forKey: "sharedInstance") as? NSObject
        else {
            throw SocialAuthError.googleSDKNotInstalled
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Call GIDSignIn.sharedInstance.signIn(withPresenting:completion:)
            let selector = NSSelectorFromString("signInWithPresentingViewController:completion:")
            guard sharedInstance.responds(to: selector) else {
                continuation.resume(throwing: SocialAuthError.googleSDKNotInstalled)
                return
            }

            // Use ObjC-bridging to call the method
            typealias SignInBlock = @convention(block) (AnyObject?, Error?) -> Void
            let block: SignInBlock = { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard
                    let result,
                    let user       = result.value(forKey: "user") as? NSObject,
                    let profile    = user.value(forKey: "profile") as? NSObject,
                    let email      = profile.value(forKey: "email") as? String
                else {
                    continuation.resume(throwing: SocialAuthError.missingProfile)
                    return
                }
                let name = (profile.value(forKey: "name") as? String) ?? email
                continuation.resume(returning: SocialAuthResult(name: name, email: email, provider: "google"))
            }
            let blockObj = block as AnyObject
            sharedInstance.perform(selector, with: presentingViewController, with: blockObj)
        }
    }

    // MARK: - Nonce helpers (Apple requirement)
    private func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256(_ input: String) -> String {
        let data   = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension SocialAuthService: ASAuthorizationControllerDelegate {

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential else {
            Task { @MainActor in
                self.appleSignInContinuation?.resume(throwing: SocialAuthError.missingProfile)
                self.appleSignInContinuation = nil
            }
            return
        }

        // Apple only provides name on first sign-in
        let firstName  = cred.fullName?.givenName  ?? ""
        let lastName   = cred.fullName?.familyName ?? ""
        let name       = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")

        // Persist apple user ID → email mapping for future sign-ins (Apple omits email after first)
        if let e = cred.email {
            UserDefaults.standard.set(e, forKey: "hb_apple_\(cred.user)")
        }
        // Inline read — safe from nonisolated context (UserDefaults is Sendable)
        let email = cred.email
            ?? UserDefaults.standard.string(forKey: "hb_apple_\(cred.user)")
            ?? cred.user

        let result = SocialAuthResult(
            name:     name.isEmpty ? email : name,
            email:    email,
            provider: "apple"
        )
        Task { @MainActor in
            self.appleSignInContinuation?.resume(returning: result)
            self.appleSignInContinuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            self.appleSignInContinuation?.resume(throwing: error)
            self.appleSignInContinuation = nil
        }
    }

}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension SocialAuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard
            let scene  = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let window = scene.windows.first(where: { $0.isKeyWindow })
        else {
            // Fallback: return a new window attached to the first available scene
            return UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first ?? UIWindow(windowScene: UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene }).first!)
        }
        return window
    }
}

// MARK: - SocialAuthError
enum SocialAuthError: LocalizedError, Equatable {
    case missingProfile
    case googleSDKNotInstalled
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingProfile:
            return "Could not retrieve your profile. Please try again."
        case .googleSDKNotInstalled:
            return "Google Sign-In is not configured yet. Add the GoogleSignIn package and your client ID."
        case .cancelled:
            return nil     // user cancelled — don't show an error
        }
    }
}
