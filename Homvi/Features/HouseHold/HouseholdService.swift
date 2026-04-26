internal import Foundation
internal import Combine

// MARK: - UserDefaults Keys

private enum HouseholdStorageKeys {
    static let household = "hb_household_v2"
    static let invites   = "hb_householdInvites_v2"
}

// MARK: - HouseholdError

enum HouseholdError: LocalizedError {
    case invalidCode
    case expiredCode
    case alreadyMember
    case notFound
    case notOwner

    var errorDescription: String? {
        switch self {
        case .invalidCode:   return "That invite code doesn't match any pending invitation."
        case .expiredCode:   return "This invite code has expired. Ask the owner for a new one."
        case .alreadyMember: return "You're already a member of a household."
        case .notFound:      return "Household not found."
        case .notOwner:      return "Only an owner or adult member can do that."
        }
    }
}

// MARK: - HouseholdService

@MainActor
final class HouseholdService: ObservableObject {

    // Singleton — accessed as HouseholdService.shared throughout the app.
    // Views must hold a reference via @StateObject or @EnvironmentObject;
    // never use @ObservedObject with a singleton property initialiser.
    static let shared = HouseholdService()

    // MARK: Published State

    @Published private(set) var household: Household?
    @Published private(set) var pendingInvites: [HouseholdInviteRecord] = []

    // MARK: Derived Helpers

    /// Returns the UserDefaults key scoped to the household (or the user if solo).
    func storageKey(base: String, userID: String) -> String {
        if let hid = household?.id {
            return "\(base)_hh_\(hid)"
        }
        return "\(base)_user_\(userID)"
    }

    // MARK: Init

    private init() {
        loadHousehold()
        loadInvites()
    }

    // MARK: - Persistence

    private func loadHousehold() {
        guard
            let data = UserDefaults.standard.data(forKey: HouseholdStorageKeys.household),
            let decoded = try? JSONDecoder().decode(Household.self, from: data)
        else { return }
        household = decoded
    }

    private func saveHousehold() {
        if let h = household, let data = try? JSONEncoder().encode(h) {
            UserDefaults.standard.set(data, forKey: HouseholdStorageKeys.household)
        } else {
            UserDefaults.standard.removeObject(forKey: HouseholdStorageKeys.household)
        }
    }

    private func loadInvites() {
        guard
            let data = UserDefaults.standard.data(forKey: HouseholdStorageKeys.invites),
            let decoded = try? JSONDecoder().decode([HouseholdInviteRecord].self, from: data)
        else { return }
        pendingInvites = decoded
    }

    private func saveInvites() {
        if let data = try? JSONEncoder().encode(pendingInvites) {
            UserDefaults.standard.set(data, forKey: HouseholdStorageKeys.invites)
        }
    }

    // MARK: - Create Household

    /// Called by the first member (owner) to start a new household.
    /// - Parameters:
    ///   - name: The household name chosen by the owner.
    ///   - ownerID: String form of the owner's UUID.
    ///   - ownerUsername: Display name / full name of the owner.
    ///   - ownerEmail: Owner's email address.
    func createHousehold(name: String,
                         ownerID: String,
                         ownerUsername: String,
                         ownerEmail: String) {
        let householdID = "HH-\(generateCode(length: 6))"
        let membership = HouseholdMembership(
            id: ownerID,
            username: ownerUsername,
            email: ownerEmail,
            role: .owner,
            avatarHex: "#4CAF74",
            joinedAt: Date()
        )
        household = Household(
            id: householdID,
            name: name,
            ownerUserID: ownerID,
            members: [membership],
            createdAt: Date()
        )
        saveHousehold()
    }

    // MARK: - Invite a Member

    /// Generates a `HouseholdInviteRecord`, persists it, and opens a mailto: link.
    @discardableResult
    func inviteMember(email: String,
                      role: HouseholdRole,
                      inviterName: String,
                      currentUserID: String) async throws -> HouseholdInviteRecord {
        guard let h = household else { throw HouseholdError.notFound }
        guard let requester = h.members.first(where: { $0.id == currentUserID }),
              requester.role.canManage   // ← fixed: canManage is on HouseholdRole
        else { throw HouseholdError.notOwner }

        let invite = HouseholdInviteRecord(
            id: UUID().uuidString,
            householdID: h.id,
            householdName: h.displayName,
            inviterName: inviterName,
            token: generateToken(householdID: h.id, householdName: h.displayName,
                                 inviterName: inviterName, role: role, inviteeEmail: email),
            inviteeEmail: email,
            role: role,
            createdAt: Date(),
            acceptedAt: nil
        )
        pendingInvites.append(invite)
        saveInvites()
        _ = await EmailService.shared.sendHouseholdInvite(
            to: email,
            inviterName: inviterName,
            householdName: h.displayName,
            token: invite.token
        )
        return invite
    }

