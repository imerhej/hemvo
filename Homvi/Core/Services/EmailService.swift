// EmailService.swift
// Homvi
//
// Sends transactional emails via the Resend API.
//
// What this handles:
//   ✅ Household invite emails (custom HTML, sent from your domain)
//
// What Supabase handles automatically (no code needed here):
//   ✅ Email verification on signup → Supabase Auth → Email Templates
//   ✅ Password reset emails       → Supabase Auth → Email Templates
//
// SETUP (one-time):
//   1. Go to https://resend.com → create free account (3,000 emails/month free)
//   2. Dashboard → API Keys → Create API Key → paste below
//   3. Use "onboarding@resend.dev" for dev, or verify your own domain
//
// Supabase email template setup:
//   1. Supabase Dashboard → Authentication → Email Templates
//   2. Customise the "Confirm signup" and "Reset password" templates there
//   3. Authentication → Providers → Email → Enable Email Confirmations → ON

internal import Foundation

final class EmailService {

    static let shared = EmailService()
    private init() {}

    // ── CONFIGURE THESE ──────────────────────────────────────────────────
    /// Your Resend API key — https://resend.com/api-keys
    private let apiKey = "re_HK2uiAGo_9SqUTy9vrNrEcM5MKabQLDYP"

    /// Sender address. Use "onboarding@resend.dev" for dev/testing,
    /// or your own verified domain address for production.
    private let fromAddress = "Homvi <onboarding@webstitching.com>"

    private let appName     = "Homvi"
    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    // ─────────────────────────────────────────────────────────────────────

    private let endpoint = URL(string: "https://api.resend.com/emails")!

    // MARK: - Send household invite
    // Called by HouseholdInviteService when an owner invites a family member.
    // Supabase does NOT handle this — it's a custom app-level email.
    func sendHouseholdInvite(
        to email: String,
        inviterName: String,
        householdName: String,
        token: String
    ) async -> Bool {
        let subject = "\(inviterName) invited you to join \(householdName) on \(appName)"
        let html = """
        <!DOCTYPE html>
        <html>
        <body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
                     background:#FAF7F2;margin:0;padding:0;">
          <div style="max-width:480px;margin:40px auto;background:#fff;
                      border-radius:20px;overflow:hidden;
                      box-shadow:0 4px 24px rgba(26,18,8,0.08);">
            <div style="background:linear-gradient(135deg,#C8922A,#E6A83A);
                        padding:36px 32px;text-align:center;">
              <div style="font-size:42px;margin-bottom:8px;">🏠</div>
              <h1 style="color:#fff;margin:0;font-size:24px;font-weight:900;">You're Invited!</h1>
              <p style="color:rgba(255,255,255,0.85);margin:6px 0 0;font-size:14px;">
                \(inviterName) wants you in \(householdName)
              </p>
            </div>
            <div style="padding:36px 32px;">
              <p style="color:#1A1208;font-size:16px;line-height:1.6;margin:0 0 24px;">
                Hi there! \(inviterName) has invited you to join
                <strong>\(householdName)</strong> on \(appName) — share meals,
                budgets, and schedules with your household.
              </p>
              <p style="color:#1A1208;font-size:14px;font-weight:700;margin:0 0 8px;">
                Your invite token:
              </p>
              <div style="background:#FAF7F2;border:2px solid #E6DDD0;border-radius:12px;
                          padding:16px;word-break:break-all;font-size:12px;
                          font-family:monospace;color:#C8922A;margin:0 0 24px;">
                \(token)
              </div>
              <p style="color:#1A1208;font-size:14px;font-weight:700;margin:0 0 12px;">
                How to join:
              </p>
              <ol style="color:#7A6A55;font-size:14px;line-height:1.8;margin:0 0 24px;
                         padding-left:20px;">
                <li>Download \(appName) from the App Store</li>
                <li>Create your account (or sign in)</li>
                <li>Go to Settings → Join a Household</li>
                <li>Paste the token above</li>
              </ol>
              <p style="color:#7A6A55;font-size:13px;margin:0;">
                This invite expires in <strong>7 days</strong>.
              </p>
            </div>
            <div style="border-top:1px solid #E6DDD0;padding:20px 32px;text-align:center;">
              <p style="color:#7A6A55;font-size:12px;margin:0;">
                © \(currentYear) \(appName) · Sent with ❤️
              </p>
            </div>
          </div>
        </body>
        </html>
        """
        return await send(to: email, subject: subject, html: html)
    }

    // MARK: - Core send
    @discardableResult
    private func send(to recipient: String, subject: String, html: String) async -> Bool {
        var request        = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "from":    fromAddress,
            "to":      [recipient],
            "subject": subject,
            "html":    html
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            print("EmailService: failed to serialize body")
            return false
        }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 200 || statusCode == 201 {
                print("EmailService: ✅ Email sent to \(recipient)")
                return true
            } else {
                let body = String(data: data, encoding: .utf8) ?? "unknown"
                print("EmailService: ❌ Failed (\(statusCode)) — \(body)")
                return false
            }
        } catch {
            print("EmailService: ❌ Network error — \(error.localizedDescription)")
            return false
        }
    }
}
