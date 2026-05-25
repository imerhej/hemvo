// create-account — Supabase Edge Function
// Creates a new user via the admin API (bypasses GoTrue's SMTP path entirely —
// the client signUp() call causes GoTrue to delete the user if its own SMTP
// delivery fails, which breaks the flow). After creation, generates a magic
// link and delivers it via Resend so the user can confirm their email.
//
// Secrets: RESEND_API_KEY, FROM_ADDRESS, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Deploy: supabase functions deploy create-account --no-verify-jwt

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

  let email: string, password: string, fullName: string, username: string;
  try {
    ({ email, password, full_name: fullName, username } = await req.json());
  } catch {
    return jsonError(400, "Invalid JSON");
  }
  if (!email || !password) return jsonError(400, "Missing email or password");

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Create the user via admin API — does NOT call Supabase's SMTP,
  // so the user row is never rolled back due to email delivery failure.
  // email_confirm: false leaves the user unconfirmed until they tap the link.
  const { data: userData, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: false,
    user_metadata: {
      full_name: fullName ?? "",
      username:  (username ?? "").toLowerCase().trim(),
    },
  });

  if (createError) {
    // If the email is already registered, check whether they're still unconfirmed
    // (e.g. from a previous failed signup attempt). If so, just resend the link.
    const msg = createError.message.toLowerCase();
    const alreadyExists = msg.includes("already registered") || msg.includes("already been registered")
      || msg.includes("already exists") || msg.includes("duplicate");

    if (alreadyExists) {
      const { data: existing } = await admin.auth.admin.getUserByEmail(email);
      if (existing?.user && !existing.user.email_confirmed_at) {
        // Unconfirmed — fall through and resend the confirmation link below.
        console.log(`create-account: resending confirmation for unconfirmed user ${email}`);
      } else {
        // Confirmed — this is a genuine "already registered" error.
        return jsonError(409, "An account with this email already exists. Please sign in instead.");
      }
    } else {
      console.error(`create-account: createUser error: ${createError.message}`);
      return jsonError(400, createError.message);
    }
  }

  // Generate a magic link — works for unconfirmed users and confirms them on tap.
  const { data: linkData, error: linkError } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
    options: { redirectTo: REDIRECT_TO },
  });

  if (linkError || !linkData?.properties?.action_link) {
    console.error(`create-account: generateLink error: ${linkError?.message ?? "no link"}`);
    // Account was created — return success even if we couldn't send the email.
    // The user can sign in with email+password once confirmed via another path.
    return new Response(JSON.stringify({ created: true, emailSent: false }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const rawLink     = linkData.properties.action_link;
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
    return new Response(JSON.stringify({ created: true, emailSent: true }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const errBody = await res.text();
  console.error(`Resend ${res.status}: ${errBody}`);
  // Account exists — don't fail the whole signup over email delivery.
  return new Response(JSON.stringify({ created: true, emailSent: false }), {
    headers: { "Content-Type": "application/json" },
  });
});
