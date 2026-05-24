// send-password-changed-email — Supabase Edge Function
// Notifies the authenticated user that their password was changed.
// Requires a valid Supabase auth JWT in the Authorization header.
//
// Secrets used (already set):
//   RESEND_API_KEY, FROM_ADDRESS, SUPABASE_URL, SUPABASE_ANON_KEY
//
// Deploy: supabase functions deploy send-password-changed-email

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const FROM_ADDRESS   = Deno.env.get("FROM_ADDRESS") ?? "Hemvo <noreply@hemvo.app>";
const SUPABASE_URL   = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY       = Deno.env.get("SUPABASE_ANON_KEY")!;
const APP_NAME       = "Hemvo";

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

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonError(401, "Unauthorized");

  // Resolve the caller's identity from their JWT — never trust a client-supplied email.
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth:   { autoRefreshToken: false, persistSession: false },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user?.email) return jsonError(401, "Could not identify user");

  const email = user.email;
  const year  = new Date().getFullYear();
  const now   = new Date().toLocaleString("en-US", {
    timeZone:  "UTC",
    dateStyle: "medium",
    timeStyle: "short",
  }) + " UTC";

  const subject = `Your ${APP_NAME} password was changed`;
  const html = `<!DOCTYPE html>
<html>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#FAF7F2;margin:0;padding:0;">
  <div style="max-width:480px;margin:40px auto;background:#fff;border-radius:20px;overflow:hidden;box-shadow:0 4px 24px rgba(26,18,8,0.08);">
    <div style="background:linear-gradient(135deg,#C8922A,#E6A83A);padding:36px 32px;text-align:center;">
      <div style="font-size:42px;margin-bottom:8px;">&#128275;</div>
      <h1 style="color:#fff;margin:0;font-size:24px;font-weight:900;">Password Changed</h1>
      <p style="color:rgba(255,255,255,0.85);margin:6px 0 0;font-size:14px;">Your account password was updated</p>
    </div>
    <div style="padding:36px 32px;">
      <p style="color:#1A1208;font-size:16px;line-height:1.6;margin:0 0 16px;">
        Your ${APP_NAME} password was successfully changed on <strong>${now}</strong>.
      </p>
      <p style="color:#7A6A55;font-size:14px;line-height:1.6;margin:0 0 24px;">
        If you made this change, no action is needed. If you did not change your password, please contact support immediately.
      </p>
      <div style="text-align:center;margin:0 0 8px;">
        <a href="https://hemvo.app/contact.html"
           style="display:inline-block;background:linear-gradient(135deg,#C8922A,#E6A83A);color:#fff;font-size:15px;font-weight:700;text-decoration:none;padding:14px 28px;border-radius:12px;">
          Contact Support
        </a>
      </div>
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
