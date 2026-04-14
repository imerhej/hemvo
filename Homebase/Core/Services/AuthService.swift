//  AuthService.swift
//  HomeBase
//  Handles user creation, login, and session persistence.
//  Replace the in-memory/UserDefaults stub with a real backend (Firebase, Supabase, etc.)

internal import Foundation

// MARK: - AuthError
enum AuthError: LocalizedError {
    case invalidCredentials
    case emailAlreadyInUse
    case weakPassword
    case networkError
    case userNotFound
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:  return "Invalid email or password."
        case .emailAlreadyInUse:   return "An account with this email already exists."
        case .weakPassword:        return "Password must be at least 8 characters."
        case .networkError:        return "Network error. Please check your connection."
        case .userNotFound:        return "No account found with that email."
        case .unknown(let msg):    return msg
        }
    }
}

// MARK: - AuthService
final class AuthService {

    private let userKey    = "hb_currentUser"
    private let usersKey   = "hb_allUsers"          // stores all registered users
    private let passwordKey = "hb_passwords"        // stores hashed passwords (stubbed)

    // MARK: - Create Account
    func createAccount(name: String, email: String, password: String) async throws -> User {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 600_000_000)

        guard password.count >= 8 else { throw AuthError.weakPassword }

        // Check for duplicate
        var users = loadAllUsers()
        if users.contains(where: { $0.email.lowercased() == email.lowercased() }) {
            throw AuthError.emailAlreadyInUse
        }

        let user = User(name: name, email: email.lowercased())
        users.append(user)
        saveAllUsers(users)
        savePassword(password, for: user.id)
        saveCurrentUser(user)
        return user
    }

    // MARK: - Login
    func login(email: String, password: String) async throws -> User {
        try await Task.sleep(nanoseconds: 600_000_000)

        let users = loadAllUsers()
        guard let user = users.first(where: { $0.email.lowercased() == email.lowercased() }) else {
            throw AuthError.userNotFound
        }
        guard checkPassword(password, for: user.id) else {
            throw AuthError.invalidCredentials
        }
        saveCurrentUser(user)
        return user
    }

    // MARK: - Session
    func loadStoredUser() -> User? {
        guard let data = UserDefaults.standard.data(forKey: userKey),
              let user = try? JSONDecoder().decode(User.self, from: data)
        else { return nil }
        return user
    }

    func clearSession() {
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    func updateUser(_ user: User) {
        saveCurrentUser(user)
        var users = loadAllUsers()
        if let idx = users.firstIndex(where: { $0.id == user.id }) {
            users[idx] = user
            saveAllUsers(users)
        }
    }

    /// Public read — needed by AuthViewModel for social login lookup
    func loadAllUsers() -> [User] {
        guard let data = UserDefaults.standard.data(forKey: usersKey),
              let users = try? JSONDecoder().decode([User].self, from: data)
        else { return [] }
        return users
    }

    /// Public write — saves the current session for social login
    func saveCurrentUserPublic(_ user: User) {
        saveCurrentUser(user)
    }

    // MARK: - Change Password
    /// Verifies the current password then replaces it with the new one.
    func changePassword(for userID: UUID, current: String, new: String) throws {
        guard checkPassword(current, for: userID) else {
            throw AuthError.invalidCredentials
        }
        guard new.count >= 8 else { throw AuthError.weakPassword }
        savePassword(new, for: userID)
    }

    /// Resets the password without knowing the old one (Forgot Password flow).
    func resetPassword(for userID: UUID, new: String) throws {
        guard new.count >= 8 else { throw AuthError.weakPassword }
        savePassword(new, for: userID)
    }

    // MARK: - Private Helpers
    private func saveCurrentUser(_ user: User) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: userKey)
    }

    private func saveAllUsers(_ users: [User]) {
        guard let data = try? JSONEncoder().encode(users) else { return }
        UserDefaults.standard.set(data, forKey: usersKey)
    }

    // NOTE: In production, use bcrypt or Keychain — never store plain passwords.
    private func savePassword(_ password: String, for userID: UUID) {
        var map = loadPasswords()
        map[userID.uuidString] = password      // placeholder — hash in production
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: passwordKey)
        }
    }

    private func checkPassword(_ password: String, for userID: UUID) -> Bool {
        let map = loadPasswords()
        return map[userID.uuidString] == password
    }

    private func loadPasswords() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: passwordKey),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }
}
