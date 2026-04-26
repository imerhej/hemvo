//  PasswordResetService.swift
//  Homvi
//  Manages password reset tokens for the "forgot password" deep-link flow.
//
//  HOW IT WORKS
//  ────────────────────────────────────────────────────────────────────────
//  1. User enters email in LoginView → sendResetLink() calls generateToken(for:)
//  2. Token is stored in UserDefaults with userID + expiry (30 min)
//  3. App opens Mail with a pre-filled email body containing:
//       homvi://reset-password?token=XXXXXX
//  4. User taps the link on their iPhone → iOS calls scene(_:openURLContexts:)
//  5. HomviApp receives the URL via .onOpenURL and calls handleResetURL(_:)
//  6. If token is valid → app shows ResetPasswordView as a full-screen cover
//  7. User sets new password → validateAndReset(token:newPassword:) is called
//  ────────────────────────────────────────────────────────────────────────

internal import Foundation

// MARK: - PasswordResetService
final class PasswordResetService {

    static let shared = PasswordResetService()
    private init() {}

    private let storageKey = "hb_resetTokens"
    private let expiryMinutes: Double = 30

    // MARK: - Token model
    private struct ResetToken: Codable {
        let token:     String
        let userID:    UUID
        let expiresAt: Date
    }

    // MARK: - Generate a new token for a userID
    func generateToken(for userID: UUID) -> String {
        let chars  = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        let token  = String((0..<32).map { _ in chars.randomElement()! })
        let expiry = Date().addingTimeInterval(expiryMinutes * 60)
        let entry  = ResetToken(token: token, userID: userID, expiresAt: expiry)

        var tokens = loadTokens()
        // Remove any existing tokens for this user
        tokens.removeAll { $0.userID == userID }
        tokens.append(entry)
        saveTokens(tokens)
        return token
    }

    // MARK: - Validate a token; returns the userID if valid
    func validate(token: String) -> UUID? {
        let tokens = loadTokens()
        guard let entry = tokens.first(where: { $0.token == token }) else { return nil }
        guard entry.expiresAt > Date() else {
            // Expired — clean it up
            invalidate(token: token)
            return nil
        }
        return entry.userID
    }

    // MARK: - Parse deep-link URL
    /// Returns the token string from homvi://reset-password?token=XXXXX
    func tokenFromURL(_ url: URL) -> String? {
        guard url.scheme == "homvi",
              url.host == "reset-password",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let tokenItem  = components.queryItems?.first(where: { $0.name == "token" })
        else { return nil }
        return tokenItem.value
    }

    // MARK: - Invalidate (delete) a token after use
    func invalidate(token: String) {
        var tokens = loadTokens()
        tokens.removeAll { $0.token == token }
        saveTokens(tokens)
    }

    // MARK: - Persistence
    private func loadTokens() -> [ResetToken] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let tokens = try? JSONDecoder().decode([ResetToken].self, from: data)
        else { return [] }
        return tokens
    }

    private func saveTokens(_ tokens: [ResetToken]) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
