internal import Foundation
internal import Combine
internal import Supabase
internal import OSLog

// MARK: - UserDefaults Keys

private enum HouseholdStorageKeys {
    static let household = "hemvo_household_v2"
    static let invites   = "hemvo_householdInvites_v2"
}

// MARK: - HouseholdError

enum HouseholdError: LocalizedError {
    case invalidCode
    case expiredCode
    case alreadyMember
    case notFound
    case notOwner
    case emailMismatch             // signed-in account email doesn't match invite recipient
    case emailFailed(code: String) // invite was saved but email delivery failed
    case rateLimitExceeded
    case syncFailed                // the server rejected or never received the change

    var errorDescription: String? {
        switch self {
        case .invalidCode:        return "That invite code doesn't match any pending invitation."
        case .expiredCode:        return "This invite code has expired. Ask the owner for a new one."
        case .alreadyMember:      return "You're already a member of a household."
        case .notFound:           return "Household not found."
        case .notOwner:           return "Only the household owner can do that."
        case .emailMismatch:      return "This invite was sent to a different email address. Sign in with the account that received the invite."
        case .emailFailed(let c): return "Invite saved, but the email couldn't be delivered. Share this code manually: \(c)"
        case .rateLimitExceeded:  return "Too many attempts. Please wait a few minutes and try again."
        case .syncFailed:         return "Couldn't save that change. Check your connection and try again."
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
    @Published private(set) var pendingInvites: [HouseholdInvite] = []

    // MARK: Derived Helpers

    /// Returns the UserDefaults key scoped to the household (or the user if solo).
    func storageKey(base: String, userID: String) -> String {
        if let hid = household?.id {
            return "\(base)_hh_\(hid)"
        }
        return "\(base)_user_\(userID)"
    }

    /// Display name for a household member, for use in "<name> did X" notification text.
    func displayName(forUserID id: UUID?) -> String {
        guard let idString = id?.uuidString,
              let member = household?.members.first(where: { $0.id == idString }) else {
            return "Someone"
        }
        return member.username
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
                Logger.realtime.error("profiles subscribe error: \(error.localizedDescription)")
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
            let decoded = try? JSONDecoder().decode([HouseholdInvite].self, from: data)
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
    /// Writes to Supabase FIRST and only adopts the household locally once the
    /// server has both the `households` row and the owner's claim on it.
    /// Previously this was optimistic + fire-and-forget: a failed insert left a
    /// phone-only household that the next `syncWithProfile` silently wiped
    /// (the profile still had no household_id), taking any data entered in the
    /// meantime with it.
    func createHousehold(name: String,
                         ownerID: String,
                         ownerUsername: String,
                         ownerEmail: String) async throws {
        guard household == nil else { throw HouseholdError.alreadyMember }
        // Use a real UUID so the row can be stored in Supabase's households table.
        let householdUUID = UUID()
        try await upsertHouseholdToSupabase(householdUUID: householdUUID,
                                            name: name,
                                            ownerID: ownerID)
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
    }

    // MARK: - Supabase Sync

    private func upsertHouseholdToSupabase(householdUUID: UUID,
                                           name: String,
                                           ownerID: String) async throws {
        guard let ownerUUID = UUID(uuidString: ownerID) else {
            Logger.household.error("createHousehold: ownerID is not a valid UUID")
            throw HouseholdError.syncFailed
        }
        let row = SupabaseHouseholdRow(id: householdUUID,
                                       name: name,
                                       ownerId: ownerUUID)
        struct ClaimParams: Encodable {
            let pHouseholdId: UUID
            enum CodingKeys: String, CodingKey { case pHouseholdId = "p_household_id" }
        }
        // 1. Insert the household row.
        do {
            try await supabase
                .from("households")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            Logger.household.error("createHousehold insert error: \(error.localizedDescription)")
            throw HouseholdError.syncFailed
        }

        // 2. Claim ownership: sets the owner's household_id and role via a
        // guarded RPC (a raw profiles UPDATE is blocked by
        // guard_profile_privilege_columns).
        do {
            try await supabase
                .rpc("claim_new_household_ownership", params: ClaimParams(pHouseholdId: householdUUID))
                .execute()
        } catch {
            Logger.household.error("createHousehold claim error: \(error.localizedDescription)")
            // Don't leave an orphaned households row nobody belongs to. The
            // owner's profile never got household_id, so this delete cascades
            // to nothing. Best effort — the row is harmless if it survives.
            _ = try? await supabase
                .from("households")
                .delete()
                .eq("id", value: householdUUID.uuidString)
                .execute()
            if error.localizedDescription.contains("already belongs to a household") {
                throw HouseholdError.alreadyMember
            }
            throw HouseholdError.syncFailed
        }

        Logger.household.debug("household created")
    }

    // MARK: - Invite a Member

    /// Inserts an invite row into `household_invites`, persists it locally, and sends the email.
    @discardableResult
    func inviteMember(email: String,
                      role: HouseholdRole,
                      permissions: MemberPermissions? = nil,
                      inviterName: String,
                      currentUserID: String) async throws -> HouseholdInvite {
        guard let h = household else { throw HouseholdError.notFound }
        guard let requester = h.members.first(where: { $0.id == currentUserID }),
              requester.role.canInvite
        else { throw HouseholdError.notOwner }

        let code      = generateInviteCode()
        let expiresAt = Date().addingTimeInterval(60 * 60 * 24 * 7)

        // Append locally first so the invite appears in the UI immediately,
        // before the network round-trip completes.
        let localID = UUID().uuidString
        let invite = HouseholdInvite(
            id:            localID,
            supabaseID:    nil,
            householdID:   h.id,
            householdName: h.displayName,
            inviterName:   inviterName,
            code:          code,
            inviteeEmail:  email,
            role:          role,
            permissions:   permissions,
            createdAt:     Date(),
            acceptedAt:    nil
        )
        pendingInvites.append(invite)
        saveInvites()

        struct InviteInsert: Encodable {
            let code:          String
            let householdId:   String
            let householdName: String
            let inviterName:   String
            let inviteeEmail:  String
            let role:          String
            let permissions:   MemberPermissions?
            let createdBy:     String
            let expiresAt:     Date
            enum CodingKeys: String, CodingKey {
                case code
                case householdId   = "household_id"
                case householdName = "household_name"
                case inviterName   = "inviter_name"
                case inviteeEmail  = "invitee_email"
                case role, permissions
                case createdBy     = "created_by"
                case expiresAt     = "expires_at"
            }
        }
        struct InsertedRow: Decodable { let id: UUID }

        // Persist to Supabase; remove the local ghost and rethrow on failure.
        let rows: [InsertedRow]
        do {
            rows = try await supabase
                .from("household_invites")
                .insert(InviteInsert(
                    code:          code,
                    householdId:   h.id,
                    householdName: h.displayName,
                    inviterName:   inviterName,
                    inviteeEmail:  email,
                    role:          role.rawValue,
                    permissions:   permissions,
                    createdBy:     currentUserID,
                    expiresAt:     expiresAt
                ))
                .select("id")
                .execute()
                .value
        } catch {
            pendingInvites.removeAll { $0.id == localID }
            saveInvites()
            throw error
        }

        // Stamp the server-assigned UUID so revokeInvite can target it precisely.
        if let serverID = rows.first?.id.uuidString,
           let idx = pendingInvites.firstIndex(where: { $0.id == localID }) {
            pendingInvites[idx].supabaseID = serverID
            saveInvites()
        }

        let sent = await EmailService.shared.sendHouseholdInvite(
            to: email,
            inviterName: inviterName,
            householdName: h.displayName,
            code: code
        )
        if !sent { throw HouseholdError.emailFailed(code: code) }
        return invite
    }

    // MARK: - Join a Household

    func joinHousehold(code: String,
                       userID: String,
                       username: String,
                       email: String) async throws {
        guard household == nil else { throw HouseholdError.alreadyMember }

        struct Params: Encodable {
            let pCode: String
            enum CodingKeys: String, CodingKey { case pCode = "p_code" }
        }
        struct JoinResult: Decodable {
            let householdId:   String
            let householdName: String
            let inviterName:   String
            let role:          HouseholdRole
            let permissions:   MemberPermissions?
            enum CodingKeys: String, CodingKey {
                case householdId   = "household_id"
                case householdName = "household_name"
                case inviterName   = "inviter_name"
                case role, permissions
            }
        }

        let result: JoinResult
        do {
            result = try await supabase
                .rpc("join_household_with_code",
                     params: Params(pCode: code.uppercased().trimmingCharacters(in: .whitespaces)))
                .execute()
                .value
        } catch {
            let msg = error.localizedDescription.uppercased()
            if msg.contains("INVALID_CODE") || msg.contains("ALREADY_USED") {
                throw HouseholdError.invalidCode
            } else if msg.contains("EXPIRED_CODE") {
                throw HouseholdError.expiredCode
            } else if msg.contains("EMAIL_MISMATCH") {
                throw HouseholdError.emailMismatch
            } else if msg.contains("ALREADY_MEMBER") {
                throw HouseholdError.alreadyMember
            } else if msg.contains("RATE_LIMIT_EXCEEDED") {
                throw HouseholdError.rateLimitExceeded
            }
            throw error
        }

        // RPC already updated the profile; build local state for an instant UI response.
        let membership = HouseholdMembership(
            id: userID,
            username: username,
            email: email,
            role: result.role,
            avatarHex: "#C8922A",
            joinedAt: Date(),
            permissions: result.permissions
        )
        household = Household(
            id: result.householdId,
            name: result.householdName,
            ownerUserID: "",
            members: [membership],
            createdAt: Date()
        )
        saveHousehold()
        await fetchMembersFromSupabase(householdID: result.householdId)
        PushNotificationService.shared.refreshToken()

        // Notify the owner that their invitee has joined.
        if let ownerID = household?.ownerUserID,
           let ownerUUID = UUID(uuidString: ownerID) {
            Task {
                await PushNotificationService.shared.notifyUsers(
                    [ownerUUID],
                    title: "\(username) joined your household!",
                    body: "\(username) accepted the invite and is now part of \(result.householdName)."
                )
            }
        }
    }

    // MARK: - Leave / Remove

    /// What the server did when the caller left.
    enum LeaveOutcome: String, Decodable {
        case none, left, transferred, deleted
    }

    /// Leaves the current household. The server (`leave_household_safely`)
    /// decides — from the LIVE profiles table, under a row lock — whether an
    /// owner's departure transfers ownership or deletes the household. The
    /// client used to make that call from its cached member list, and a stale
    /// cache could delete a multi-member household (cascading every member's
    /// shared data) or hand ownership to a Teen.
    @discardableResult
    func leaveHousehold() async throws -> LeaveOutcome {
        guard household != nil else { throw HouseholdError.notFound }
        struct Result: Decodable { let action: LeaveOutcome }
        let result: Result
        do {
            result = try await supabase
                .rpc("leave_household_safely")
                .execute()
                .value
        } catch {
            Logger.household.error("leave_household_safely error: \(error.localizedDescription)")
            throw HouseholdError.syncFailed
        }
        // The caller is out of the household server-side in every outcome, so
        // drop all local household state (and the profiles realtime channel).
        // Previously a leaving member kept the household locally whenever
        // anyone else remained in it.
        clearHousehold()
        Logger.household.debug("left household: \(result.action.rawValue)")
        return result.action
    }

    /// Removes a member. The server call happens first; local state only
    /// changes once it succeeds, so a failure can't show a removal that
    /// silently reappears on the next refresh.
    func removeMember(memberID: String, requestingUserID: String) async throws {
        guard let h = household else { throw HouseholdError.notFound }
        // Only the household owner may delete members.
        let isOwner = h.ownerUserID == requestingUserID ||
            h.members.first(where: { $0.id == requestingUserID })?.role == .owner
        guard isOwner else { throw HouseholdError.notOwner }
        guard let memberUUID = UUID(uuidString: memberID) else { throw HouseholdError.notFound }

        struct Params: Encodable {
            let pMemberId: UUID
            enum CodingKeys: String, CodingKey { case pMemberId = "p_member_id" }
        }
        do {
            try await supabase
                .rpc("delete_household_member", params: Params(pMemberId: memberUUID))
                .execute()
        } catch {
            Logger.household.error("delete_household_member error: \(error.localizedDescription)")
            throw HouseholdError.syncFailed
        }

        guard var current = household else { return }
        current.members.removeAll { $0.id == memberID }
        household = current
        saveHousehold()
    }

    func setMemberDisabled(memberID: String, disabled: Bool) async {
        guard let memberUUID = UUID(uuidString: memberID) else {
            Logger.household.error("setMemberDisabled: invalid UUID")
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
            Logger.household.error("set_member_disabled error: \(error.localizedDescription)")
        }
    }

    // MARK: - Rename

    /// Renames the household on the server first, then locally.
    func renameHousehold(_ newName: String, requestingUserID: String) async throws {
        guard let h = household else { throw HouseholdError.notFound }
        guard let requester = h.members.first(where: { $0.id == requestingUserID }),
              requester.role.canInvite
        else { throw HouseholdError.notOwner }

        struct IDOnly: Decodable { let id: UUID }
        let updated: [IDOnly]
        do {
            updated = try await supabase
                .from("households")
                .update(["name": newName])
                .eq("id", value: h.id)
                .select("id")
                .execute()
                .value
        } catch {
            Logger.household.error("renameHousehold error: \(error.localizedDescription)")
            throw HouseholdError.syncFailed
        }
        // households_update RLS is owner-only. A filtered UPDATE returns no
        // error, just zero rows — treat that as "not allowed", not success.
        guard !updated.isEmpty else { throw HouseholdError.notOwner }

        guard var current = household else { return }
        current.name = newName
        household = current
        saveHousehold()
        Logger.household.debug("household renamed")
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
        guard let invite = pendingInvites.first(where: { $0.id == id }) else { return }
        pendingInvites.removeAll { $0.id == id }
        saveInvites()
        let code = invite.code
        Task {
            do {
                try await supabase
                    .from("household_invites")
                    .delete()
                    .eq("code", value: code)
                    .execute()
            } catch {
                Logger.household.error("revokeInvite error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Change Member Role

    /// Changes a member's role (Owner → Adult/Teen not allowed; use leaveHousehold for ownership transfer).
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
            Logger.household.error("changeRole error: \(error.localizedDescription)")
        }
    }

    // MARK: - Member Permissions

    /// Updates a member's notification permissions locally and in Supabase.
    /// Only the household owner is allowed to do this.
    func updateMemberPermissions(memberID: String,
                                 permissions: MemberPermissions,
                                 requestingUserID: String) async throws {
        guard let h = household else { throw HouseholdError.notFound }
        guard h.ownerUserID == requestingUserID else { throw HouseholdError.notOwner }
        // Server first so MemberPermissionsSheet can surface a failure instead
        // of dismissing on a change that never saved.
        do {
            try await sendMemberPermissions(memberID: memberID, permissions: permissions)
        } catch {
            throw HouseholdError.syncFailed
        }
        guard var current = household,
              let i = current.members.firstIndex(where: { $0.id == memberID }) else { return }
        current.members[i].permissions = permissions
        household = current
        saveHousehold()
    }

    /// Fire-and-forget variant used by changeRole and invite auto-apply.
    func updateMemberPermissionsInSupabase(memberID: String, permissions: MemberPermissions) async {
        do {
            try await sendMemberPermissions(memberID: memberID, permissions: permissions)
        } catch {
            Logger.household.error("updatePermissions error: \(error.localizedDescription)")
        }
    }

    private func sendMemberPermissions(memberID: String, permissions: MemberPermissions) async throws {
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
        try await supabase
            .rpc("update_member_permissions",
                 params: Params(pMemberId: memberID, pPermissions: permissions))
            .execute()
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
            // Members with no email are stored as "", so several can share a
            // key — `uniqueKeysWithValues` traps on duplicates and crashed every
            // refresh. Skip blank emails and keep the first of any duplicates.
            let membersByEmail = Dictionary(
                members.filter { !$0.email.isEmpty }.map { ($0.email.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for invite in pendingInvites where invite.isPending {
                guard let invitePermissions = invite.permissions,
                      let joinedMember = membersByEmail[invite.inviteeEmail.lowercased()]
                else { continue }
                let memberID = joinedMember.id
                Task { await self.updateMemberPermissionsInSupabase(memberID: memberID, permissions: invitePermissions) }
            }

            // Refresh pending invites from the server so the list is always
            // authoritative — picks up invites created on other devices and
            // drops invites that were accepted or expired server-side.
            await fetchPendingInvitesFromSupabase(householdID: householdID)
        } catch {
            Logger.household.error("fetchMembers error: \(error.localizedDescription)")
        }
    }

    private func fetchPendingInvitesFromSupabase(householdID: String) async {
        struct InviteRow: Decodable {
            let id:            UUID
            let code:          String
            let householdId:   UUID
            let householdName: String
            let inviterName:   String
            let inviteeEmail:  String
            let role:          String
            let permissions:   MemberPermissions?
            let createdAt:     Date
            let acceptedAt:    Date?
            let expiresAt:     Date
            enum CodingKeys: String, CodingKey {
                case id, code
                case householdId   = "household_id"
                case householdName = "household_name"
                case inviterName   = "inviter_name"
                case inviteeEmail  = "invitee_email"
                case role, permissions
                case createdAt     = "created_at"
                case acceptedAt    = "accepted_at"
                case expiresAt     = "expires_at"
            }
        }
        do {
            let rows: [InviteRow] = try await supabase
                .from("household_invites")
                .select("id,code,household_id,household_name,inviter_name,invitee_email,role,permissions,created_at,accepted_at,expires_at")
                .eq("household_id", value: householdID)
                .execute()
                .value
            let now = Date()
            pendingInvites = rows
                .filter { $0.acceptedAt == nil && $0.expiresAt > now }
                .map { row in
                    HouseholdInvite(
                        id:            row.id.uuidString,
                        supabaseID:    row.id.uuidString,
                        householdID:   row.householdId.uuidString,
                        householdName: row.householdName,
                        inviterName:   row.inviterName,
                        code:          row.code,
                        inviteeEmail:  row.inviteeEmail,
                        role:          HouseholdRole(rawValue: row.role) ?? .adult,
                        permissions:   row.permissions,
                        createdAt:     row.createdAt,
                        acceptedAt:    row.acceptedAt
                    )
                }
            saveInvites()
        } catch {
            // Non-owners get an empty result via RLS — not an error condition.
            Logger.household.error("fetchPendingInvites error: \(error.localizedDescription)")
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
            Logger.household.error("syncWithProfile: verification failed: \(error.localizedDescription)")
        }
    }

    private func clearHousehold() {
        stopProfilesRealtime()
        household      = nil
        pendingInvites = []
        UserDefaults.standard.removeObject(forKey: HouseholdStorageKeys.household)
        UserDefaults.standard.removeObject(forKey: HouseholdStorageKeys.invites)
    }

    // MARK: - Invite Code Generation

    private func generateInviteCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // no ambiguous 0/O/1/I
        let part1 = String((0..<4).compactMap { _ in chars.randomElement() })
        let part2 = String((0..<4).compactMap { _ in chars.randomElement() })
        return "\(part1)-\(part2)"
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