    // MARK: - Join a Household

    func joinHousehold(code: String,
                       userID: String,
                       username: String,
                       email: String) throws {
        guard household == nil else { throw HouseholdError.alreadyMember }

        guard let decoded = decodeToken(code) else {
            throw HouseholdError.invalidCode
        }
        guard decoded.expiresAt > Date() else {
            throw HouseholdError.expiredCode
        }

        let membership = HouseholdMembership(
            id: userID,
            username: username,
            email: email,
            role: decoded.role,
            avatarHex: "#C8922A",
            joinedAt: Date()
        )

        // Build a local stub; CloudKit will sync the real data.
        household = Household(
            id: decoded.householdID,
            name: decoded.householdName,
            ownerUserID: "",
            members: [membership],
            createdAt: Date()
        )
        saveHousehold()

        // Mark the invite accepted on this device if the inviter happens to be the same device.
        if let idx = pendingInvites.firstIndex(where: { $0.token == code }) {
            pendingInvites[idx].acceptedAt = Date()
            saveInvites()
        }
    }

    // MARK: - Leave / Remove

    func leaveHousehold(userID: String) {
        guard var h = household else { return }
        h.members.removeAll { $0.id == userID }

        if h.ownerUserID == userID, let newOwner = h.members.first {
            h.ownerUserID = newOwner.id
            if let i = h.members.firstIndex(where: { $0.id == newOwner.id }) {
                h.members[i].role = .owner
            }
        }
        household = h.members.isEmpty ? nil : h
        saveHousehold()
    }

    func removeMember(memberID: String, requestingUserID: String) throws {
        guard var h = household else { throw HouseholdError.notFound }
        guard let requester = h.members.first(where: { $0.id == requestingUserID }),
              requester.role.canManage   // ← fixed
        else { throw HouseholdError.notOwner }
        h.members.removeAll { $0.id == memberID }
        household = h
        saveHousehold()
    }

    // MARK: - Rename

    func renameHousehold(_ newName: String, requestingUserID: String) throws {
        guard var h = household else { throw HouseholdError.notFound }
        guard let requester = h.members.first(where: { $0.id == requestingUserID }),
              requester.role.canManage   // ← fixed
        else { throw HouseholdError.notOwner }
        h.name = newName
        household = h
        saveHousehold()
    }

    // MARK: - Update Own Username

    func updateUsername(_ username: String, userID: String) {
        guard var h = household,
              let i = h.members.firstIndex(where: { $0.id == userID })
        else { return }
        h.members[i].username = username
        household = h
        saveHousehold()
    }

    // MARK: - Revoke Invite

    func revokeInvite(id: String) {
        pendingInvites.removeAll { $0.id == id }
        saveInvites()
    }

    // MARK: - Token Generation & Decoding

    private func generateToken(householdID: String, householdName: String,
                               inviterName: String, role: HouseholdRole,
                               inviteeEmail: String) -> String {
        let expiry = Int(Date().addingTimeInterval(60 * 60 * 24 * 7).timeIntervalSince1970)
        let payload = [householdID, householdName, inviterName, role.rawValue, inviteeEmail, "\(expiry)"]
            .joined(separator: "|")
        let b64 = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "HB-\(b64)"
    }

    private struct DecodedInvite {
        let householdID: String
        let householdName: String
        let inviterName: String
        let role: HouseholdRole
        let inviteeEmail: String
        let expiresAt: Date
    }

    private func decodeToken(_ token: String) -> DecodedInvite? {
        guard token.hasPrefix("HB-") else { return nil }
        var b64 = String(token.dropFirst(3))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = b64.count % 4
        if remainder != 0 { b64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: b64),
              let payload = String(data: data, encoding: .utf8) else { return nil }
        let parts = payload.components(separatedBy: "|")
        guard parts.count == 6,
              let role = HouseholdRole(rawValue: parts[3]),
              let expTS = TimeInterval(parts[5]) else { return nil }
        return DecodedInvite(
            householdID: parts[0],
            householdName: parts[1],
            inviterName: parts[2],
            role: role,
            inviteeEmail: parts[4],
            expiresAt: Date(timeIntervalSince1970: expTS)
        )
    }

    private func generateCode(length: Int) -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // no 0/O/1/I
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }
}
