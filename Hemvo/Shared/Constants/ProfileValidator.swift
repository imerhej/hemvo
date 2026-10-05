//  ProfileValidator.swift
//  Hemvo
//  Single source of truth for full-name and username rules.
//  Used by sign-up (LoginView) and profile editing (ProfileView) so the two
//  can't drift apart. Mirrored server-side in the `create-account` Edge
//  Function and by the profiles table CHECK constraints.

internal import Foundation

enum ProfileValidator {

    /// Letters plus the separators that appear in real names ("Ana-Maria", "O'Neil").
    private static let nameAllowed = CharacterSet.letters.union(.init(charactersIn: " -'"))
    private static let usernameAllowed = CharacterSet.alphanumerics.union(.init(charactersIn: "_"))

    static func isValidName(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= AppConstants.minNameLength,
              trimmed.count <= AppConstants.maxNameLength else { return false }
        return trimmed.unicodeScalars.allSatisfy { nameAllowed.contains($0) }
    }

    static func isValidUsername(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= AppConstants.minUsernameLength,
              trimmed.count <= AppConstants.maxUsernameLength else { return false }
        return trimmed.unicodeScalars.allSatisfy { usernameAllowed.contains($0) }
    }

    static let nameHint     = "Min \(AppConstants.minNameLength) characters, letters only"
    static let usernameHint = "Min \(AppConstants.minUsernameLength) characters, letters, numbers and _ only"
}
