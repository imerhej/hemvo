// send-confirmation-email — Supabase Edge Function
// Generates a Supabase signup confirmation link via the Admin API and delivers
// it via Resend. Called right after auth.signUp() so confirmation emails use
// Resend instead of Supabase's rate-limited default SMTP.
//
// Secrets used (already set):
//   RESEND_API_KEY, FROM_ADDRESS, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Deploy: supabase functions deploy send-confirmation-email

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const FROM_ADDRESS   = Deno.env.get("FROM_ADDRESS") ?? "Hemvo <noreply@hemvo.app>";
const SUPABASE_URL   = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY    = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const REDIRECT_TO    = "hemvo://";
const APP_NAME       = "Hemvo";

function htmlEscape(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#x27;");
}

function jsonError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  let email: string;
  try {
    ({ email } = await req.json());
  } catch {
    return jsonError(400, "Invalid JSON");
  }
  if (!email) return jsonError(400, "Missing email");

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Guard: only generate a link for an account that already exists.
  // generateLink({ type: "magiclink" }) creates a bare user as a side-effect if
  // the email is not in auth.users — this check prevents that from happening when
  // the app calls this function after a failed signUp.
  const { data: existingUser } = await admin.auth.admin.getUserByEmail(email);
  if (!existingUser?.user) {
    // Return success silently — leaking 404 would confirm that an email is
    // not registered, enabling account enumeration via this endpoint.
    console.log(`send-confirmation-email: no account found for [redacted], returning silent 200`);
    return new Response(JSON.stringify({ sent: false }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  // Rate limit: at most one confirmation email per 60 seconds per address.
  // Uses the confirmation_sent_at timestamp already maintained by Supabase Auth —
  // no extra table required.
  const lastSent = existingUser.user.confirmation_sent_at;
  if (lastSent) {
    const secondsAgo = (Date.now() - new Date(lastSent).getTime()) / 1000;
    if (secondsAgo < 60) {
      return jsonError(429, "Too many requests — please wait before requesting another confirmation email");
    }
  }

  // Use magiclink instead of signup — magiclink requires no password, works for
  // unconfirmed users, and logs the user in on click (confirming their email
  // in the same step).
  const { data, error: genError } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
    options: { redirectTo: REDIRECT_TO },
  });

  if (genError || !data?.properties?.action_link) {
    console.error(
      `Confirmation link not generated: ${genError?.message ?? "no link"}`
    );
    return jsonError(502, "Could not generate confirmation link");
  }

  const rawLink     = data.properties.action_link;
  const rawUrl      = new URL(rawLink);
  const token       = rawUrl.searchParams.get("token") ?? "";
  const type        = rawUrl.searchParams.get("type") ?? "magiclink";
  const confirmLink = `https://hemvo.app/verify-email.html?token=${encodeURIComponent(token)}&type=${encodeURIComponent(type)}&email=${encodeURIComponent(email)}`;
  const safeEmail   = htmlEscape(email);
  const year        = new Date().getFullYear();

  const subject = `Confirm your ${APP_NAME} account`;
  const html = `<!DOCTYPE html>
<html>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#FAF7F2;margin:0;padding:0;">
  <div style="max-width:480px;margin:40px auto;background:#fff;border-radius:20px;overflow:hidden;box-shadow:0 4px 24px rgba(26,18,8,0.08);">
    <div style="background:linear-gradient(135deg,#1B5E34,#4CAF74);padding:36px 32px;text-align:center;">
      <div style="font-size:42px;margin-bottom:8px;">&#127968;</div>
      <h1 style="color:#fff;margin:0;font-size:24px;font-weight:900;">Welcome to ${APP_NAME}!</h1>
      <p style="color:rgba(255,255,255,0.85);margin:6px 0 0;font-size:14px;">One tap to confirm your email</p>
    </div>
    <div style="padding:36px 32px;">
      <p style="color:#1A1208;font-size:16px;line-height:1.6;margin:0 0 24px;">
        Thanks for signing up! Tap the button below <strong>on your iPhone</strong> to confirm
        <strong>${safeEmail}</strong> and activate your account.
      </p>
      <div style="text-align:center;margin:0 0 24px;">
        <a href="${confirmLink}"
           style="display:inline-block;background:linear-gradient(135deg,#1B5E34,#4CAF74);color:#fff;font-size:16px;font-weight:700;text-decoration:none;padding:16px 32px;border-radius:12px;">
          Confirm Email
        </a>
      </div>
      <p style="color:#7A6A55;font-size:13px;margin:0;">
        If you did not create a ${APP_NAME} account, you can safely ignore this email.
      </p>
    </div>
    <div style="border-top:1px solid #E6DDD0;padding:20px 32px;text-align:center;">
      <p style="color:#7A6A55;font-size:12px;margin:0;">&#169; ${year} ${APP_NAME}</p>
    </div>
  </div>
</body>
</html>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization:  `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from: FROM_ADDRESS, to: [email], subject, html }),
  });

  if (res.ok) {
    return new Response(JSON.stringify({ sent: true }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const errBody = await res.text();
  console.error(`Resend ${res.status}: ${errBody}`);
  return new Response(
    JSON.stringify({ error: "Email delivery failed", resendStatus: res.status, resendError: errBody }),
    { status: 502, headers: { "Content-Type": "application/json" } }
  );
});
