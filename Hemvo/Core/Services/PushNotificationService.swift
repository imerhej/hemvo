//  PushNotificationService.swift
//  Hemvo
//
//  Stores the device's APNs token in Supabase and calls the
//  `notify-household` Edge Function to push real-time alerts to
//  every other household member when content is created.
//
//  Setup required (one-time, in Supabase dashboard):
//    1. Run the SQL in supabase/functions/notify-household/setup.sql
//    2. Deploy the Edge Function:  supabase functions deploy notify-household
//    3. Set secrets in Supabase:
//         APNS_KEY_ID     — 10-char key ID from Apple Developer portal
//         APNS_TEAM_ID    — 10-char Team ID from Apple Developer portal
//         APNS_PRIVATE_KEY — full contents of the .p8 file (AuthKey_XXXXXX.p8)

internal import Foundation
internal import Supabase
internal import UIKit
internal import OSLog

final class PushNotificationService {

    static let shared = PushNotificationService()
    private init() {}

    // Debug builds use sandbox APNs; release / TestFlight use production.
    #if DEBUG
    static let apnsEnvironment = "sandbox"
    #else
    static let apnsEnvironment = "production"
    #endif

    // MARK: - Token Registration

    /// Called from AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken.
    func registerToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        KeychainHelper.shared.saveString(token, key: "hemvo_apns_token", iCloudSync: false)
        Task { await saveTokenToSupabase(token) }
    }

    /// Refreshes the stored token after login/household-join in case the user
    /// ID or household ID changed since the token was first saved.
    func refreshToken() {
        guard let token = KeychainHelper.shared.loadString(key: "hemvo_apns_token", iCloudSync: false) else { return }
        Task { await saveTokenToSupabase(token) }
    }

    private func saveTokenToSupabase(_ token: String) async {
        guard let uid = await AuthService.shared.currentUserID() else { return }
        // HouseholdService is @MainActor — read both household ID and device ID together.
        let (householdID, deviceID): (UUID?, String) = await MainActor.run {
            let hid = HouseholdService.shared.household.flatMap { UUID(uuidString: $0.id) }
            // IDFV is stable across reinstalls as long as any vendor app remains installed.
            // Using it as the conflict key means token rotation updates the row in-place
            // instead of inserting a duplicate, preventing multi-notification delivery.
            let did = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            return (hid, did)
        }

        struct Row: Encodable {
            let userId:          UUID
            let householdId:     UUID?
            let token:           String
            let apnsEnvironment: String
            let deviceId:        String
            enum CodingKeys: String, CodingKey {
                case userId          = "user_id"
                case householdId     = "household_id"
                case token
                case apnsEnvironment = "apns_environment"
                case deviceId        = "device_id"
            }
        }

        do {
            try await supabase
                .from("device_tokens")
                .upsert(Row(userId: uid, householdId: householdID, token: token,
                            apnsEnvironment: PushNotificationService.apnsEnvironment,
                            deviceId: deviceID),
                        onConflict: "user_id,device_id")
                .execute()
        } catch {
            Logger.push.error("save token error: \(error.localizedDescription)")
        }
    }

    // MARK: - Household Notifications

    /// Sends a push notification to specific users (e.g. event invitees).
    /// The current user is dropped here and again by the Edge Function via
    /// creator_id, so callers may pass member lists that include the sender.
    func notifyUsers(_ userIDs: [UUID], title: String, body: String) async {
        guard let uid = await AuthService.shared.currentUserID() else { return }
        let userIDs = userIDs.filter { $0 != uid }
        guard !userIDs.isEmpty else { return }

        struct Payload: Encodable {
            let userIds:   [String]
            let creatorId: String
            let title:     String
            let body:      String
            enum CodingKeys: String, CodingKey {
                case userIds   = "user_ids"
                case creatorId = "creator_id"
                case title, body
            }
        }

        do {
            try await supabase.functions.invoke(
                "notify-household",
                options: FunctionInvokeOptions(
                    body: Payload(
                        userIds:   userIDs.map { $0.uuidString },
                        creatorId: uid.uuidString,
                        title:     title,
                        body:      body
                    )
                )
            )
        } catch {
            Logger.push.error("notify-users error: \(error.localizedDescription)")
        }
    }

    /// Sends a push to all household members EXCEPT the creator AND the given user IDs.
    /// Used when invitees already receive a personalised push so they don't get two.
    func notifyHouseholdExcluding(userIDs: [UUID], title: String, body: String) async {
        guard !userIDs.isEmpty else {
            await notifyHousehold(title: title, body: body)
            return
        }
        guard let uid = await AuthService.shared.currentUserID() else { return }
        let householdID: String? = await MainActor.run { HouseholdService.shared.household?.id }
        guard let householdID else {
            Logger.push.debug("notifyHouseholdExcluding skipped — household not set")
            return
        }

        struct Payload: Encodable {
            let householdId:    String
            let creatorId:      String
            let excludeUserIds: [String]
            let title:          String
            let body:           String
            enum CodingKeys: String, CodingKey {
                case householdId    = "household_id"
                case creatorId      = "creator_id"
                case excludeUserIds = "exclude_user_ids"
                case title, body
            }
        }

        do {
            try await supabase.functions.invoke(
                "notify-household",
                options: FunctionInvokeOptions(
                    body: Payload(
                        householdId:    householdID,
                        creatorId:      uid.uuidString,
                        excludeUserIds: userIDs.map { $0.uuidString },
                        title:          title,
                        body:           body
                    )
                )
            )
        } catch {
            Logger.push.error("notify-household-excluding error: \(error.localizedDescription)")
        }
    }

    /// Sends a push notification only to household members whose permissions
    /// include the given flag. Falls back to notifyHousehold when no member
    /// list is available (e.g. solo user without a household).
    func notifyHouseholdFiltered(
        permission: KeyPath<MemberPermissions, Bool>,
        title: String, body: String
    ) async {
        let members = await MainActor.run { HouseholdService.shared.household?.members ?? [] }
        guard !members.isEmpty else {
            await notifyHousehold(title: title, body: body)
            return
        }
        let targetIDs = members
            .filter { $0.permissions[keyPath: permission] }
            .compactMap { UUID(uuidString: $0.id) }
        guard !targetIDs.isEmpty else { return }
        await notifyUsers(targetIDs, title: title, body: body)
    }

    /// Sends a push to household members who have the given permission enabled,
    /// excluding the specified user IDs (e.g. invitees who already got a personalised push).
    func notifyHouseholdExcludingFiltered(
        userIDs: [UUID], permission: KeyPath<MemberPermissions, Bool>,
        title: String, body: String
    ) async {
        let members = await MainActor.run { HouseholdService.shared.household?.members ?? [] }
        guard !members.isEmpty else {
            await notifyHouseholdExcluding(userIDs: userIDs, title: title, body: body)
            return
        }
        let excludeSet = Set(userIDs.map { $0.uuidString.lowercased() })
        let targetIDs = members
            .filter { !excludeSet.contains($0.id.lowercased()) && $0.permissions[keyPath: permission] }
            .compactMap { UUID(uuidString: $0.id) }
        guard !targetIDs.isEmpty else { return }
        await notifyUsers(targetIDs, title: title, body: body)
    }

    /// Sends a push to household members who have the given permission enabled,
    /// resolving membership directly from Supabase `profiles` rather than
    /// `HouseholdService`'s in-memory cache. Use this when the household ID is
    /// already resolved (e.g. right after launch, before `HouseholdService`
    /// has ever populated its member list) but the push still needs to honour
    /// each recipient's notification permissions.
    func notifyHouseholdFiltered(
        householdID: String, creatorID: String?,
        permission: KeyPath<MemberPermissions, Bool>,
        title: String, body: String
    ) async {
        struct ProfileRow: Decodable {
            let id: UUID
            let role: String?
            let permissions: MemberPermissions?
        }
        do {
            let profiles: [ProfileRow] = try await supabase
                .from("profiles")
                .select("id, role, permissions")
                .eq("household_id", value: householdID)
                .execute()
                .value
            let targetIDs = profiles.compactMap { row -> UUID? in
                if row.id.uuidString == creatorID { return nil }
                let role  = HouseholdRole(rawValue: row.role ?? "") ?? .adult
                let perms = row.permissions ?? .defaults(for: role)
                return perms[keyPath: permission] ? row.id : nil
            }
            guard !targetIDs.isEmpty else { return }
            await notifyUsers(targetIDs, title: title, body: body)
        } catch {
            Logger.push.error("notify-household-filtered error: \(error.localizedDescription)")
        }
    }

    /// Sends a push to every member of the given household, optionally skipping
    /// the creator. Use this when the household ID is already resolved so the
    /// call doesn't depend on HouseholdService in-memory state being loaded.
    func notifyHousehold(householdID: String, creatorID: String?, title: String, body: String) async {
        struct Payload: Encodable {
            let householdId: String
            let creatorId:   String?
            let title:       String
            let body:        String
            enum CodingKeys: String, CodingKey {
                case householdId = "household_id"
                case creatorId   = "creator_id"
                case title, body
            }
        }
        do {
            try await supabase.functions.invoke(
                "notify-household",
                options: FunctionInvokeOptions(
                    body: Payload(householdId: householdID, creatorId: creatorID,
                                  title: title, body: body)
                )
            )
        } catch {
            Logger.push.error("notify-household error: \(error.localizedDescription)")
        }
    }

    /// Sends a push notification to every household member except the creator.
    /// Fire-and-forget — errors are logged but never surface to the UI.
    func notifyHousehold(title: String, body: String) async {
        guard let uid = await AuthService.shared.currentUserID() else { return }
        let householdID: String? = await MainActor.run { HouseholdService.shared.household?.id }
        guard let householdID else {
            Logger.push.debug("notifyHousehold skipped — household not set")
            return
        }

        struct Payload: Encodable {
            let householdId: String
            let creatorId:   String
            let title:       String
            let body:        String
            enum CodingKeys: String, CodingKey {
                case householdId = "household_id"
                case creatorId   = "creator_id"
                case title, body
            }
        }

        do {
            try await supabase.functions.invoke(
                "notify-household",
                options: FunctionInvokeOptions(
                    body: Payload(
                        householdId: householdID,
                        creatorId:   uid.uuidString,
                        title:       title,
                        body:        body
                    )
                )
            )
        } catch {
            Logger.push.error("notify-household error: \(error.localizedDescription)")
        }
    }
}
