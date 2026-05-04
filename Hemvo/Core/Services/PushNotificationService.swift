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

final class PushNotificationService {

    static let shared = PushNotificationService()
    private init() {}

    // MARK: - Token Registration

    /// Called from AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken.
    func registerToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "hb_apns_token")
        Task { await saveTokenToSupabase(token) }
    }

    /// Refreshes the stored token after login/household-join in case the user
    /// ID or household ID changed since the token was first saved.
    func refreshToken() {
        guard let token = UserDefaults.standard.string(forKey: "hb_apns_token") else { return }
        Task { await saveTokenToSupabase(token) }
    }

    private func saveTokenToSupabase(_ token: String) async {
        guard let uid = await AuthService.shared.currentUserID() else { return }
        let householdID = HouseholdService.shared.household.map { UUID(uuidString: $0.id) } ?? nil

        struct Row: Encodable {
            let userId:      UUID
            let householdId: UUID?
            let token:       String
            enum CodingKeys: String, CodingKey {
                case userId      = "user_id"
                case householdId = "household_id"
                case token
            }
        }

        do {
            try await supabase
                .from("device_tokens")
                .upsert(Row(userId: uid, householdId: householdID, token: token),
                        onConflict: "user_id,token")
                .execute()
        } catch {
            print("[Push] save token error: \(error)")
        }
    }

    // MARK: - Household Notifications

    /// Sends a push notification to specific users (e.g. event invitees).
    /// Skips the current user automatically via creator_id on the Edge Function.
    func notifyUsers(_ userIDs: [UUID], title: String, body: String) async {
        guard !userIDs.isEmpty else { return }
        guard let uid = await AuthService.shared.currentUserID() else { return }

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
            print("[Push] notify-users error: \(error)")
        }
    }

    /// Sends a push notification to every household member except the creator.
    /// Fire-and-forget — errors are logged but never surface to the UI.
    func notifyHousehold(title: String, body: String) async {
        guard let uid = await AuthService.shared.currentUserID() else { return }
        guard let householdID = HouseholdService.shared.household?.id else { return }

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
            print("[Push] notify-household error: \(error)")
        }
    }
}
