// EmailService.swift
// Hemvo
//
// Sends household invite emails by invoking the `send-invite-email` Supabase
// Edge Function. The Resend API key lives server-side in that function —
// it is never embedded in the app binary.
//
// Deploy the function once:
//   supabase functions deploy send-invite-email
//   supabase secrets set RESEND_API_KEY=re_xxxx
//   supabase secrets set FROM_ADDRESS="Hemvo <noreply@yourdomain.com>"

internal import Foundation
internal import Supabase

final class EmailService {

    static let shared = EmailService()
    private init() {}

    // MARK: - Send household invite
    /// Invokes the `send-invite-email` Edge Function with the caller's auth token.
    /// HTML escaping and Resend delivery are handled entirely server-side.
    func sendHouseholdInvite(
        to email:         String,
        inviterName:      String,
        householdName:    String,
        token:            String
    ) async -> Bool {
        struct Payload: Encodable {
            let to:            String
            let inviterName:   String
            let householdName: String
            let token:         String
        }

        do {
            try await supabase.functions.invoke(
                "send-invite-email",
                options: FunctionInvokeOptions(
                    body: Payload(
                        to:            email,
                        inviterName:   inviterName,
                        householdName: householdName,
                        token:         token
                    )
                )
            )
            print("EmailService: ✅ invite dispatched to \(email)")
            return true
        } catch {
            print("EmailService: ❌ Edge Function error — \(error.localizedDescription)")
            return false
        }
    }
}
