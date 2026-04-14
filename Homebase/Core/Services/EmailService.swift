//  EmailService.swift
//  HomeBase
//  Sends transactional emails via the Resend API.
//
//  SETUP (one-time, ~5 minutes):
//  ─────────────────────────────────────────────────────────────────────────
//  1. Go to https://resend.com and create a free account (3,000 emails/month free)
//  2. In the Resend dashboard → API Keys → Create API Key
//  3. Paste your key into the `apiKey` constant below
//  4. Add a "From" domain OR use Resend's shared domain for testing:
//       "onboarding@resend.dev"  ← works immediately, no domain needed
//  5. Replace `fromAddress` below with your verified address or keep the
//     shared domain address for development.
//
//  That's it — no backend, no server, works directly from the iOS app.
//  ─────────────────────────────────────────────────────────────────────────

internal import Foundation

// MARK: - EmailService
final class EmailService {

    static let shared = EmailService()
    private init() {}

    // ── CONFIGURE THESE ──────────────────────────────────────────────────
    /// Your Resend API key from https://resend.com/api-keys
    private let apiKey      = "re_HK2uiAGo_9SqUTy9vrNrEcM5MKabQLDYP"

    /// Verified sender address. Use "onboarding@resend.dev" for dev/testing
    /// or your own domain once verified in the Resend dashboard.
    private let fromAddress = "HomeBaserun <onboarding@resend.dev>"

    /// App name shown in email subjects
    private let appName     = "HomeBaserun"
    // ─────────────────────────────────────────────────────────────────────

    private let endpoint = URL(string: "https://api.resend.com/emails")!

    // MARK: - Send verification code
    func sendVerificationCode(to email: String, code: String) async -> Bool {
        let subject = "Your \(appName) verification code"
        let html = """
        <!DOCTYPE html>
        <html>
        <body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
                     background:#FAF7F2;margin:0;padding:0;">
          <div style="max-width:480px;margin:40px auto;background:#fff;
                      border-radius:20px;overflow:hidden;
                      box-shadow:0 4px 24px rgba(26,18,8,0.08);">
            <!-- Header -->
            <div style="background:linear-gradient(135deg,#C8922A,#E6A83A);
                        padding:36px 32px;text-align:center;">
              <div style="font-size:42px;margin-bottom:8px;">🏠</div>
              <h1 style="color:#fff;margin:0;font-size:24px;font-weight:900;
                         letter-spacing:-0.5px;">\(appName)</h1>
              <p style="color:rgba(255,255,255,0.85);margin:6px 0 0;
                        font-size:14px;">Verify your email address</p>
            </div>
            <!-- Body -->
            <div style="padding:36px 32px;">
              <p style="color:#1A1208;font-size:16px;line-height:1.6;margin:0 0 24px;">
                Hi there! Enter this code in the HomeBase app to verify your email and activate your account.
              </p>
              <!-- Code box -->
              <div style="background:#FAF7F2;border:2px solid #E6DDD0;
                          border-radius:16px;padding:24px;text-align:center;
                          margin:0 0 24px;">
                <div style="font-size:42px;font-weight:900;letter-spacing:10px;
                            color:#C8922A;font-variant-numeric:tabular-nums;">
                  \(code)
                </div>
                <p style="color:#7A6A55;font-size:13px;margin:12px 0 0;">
                  This code expires in <strong>10 minutes</strong>
                </p>
              </div>
              <p style="color:#7A6A55;font-size:13px;line-height:1.6;margin:0;">
                If you didn't create a HomeBase account, you can safely ignore this email.
              </p>
            </div>
            <!-- Footer -->
            <div style="border-top:1px solid #E6DDD0;padding:20px 32px;text-align:center;">
              <p style="color:#7A6A55;font-size:12px;margin:0;">
                © 2025 \(appName) · Sent with ❤️
              </p>
            </div>
          </div>
        </body>
        </html>
        """
        return await send(to: email, subject: subject, html: html)
    }

    // MARK: - Send password reset link
    func sendPasswordResetLink(to email: String, resetURL: String, firstName: String) async -> Bool {
        let subject = "Reset your \(appName) password"
        let html = """
        <!DOCTYPE html>
        <html>
        <body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
                     background:#FAF7F2;margin:0;padding:0;">
          <div style="max-width:480px;margin:40px auto;background:#fff;
                      border-radius:20px;overflow:hidden;
                      box-shadow:0 4px 24px rgba(26,18,8,0.08);">
            <!-- Header -->
            <div style="background:linear-gradient(135deg,#C8922A,#E6A83A);
                        padding:36px 32px;text-align:center;">
              <div style="font-size:42px;margin-bottom:8px;">🔐</div>
              <h1 style="color:#fff;margin:0;font-size:24px;font-weight:900;">
                Password Reset
              </h1>
              <p style="color:rgba(255,255,255,0.85);margin:6px 0 0;font-size:14px;">
                \(appName) Account
              </p>
            </div>
            <!-- Body -->
            <div style="padding:36px 32px;">
              <p style="color:#1A1208;font-size:16px;line-height:1.6;margin:0 0 20px;">
                Hi \(firstName),<br><br>
                You requested a password reset for your \(appName) account.
                Tap the button below on your iPhone to set a new password.
              </p>
              <!-- CTA Button -->
              <div style="text-align:center;margin:0 0 24px;">
                <a href="\(resetURL)"
                   style="display:inline-block;background:#C8922A;color:#fff;
                          font-size:16px;font-weight:700;text-decoration:none;
                          padding:16px 36px;border-radius:14px;
                          box-shadow:0 4px 16px rgba(200,146,42,0.35);">
                  Reset My Password
                </a>
              </div>
              <!-- Fallback link -->
              <p style="color:#7A6A55;font-size:13px;line-height:1.6;margin:0 0 16px;">
                Or copy and open this link in Safari on your iPhone:
              </p>
              <div style="background:#FAF7F2;border:1px solid #E6DDD0;
                          border-radius:10px;padding:14px;
                          word-break:break-all;font-size:12px;color:#C8922A;">
                \(resetURL)
              </div>
              <p style="color:#7A6A55;font-size:13px;margin:20px 0 0;">
                This link expires in <strong>30 minutes</strong>.
                If you didn't request this, you can safely ignore this email.
              </p>
            </div>
            <!-- Footer -->
            <div style="border-top:1px solid #E6DDD0;padding:20px 32px;text-align:center;">
              <p style="color:#7A6A55;font-size:12px;margin:0;">
                © 2025 \(appName) · Sent with ❤️
              </p>
            </div>
          </div>
        </body>
        </html>
        """
        return await send(to: email, subject: subject, html: html)
    }

    // MARK: - Core send method
    @discardableResult
    private func send(to recipient: String, subject: String, html: String) async -> Bool {
        var request         = URLRequest(url: endpoint)
        request.httpMethod  = "POST"
        request.setValue("Bearer \(apiKey)",  forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "from":    fromAddress,
            "to":      [recipient],
            "subject": subject,
            "html":    html
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            print("EmailService: Failed to serialize email body")
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
