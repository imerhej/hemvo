// send-password-reset-email — Supabase Edge Function
// Generates a Supabase recovery link via the Admin API and delivers it
// via Resend. No user auth token required — caller is not logged in.
//
// Secrets used (already set):
//   RESEND_API_KEY, FROM_ADDRESS, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Deploy: supabase functions deploy send-password-reset-email

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const FROM_ADDRESS   = Deno.env.get("FROM_ADDRESS") ?? "Hemvo <noreply@hemvo.app>";
const SUPABASE_URL   = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY    = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const REDIRECT_TO    = "hemvo://reset-password";
const APP_NAME       = "Hemvo";

// Max 5 reset emails per email address per hour.
const RATE_LIMIT_MAX     = 5;
const RATE_LIMIT_MINUTES = 60;

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

async function isAllowed(admin: ReturnType<typeof createClient>, key: string, action: string): Promise<boolean> {
  const { data, error } = await admin.rpc("check_and_increment_rate_limit", {
    p_key: key,
    p_action: action,
    p_max_count: RATE_LIMIT_MAX,
    p_window_minutes: RATE_LIMIT_MINUTES,
  });
  if (error) {
    console.warn(`rate limit check failed: ${error.message}`);
    return true; // fail open — don't block legitimate requests on DB errors
  }
  return data === true;
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

  if (!await isAllowed(admin, email.toLowerCase(), "password-reset")) {
    // Return the same shape as success to avoid leaking whether the email exists.
    return new Response(JSON.stringify({ sent: true }), {
      status: 429,
      headers: { "Content-Type": "application/json", "Retry-After": "3600" },
    });
  }

  // Generate the recovery link server-side using the service role.
  // On error (e.g. email not found) we still return { sent: true } to
  // prevent user enumeration — the caller never learns if the email exists.
  const { data, error: genError } = await admin.auth.admin.generateLink({
    type: "recovery",
    email,
    options: { redirectTo: REDIRECT_TO },
  });

  if (genError || !data?.properties?.action_link) {
    console.warn(`Recovery link not generated for *@${email.split("@")[1] ?? "?"}: ${genError?.message ?? "no link"}`);
    return new Response(JSON.stringify({ sent: true }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const resetLink = data.properties.action_link;
  const safeEmail = htmlEscape(email);
  const year      = new Date().getFullYear();

  const subject = `Reset your ${APP_NAME} password`;
  const html = `<!DOCTYPE html>
<html>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#FAF7F2;margin:0;padding:0;">
  <div style="max-width:480px;margin:40px auto;background:#fff;border-radius:20px;overflow:hidden;box-shadow:0 4px 24px rgba(26,18,8,0.08);">
    <div style="background:linear-gradient(135deg,#C8922A,#E6A83A);padding:36px 32px;text-align:center;">
      <div style="font-size:42px;margin-bottom:8px;">&#128274;</div>
      <h1 style="color:#fff;margin:0;font-size:24px;font-weight:900;">Reset Your Password</h1>
      <p style="color:rgba(255,255,255,0.85);margin:6px 0 0;font-size:14px;">A reset was requested for your account</p>
    </div>
    <div style="padding:36px 32px;">
      <p style="color:#1A1208;font-size:16px;line-height:1.6;margin:0 0 24px;">
        Tap the button below <strong>on your iPhone</strong> to set a new password for <strong>${safeEmail}</strong>.
      </p>
      <div style="text-align:center;margin:0 0 24px;">
        <a href="${resetLink}"
           style="display:inline-block;background:linear-gradient(135deg,#C8922A,#E6A83A);color:#fff;font-size:16px;font-weight:700;text-decoration:none;padding:16px 32px;border-radius:12px;">
          Reset Password
        </a>
      </div>
      <p style="color:#7A6A55;font-size:13px;margin:0;">
        This link expires in <strong>1 hour</strong>. If you did not request a password reset, you can safely ignore this email.
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

  if (!res.ok) {
    const errBody = await res.text();
    console.error(`Resend ${res.status}: ${errBody}`);
  }

  return new Response(JSON.stringify({ sent: true }), {
    headers: { "Content-Type": "application/json" },
  });
});
