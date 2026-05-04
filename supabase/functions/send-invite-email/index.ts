// send-invite-email — Supabase Edge Function
// Sends household invite emails via the Resend API.
// The Resend API key lives here, server-side — it NEVER reaches the iOS client.
//
// Required Supabase secrets (set once via CLI or dashboard):
//   supabase secrets set RESEND_API_KEY=re_xxxx
//   supabase secrets set FROM_ADDRESS="Hemvo <noreply@yourdomain.com>"
//
// Deploy: supabase functions deploy send-invite-email
// Logs:   supabase functions logs send-invite-email

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const FROM_ADDRESS   = Deno.env.get("FROM_ADDRESS") ?? "Hemvo <onboarding@resend.dev>";
const APP_NAME       = "Hemvo";

function htmlEscape(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#x27;");
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  // Require a valid Supabase auth JWT — only authenticated users can send invites.
  if (!req.headers.get("Authorization")) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let to: string, inviterName: string, householdName: string, token: string;
  try {
    ({ to, inviterName, householdName, token } = await req.json());
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!to || !inviterName || !householdName || !token) {
    return new Response(JSON.stringify({ error: "Missing required fields: to, inviterName, householdName, token" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Sanitize all user-supplied values before embedding in HTML.
  const safeInviter   = htmlEscape(inviterName);
  const safeHousehold = htmlEscape(householdName);
  const safeToken     = htmlEscape(token);
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
      <p style="color:#1A1208;font-size:14px;font-weight:700;margin:0 0 8px;">Your invite token:</p>
      <div style="background:#FAF7F2;border:2px solid #E6DDD0;border-radius:12px;padding:16px;word-break:break-all;font-size:12px;font-family:monospace;color:#C8922A;margin:0 0 24px;">${safeToken}</div>
      <p style="color:#1A1208;font-size:14px;font-weight:700;margin:0 0 12px;">How to join:</p>
      <ol style="color:#7A6A55;font-size:14px;line-height:1.8;margin:0 0 24px;padding-left:20px;">
        <li>Download ${APP_NAME} from the App Store</li>
        <li>Create your account (or sign in)</li>
        <li>Go to Settings &#8594; Join a Household</li>
        <li>Paste the token above</li>
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
      headers: { "Content-Type": "application/json" },
    });
  }

  const errBody = await res.text();
  console.error(`Resend ${res.status}: ${errBody}`);
  return new Response(JSON.stringify({ error: "Email delivery failed" }), {
    status: 502,
    headers: { "Content-Type": "application/json" },
  });
});
