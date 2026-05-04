internal import Foundation
internal import Combine
internal import Supabase

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
    case emailFailed(code: String) // invite was saved but email delivery failed

    var errorDescription: String? {
        switch self {
        case .invalidCode:        return "That invite code doesn't match any pending invitation."
        case .expiredCode:        return "This invite code has expired. Ask the owner for a new one."
        case .alreadyMember:      return "You're already a member of a household."
        case .notFound:           return "Household not found."
        case .notOwner:           return "Only an owner or adult member can do that."
        case .emailFailed(let c): return "Invite saved, but the email couldn't be delivered. Share this code manually: \(c)"
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
    /// Creates the record locally first (for instant UI response), then
    /// inserts it into the Supabase `households` table and updates the
    /// owner's `profiles.household_id` in the background.
    func createHousehold(name: String,
                         ownerID: String,
                         ownerUsername: String,
                         ownerEmail: String) {
        // Use a real UUID so the row can be stored in Supabase's households table.
        let householdUUID = UUID()
        let membership = HouseholdMembership(
            id: ownerID,
            username: ownerUsername,
            email: ownerEmail,
            role: .owner,
            avatarHex: "#4CAF74",
            joinedAt: Date()
        )
        household = Household(
            id: householdUUID.uuidString,
            name: name,
            ownerUserID: ownerID,
            members: [membership],
            createdAt: Date()
        )
        saveHousehold()
        PushNotificationService.shared.refreshToken()
        // Sync to Supabase without blocking the caller.
        Task { await upsertHouseholdToSupabase(householdUUID: householdUUID,
                                               name: name,
                                               ownerID: ownerID) }
    }

    // MARK: - Supabase Sync

    private func upsertHouseholdToSupabase(householdUUID: UUID,
                                           name: String,
                                           ownerID: String) async {
        guard let ownerUUID = UUID(uuidString: ownerID) else {
            print("[Supabase] createHousehold: ownerID is not a valid UUID — \(ownerID)")
            return
        }
        let row = SupabaseHouseholdRow(id: householdUUID,
                                       name: name,
                                       ownerId: ownerUUID)
        do {
            // 1. Insert the household row.
            try await supabase
                .from("households")
                .upsert(row, onConflict: "id")
                .execute()

            // 2. Update the owner's profile: set household_id and role.
            try await supabase
                .from("profiles")
                .update(["household_id": householdUUID.uuidString,
                         "role": HouseholdRole.owner.rawValue])
                .eq("id", value: ownerID)
                .execute()

            print("[Supabase] household created: \(householdUUID.uuidString)")
        } catch {
            print("[Supabase] createHousehold error: \(error)")
        }
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
              requester.role.canInvite
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
        let sent = await EmailService.shared.sendHouseholdInvite(
            to: email,
            inviterName: inviterName,
            householdName: h.displayName,
            token: invite.token
        )
        // Invite record is always persisted so the invitee can still join via code.
        // Throw only if email delivery failed so the UI can surface a fallback message.
        if !sent { throw HouseholdError.emailFailed(code: invite.displayCode) }
        return invite
    }

    // MARK: - Join a Household

    func joinHousehold(code: String,
                       userID: String,
                       username: String,
                       email: String) async throws {
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

        household = Household(
            id: decoded.householdID,
            name: decoded.householdName,
            ownerUserID: "",
            members: [membership],
            createdAt: Date()
        )
        saveHousehold()

        // Write household_id and role to this user's Supabase profile.
        // This lets every ViewModel scope its Supabase queries by household,
        // and lets other members see the correct role on their next refresh.
        do {
            try await supabase
                .from("profiles")
                .update(["household_id": decoded.householdID,
                         "role": decoded.role.rawValue])
                .eq("id", value: userID)
                .execute()
        } catch {
            print("[Supabase] joinHousehold: failed to update profile — \(error)")
        }

        // Fetch the full member list so this user immediately sees everyone in the household.
        await fetchMembersFromSupabase(householdID: decoded.householdID)
        PushNotificationService.shared.refreshToken()
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
              requester.role.canInvite
        else { throw HouseholdError.notOwner }
        h.members.removeAll { $0.id == memberID }
        household = h
        saveHousehold()
    }

    // MARK: - Rename

    func renameHousehold(_ newName: String, requestingUserID: String) throws {
        guard var h = household else { throw HouseholdError.notFound }
        guard let requester = h.members.first(where: { $0.id == requestingUserID }),
              requester.role.canInvite
        else { throw HouseholdError.notOwner }
        h.name = newName
        household = h
        saveHousehold()
        let householdID = h.id
        Task { await updateHouseholdNameInSupabase(householdID: householdID, newName: newName) }
    }

    private func updateHouseholdNameInSupabase(householdID: String, newName: String) async {
        do {
            try await supabase
                .from("households")
                .update(["name": newName])
                .eq("id", value: householdID)
                .execute()
            print("[Supabase] household renamed to: \(newName)")
        } catch {
            print("[Supabase] renameHousehold error: \(error)")
        }
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

    // MARK: - Fetch & Refresh Members from Supabase

    /// Refreshes the member list for the current household from Supabase.
    /// Call this when the members view appears or after a join/create.
    func refreshMembers() async {
        guard let h = household else { return }
        await fetchMembersFromSupabase(householdID: h.id)
    }

    private func fetchMembersFromSupabase(householdID: String) async {
        do {
            // Fetch the household row to get the authoritative owner_id and name.
            let householdRows: [SupabaseHouseholdRow] = try await supabase
                .from("households")
                .select("id,name,owner_id")
                .eq("id", value: householdID)
                .limit(1)
                .execute()
                .value
            guard let householdRow = householdRows.first else { return }
            let ownerID = householdRow.ownerId.uuidString

            // Fetch every profile that belongs to this household.
            let profiles: [HemvoProfile] = try await supabase
                .from("profiles")
                .select()
                .eq("household_id", value: householdID)
                .execute()
                .value
            guard !profiles.isEmpty else { return }

            let members: [HouseholdMembership] = profiles.map { profile in
                let profileID = profile.id.uuidString
                let role: HouseholdRole
                if profileID == ownerID {
                    role = .owner
                } else if let roleStr = profile.role,
                          let decoded = HouseholdRole(rawValue: roleStr) {
                    role = decoded
                } else {
                    role = .adult
                }
                return HouseholdMembership(
                    id: profileID,
                    username: profile.fullName ?? profile.username ?? "Member",
                    email: profile.email ?? "",
                    role: role,
                    avatarHex: profile.avatarColor ?? "#C8922A",
                    joinedAt: profile.createdAt ?? Date()
                )
            }

            guard var h = household else { return }
            h.ownerUserID = ownerID
            h.name = householdRow.name
            h.members = members
            household = h
            saveHousehold()

            // Drop pending invites whose invitee has now joined the household.
            let memberEmails = Set(members.map { $0.email.lowercased() })
            let before = pendingInvites.count
            pendingInvites.removeAll { memberEmails.contains($0.inviteeEmail.lowercased()) }
            if pendingInvites.count != before { saveInvites() }
        } catch {
            print("[HouseholdService] fetchMembers error: \(error)")
        }
    }

    // MARK: - Sync with Supabase profile on login

    /// Called after every profile load. Clears stale local household data when:
    /// • the profile has no household_id (household was deleted + cascade nullified the FK)
    /// • the profile's household_id doesn't match the local cache (user was removed / switched)
    /// • the profile's household_id matches but the households row no longer exists in Supabase
    func syncWithProfile(_ profile: HemvoProfile) async {
        guard let profileHouseholdId = profile.householdId else {
            clearHousehold()
            return
        }

        // IDs match — do a lightweight check that the row still exists, then refresh members.
        struct IDOnly: Decodable { let id: UUID }
        do {
            let rows: [IDOnly] = try await supabase
                .from("households")
                .select("id")
                .eq("id", value: profileHouseholdId.uuidString)
                .limit(1)
                .execute()
                .value
            if rows.isEmpty {
                clearHousehold()
            } else {
                // Household is valid — bootstrap local state if missing, then fetch fresh members.
                if household == nil {
                    household = Household(
                        id: profileHouseholdId.uuidString,
                        name: "",
                        ownerUserID: "",
                        members: [],
                        createdAt: Date()
                    )
                }
                await fetchMembersFromSupabase(householdID: profileHouseholdId.uuidString)
            }
        } catch {
            // Network failure — keep local state and retry on next login.
            print("[HouseholdService] syncWithProfile: verification failed — \(error)")
        }
    }

    private func clearHousehold() {
        household      = nil
        pendingInvites = []
        UserDefaults.standard.removeObject(forKey: HouseholdStorageKeys.household)
        UserDefaults.standard.removeObject(forKey: HouseholdStorageKeys.invites)
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
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
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

// MARK: - Supabase row mapping

private struct SupabaseHouseholdRow: Codable {
    let id:      UUID
    var name:    String
    let ownerId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerId = "owner_id"
    }
}
