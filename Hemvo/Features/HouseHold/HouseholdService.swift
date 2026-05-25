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
        case .notOwner:           return "Only the household owner can do that."
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

    // MARK: Realtime (profiles — live role/permissions updates)

    private var profilesRealtimeTask:    Task<Void, Never>?
    private var profilesRealtimeChannel: RealtimeChannelV2?

    private func startProfilesRealtime(householdID: String) {
        let channel = supabase.realtimeV2.channel("profiles:\(householdID):\(UUID().uuidString)")
        profilesRealtimeChannel = channel

        profilesRealtimeTask = Task { [weak self, channel] in
            // Register the listener BEFORE subscribing (required by the SDK).
            // Realtime CDC delivers UUIDs in lowercase; pass lowercase for filter match.
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "profiles",
                filter: .eq("household_id", value: householdID.lowercased())
            )

            do {
                try await channel.subscribeWithError()
            } catch {
                print("[Realtime] profiles subscribe error: \(error)")
                await MainActor.run { [weak self] in self?.profilesRealtimeTask = nil }
                return
            }

            for await _ in changes {
                guard !Task.isCancelled, let self else { break }
                // Small debounce — role changes are rare but the owner's device
                // fires its own UPDATE event too; skip any duplicate bursts.
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { break }
                await self.refreshMembers()
            }

            if !Task.isCancelled {
                await MainActor.run { [weak self] in self?.profilesRealtimeTask = nil }
            }
        }
    }

    private func stopProfilesRealtime() {
        profilesRealtimeTask?.cancel()
        profilesRealtimeTask = nil
        if let ch = profilesRealtimeChannel {
            Task { await supabase.realtimeV2.removeChannel(ch) }
        }
        profilesRealtimeChannel = nil
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
                      permissions: MemberPermissions? = nil,
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
            permissions: permissions,
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
        let wasOwner = h.ownerUserID == userID
        h.members.removeAll { $0.id == userID }

        if wasOwner, let newOwner = h.members.first {
            // Transfer ownership locally then sync both changes to Supabase.
            h.ownerUserID = newOwner.id
            if let i = h.members.firstIndex(where: { $0.id == newOwner.id }) {
                h.members[i].role = .owner
            }
            let householdID = h.id
            let newOwnerID  = newOwner.id
            Task { await transferOwnershipInSupabase(householdID: householdID,
                                                     newOwnerID:  newOwnerID,
                                                     leavingUserID: userID) }
        } else if wasOwner {
            // Owner is the sole member — delete the household entirely.
            let householdID = h.id
            Task { await deleteHouseholdFromSupabase(householdID: householdID) }
        } else {
            // Regular member leaving — just clear their profile.
            Task { await clearProfileHousehold(userID: userID) }
        }

        household = h.members.isEmpty ? nil : h
        saveHousehold()
    }

    func removeMember(memberID: String, requestingUserID: String) throws {
        guard var h = household else { throw HouseholdError.notFound }
        // Only the household owner may delete members.
        let isOwner = h.ownerUserID == requestingUserID ||
            h.members.first(where: { $0.id == requestingUserID })?.role == .owner
        guard isOwner else { throw HouseholdError.notOwner }
        h.members.removeAll { $0.id == memberID }
        household = h
        saveHousehold()
        Task { await deleteMemberFromSupabase(memberID: memberID) }
    }

    func deleteMemberFromSupabase(memberID: String) async {
        guard let memberUUID = UUID(uuidString: memberID) else {
            print("[HouseholdService] deleteMember: invalid UUID — \(memberID)")
            return
        }
        struct Params: Encodable {
            let pMemberId: UUID
            enum CodingKeys: String, CodingKey { case pMemberId = "p_member_id" }
        }
        do {
            try await supabase
                .rpc("delete_household_member", params: Params(pMemberId: memberUUID))
                .execute()
        } catch {
            print("[HouseholdService] delete_household_member error: \(error.localizedDescription)")
        }
    }

    func setMemberDisabled(memberID: String, disabled: Bool) async {
        guard let memberUUID = UUID(uuidString: memberID) else {
            print("[HouseholdService] setMemberDisabled: invalid UUID — \(memberID)")
            return
        }
        struct Params: Encodable {
            let pMemberId: UUID
            let pDisabled: Bool
            enum CodingKeys: String, CodingKey {
                case pMemberId = "p_member_id"
                case pDisabled = "p_disabled"
            }
        }
        do {
            try await supabase
                .rpc("set_member_disabled",
                     params: Params(pMemberId: memberUUID, pDisabled: disabled))
                .execute()
            // Update local state immediately so the UI reflects the change.
            if var h = household,
               let i = h.members.firstIndex(where: { $0.id == memberID }) {
                h.members[i].isDisabled = disabled
                household = h
                saveHousehold()
            }
        } catch {
            print("[HouseholdService] set_member_disabled error: \(error.localizedDescription)")
        }
    }

    // Nullifies household_id and role on a profile row.
    // Uses explicit encode(to:) so nil is sent as JSON null, not omitted.
    private func clearProfileHousehold(userID: String) async {
        struct NullFields: Encodable {
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(String?.none, forKey: .householdId)
                try c.encode(String?.none, forKey: .role)
            }
            enum CodingKeys: String, CodingKey {
                case householdId = "household_id"
                case role
            }
        }
        do {
            try await supabase
                .from("profiles")
                .update(NullFields())
                .eq("id", value: userID)
                .execute()
            print("[Supabase] profile household cleared: \(userID)")
        } catch {
            print("[Supabase] clearProfileHousehold error: \(error)")
        }
    }

    private func transferOwnershipInSupabase(householdID: String,
                                             newOwnerID: String,
                                             leavingUserID: String) async {
        do {
            // Update the household's owner_id — RLS allows this while the
            // leaving user's session is still active (owner_id = auth.uid()).
            try await supabase
                .from("households")
                .update(["owner_id": newOwnerID])
                .eq("id", value: householdID)
                .execute()
            // Promote the new owner's role in profiles.
            try await supabase
                .from("profiles")
                .update(["role": HouseholdRole.owner.rawValue])
                .eq("id", value: newOwnerID)
                .execute()
            print("[Supabase] ownership transferred to: \(newOwnerID)")
        } catch {
            print("[Supabase] transferOwnership error: \(error)")
        }
        // Clear the leaving owner's own profile regardless of the above outcome.
        await clearProfileHousehold(userID: leavingUserID)
    }

    private func deleteHouseholdFromSupabase(householdID: String) async {
        do {
            try await supabase
                .from("households")
                .delete()
                .eq("id", value: householdID)
                .execute()
            print("[Supabase] household deleted: \(householdID)")
        } catch {
            print("[Supabase] deleteHousehold error: \(error)")
        }
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

    // MARK: - Change Member Role

    /// Changes a member's role (Owner → Adult/Teen/Child not allowed; use leaveHousehold for ownership transfer).
    /// Resets permissions to the new role's defaults and syncs both to Supabase via SECURITY DEFINER RPCs.
    func changeRole(memberID: String,
                    newRole: HouseholdRole,
                    requestingUserID: String) async throws {
        guard newRole != .owner else { return }
        guard var h = household else { throw HouseholdError.notFound }
        guard h.ownerUserID == requestingUserID else { throw HouseholdError.notOwner }

        let newPermissions = MemberPermissions.defaults(for: newRole)
        if let i = h.members.firstIndex(where: { $0.id == memberID }) {
            h.members[i].role        = newRole
            h.members[i].permissions = newPermissions
            household = h
            saveHousehold()
        }

        // Both columns need SECURITY DEFINER RPCs — direct .update() is blocked by RLS.
        async let roleUpdate: Void        = updateRoleInSupabase(memberID: memberID, role: newRole)
        async let permUpdate: Void        = updateMemberPermissionsInSupabase(memberID: memberID, permissions: newPermissions)
        _ = await (roleUpdate, permUpdate)
    }

    private func updateRoleInSupabase(memberID: String, role: HouseholdRole) async {
        struct Params: Encodable {
            let pMemberId: String
            let pRole:     String
            enum CodingKeys: String, CodingKey {
                case pMemberId = "p_member_id"
                case pRole     = "p_role"
            }
        }
        do {
            try await supabase
                .rpc("update_member_role",
                     params: Params(pMemberId: memberID, pRole: role.rawValue))
                .execute()
        } catch {
            print("[HouseholdService] changeRole error: \(error)")
        }
    }

    // MARK: - Member Permissions

    /// Updates a member's notification permissions locally and in Supabase.
    /// Only the household owner is allowed to do this.
    func updateMemberPermissions(memberID: String,
                                 permissions: MemberPermissions,
                                 requestingUserID: String) async throws {
        guard var h = household else { throw HouseholdError.notFound }
        guard h.ownerUserID == requestingUserID else { throw HouseholdError.notOwner }
        if let i = h.members.firstIndex(where: { $0.id == memberID }) {
            h.members[i].permissions = permissions
            household = h
            saveHousehold()
        }
        await updateMemberPermissionsInSupabase(memberID: memberID, permissions: permissions)
    }

    func updateMemberPermissionsInSupabase(memberID: String, permissions: MemberPermissions) async {
        // Direct .update() is blocked by RLS (profiles: only own row).
        // Call the SECURITY DEFINER RPC which validates ownership server-side
        // and updates only the `permissions` column.
        // Explicit CodingKeys required: the SDK uses default (camelCase) encoding,
        // but PostgREST matches parameter names by their exact SQL identifiers.
        struct Params: Encodable {
            let pMemberId:    String
            let pPermissions: MemberPermissions
            enum CodingKeys: String, CodingKey {
                case pMemberId    = "p_member_id"
                case pPermissions = "p_permissions"
            }
        }
        do {
            try await supabase
                .rpc("update_member_permissions",
                     params: Params(pMemberId: memberID, pPermissions: permissions))
                .execute()
        } catch {
            print("[HouseholdService] updatePermissions error: \(error)")
        }
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
                let permissions = profile.permissions ?? .defaults(for: role)
                return HouseholdMembership(
                    id: profileID,
                    username: profile.fullName ?? profile.username ?? "Member",
                    email: profile.email ?? "",
                    role: role,
                    avatarHex: profile.avatarColor ?? "#C8922A",
                    joinedAt: profile.createdAt ?? Date(),
                    permissions: permissions,
                    isDisabled: profile.disabled ?? false
                )
            }

            guard var h = household else { return }
            h.ownerUserID = ownerID
            h.name = householdRow.name
            h.members = members
            household = h
            saveHousehold()

            // Start a Realtime subscription the first time we have a valid household.
            // Guards against duplicates: only starts when the previous task is gone.
            if profilesRealtimeTask == nil {
                startProfilesRealtime(householdID: householdID)
            }

            // Auto-apply permissions from pending invite records when the member just joined.
            // This lets the owner pre-configure permissions before the invite is sent.
            let membersByEmail = Dictionary(uniqueKeysWithValues: members.map { ($0.email.lowercased(), $0) })
            for invite in pendingInvites where invite.isPending {
                guard let invitePermissions = invite.permissions,
                      let joinedMember = membersByEmail[invite.inviteeEmail.lowercased()]
                else { continue }
                let memberID = joinedMember.id
                Task { await self.updateMemberPermissionsInSupabase(memberID: memberID, permissions: invitePermissions) }
            }

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
        stopProfilesRealtime()
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
