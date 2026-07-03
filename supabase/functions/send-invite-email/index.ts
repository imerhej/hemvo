// send-invite-email — Supabase Edge Function
// Sends household invite emails via the Resend API.
// The Resend API key lives here, server-side — it NEVER reaches the iOS client.
//
// Required Supabase secrets (set once via CLI or dashboard):
//   supabase secrets set RESEND_API_KEY=re_xxxx
//   supabase secrets set FROM_ADDRESS="Hemvo <noreply@hemvo.app>"
//
// Deploy: supabase functions deploy send-invite-email
// Logs:   supabase functions logs send-invite-email

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const FROM_ADDRESS   = Deno.env.get("FROM_ADDRESS") ?? "Hemvo <noreply@hemvo.app>";
const SUPABASE_URL   = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY    = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APP_NAME       = "Hemvo";

// Max 20 invite emails per user per hour.
const RATE_LIMIT_MAX     = 20;
const RATE_LIMIT_MINUTES = 60;

const corsHeaders = {
  "Access-Control-Allow-Origin":  "https://hemvo.app",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

async function isAllowed(admin: ReturnType<typeof createClient>, key: string, action: string): Promise<boolean> {
  const { data, error } = await admin.rpc("check_and_increment_rate_limit", {
    p_key: key,
    p_action: action,
    p_max_count: RATE_LIMIT_MAX,
    p_window_minutes: RATE_LIMIT_MINUTES,
  });
  if (error) {
    console.warn(`rate limit check failed: ${error.message}`);
    return true;
  }
  return data === true;
}

function htmlEscape(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#x27;");
}

serve(async (req: Request) => {
  // Handle CORS preflight.
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  // Cryptographically verify the caller's JWT — not just presence, but validity.
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
  const token = authHeader.replace("Bearer ", "");
  const admin  = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  // Validate the JWT server-side — same pattern as delete-member.
  const { data: { user }, error: authError } = await admin.auth.getUser(token);
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  if (!await isAllowed(admin, user.id, "send-invite")) {
    return new Response(JSON.stringify({ error: "Too many invite emails. Please try again later." }), {
      status: 429,
      headers: { "Content-Type": "application/json", "Retry-After": "3600", ...corsHeaders },
    });
  }

  let code: string;
  try {
    ({ code } = await req.json());
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  if (!code) {
    return new Response(JSON.stringify({ error: "Missing required field: code" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  // Look up the invite server-side instead of trusting client-supplied
  // to/inviterName/householdName — without this, any authenticated caller could
  // send Hemvo-branded emails with arbitrary text to arbitrary addresses using
  // the app's Resend sending domain (found in security audit, 2026-07-03).
  const { data: invite, error: inviteError } = await admin
    .from("household_invites")
    .select("invitee_email, inviter_name, household_name, created_by, expires_at, accepted_at")
    .ilike("code", code.trim())
    .maybeSingle();

  if (inviteError || !invite) {
    return new Response(JSON.stringify({ error: "Invalid invite code" }), {
      status: 404,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
  if (invite.created_by !== user.id) {
    return new Response(JSON.stringify({ error: "Not your invite" }), {
      status: 403,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
  if (invite.accepted_at) {
    return new Response(JSON.stringify({ error: "Invite already accepted" }), {
      status: 409,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
  if (new Date(invite.expires_at) < new Date()) {
    return new Response(JSON.stringify({ error: "Invite expired" }), {
      status: 410,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const to = invite.invitee_email;

  // Sanitize all user-supplied values before embedding in HTML.
  const safeInviter   = htmlEscape(invite.inviter_name);
  const safeHousehold = htmlEscape(invite.household_name);
  const safeCode      = htmlEscape(code.toUpperCase());
  const year          = new Date().getFullYear();

  const subject = `${safeInviter} invited you to join ${safeHousehold} on ${APP_NAME}`;
  const html = `<!DOCTYPE html>
<html>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#FAF7F2;margin:0;padding:0;">
  <div style="max-width:480px;margin:40px auto;background:#fff;border-radius:20px;overflow:hidden;box-shadow:0 4px 24px rgba(26,18,8,0.08);">
    <div style="background:linear-gradient(135deg,#C8922A,#E6A83A);padding:36px 32px;text-align:center;">
      <div style="font-size:42px;margin-bottom:8px;">&#127968;</div>
      <h1 style="color:#fff;margin:0;font-size:24px;font-weight:900;">You're Invited!</h1>
      <p style="color:rgba(255,255,255,0.85);margin:6px 0 0;font-size:14px;">${safeInviter} wants you in ${safeHousehold}</p>
    </div>
    <div style="padding:36px 32px;">
      <p style="color:#1A1208;font-size:16px;line-height:1.6;margin:0 0 24px;">
        Hi there! <strong>${safeInviter}</strong> has invited you to join <strong>${safeHousehold}</strong> on ${APP_NAME} — share meals, budgets, and schedules with your household.
      </p>
      <p style="color:#1A1208;font-size:14px;font-weight:700;margin:0 0 12px;">Your invite code:</p>
      <div style="background:#FAF7F2;border:2px solid #C8922A;border-radius:14px;padding:20px;text-align:center;margin:0 0 24px;">
        <span style="font-size:28px;font-weight:900;letter-spacing:4px;font-family:monospace;color:#C8922A;">${safeCode}</span>
      </div>
      <p style="color:#1A1208;font-size:14px;font-weight:700;margin:0 0 12px;">How to join:</p>
      <ol style="color:#7A6A55;font-size:14px;line-height:1.8;margin:0 0 24px;padding-left:20px;">
        <li>Download ${APP_NAME} from the App Store</li>
        <li>Create your account (or sign in)</li>
        <li>Go to Settings &#8594; Join a Household</li>
        <li>Enter the invite code above</li>
      </ol>
      <p style="color:#7A6A55;font-size:13px;margin:0;">This invite expires in <strong>7 days</strong>.</p>
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
    body: JSON.stringify({ from: FROM_ADDRESS, to: [to], subject, html }),
  });

  if (res.ok) {
    return new Response(JSON.stringify({ sent: true }), {
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const errBody = await res.text();
  console.error(`Resend ${res.status}: ${errBody}`);
  return new Response(JSON.stringify({ error: "Email delivery failed", resendStatus: res.status }), {
    status: 502,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
});
