// process-scheduled-push — Supabase Edge Function
//
// Polls `notification_schedule` for rows where fire_at <= now() and sends
// an APNs push to every household member. Designed to run every minute via
// Supabase's built-in cron scheduler.
//
// Schedule via Supabase Dashboard:
//   Edge Functions → process-scheduled-push → Schedule → "* * * * *"
//   OR via management API:
//     curl -X POST https://api.supabase.com/v1/projects/<ref>/functions/process-scheduled-push/schedules \
//       -H "Authorization: Bearer <access-token>" \
//       -d '{"schedule":"* * * * *"}'
//
// Required secrets (shared with notify-household):
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const APNS_KEY_ID   = Deno.env.get("APNS_KEY_ID")!;
const APNS_TEAM_ID  = Deno.env.get("APNS_TEAM_ID")!;
const APNS_PRIV_KEY = Deno.env.get("APNS_PRIVATE_KEY")!;
const BUNDLE_ID     = "com.issammerhej.Hemvo";
const APNS_HOST     = "https://api.push.apple.com";

// ── APNs helpers (same as notify-household) ──────────────────────────────────

function base64url(input: ArrayBuffer | string): string {
  const bytes =
    typeof input === "string"
      ? new TextEncoder().encode(input)
      : new Uint8Array(input);
  const b64 = btoa(String.fromCharCode(...bytes));
  return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function pemToBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binary = atob(b64);
  const buf    = new ArrayBuffer(binary.length);
  const view   = new Uint8Array(buf);
  for (let i = 0; i < binary.length; i++) view[i] = binary.charCodeAt(i);
  return buf;
}

async function makeAPNsJWT(): Promise<string> {
  const header  = { alg: "ES256", kid: APNS_KEY_ID };
  const payload = { iss: APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) };
  const input   = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBuffer(APNS_PRIV_KEY),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(input)
  );
  return `${input}.${base64url(sig)}`;
}

async function sendAPNs(token: string, title: string, body: string, jwt: string): Promise<void> {
  const res = await fetch(`${APNS_HOST}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization:    `bearer ${jwt}`,
      "apns-topic":     BUNDLE_ID,
      "apns-push-type": "alert",
      "apns-priority":  "10",
      "content-type":   "application/json",
    },
    body: JSON.stringify({ aps: { alert: { title, body }, sound: "default" } }),
  });
  if (!res.ok) {
    const err = await res.text();
    console.error(`APNs ${res.status} for token …${token.slice(-8)}: ${err}`);
  }
}

// ── Handler ──────────────────────────────────────────────────────────────────

serve(async (_req: Request) => {
  // Use service-role key — bypasses RLS for cross-user queries.
  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // Fetch up to 100 unsent notifications that are due.
  const { data: pending, error: fetchErr } = await sb
    .from("notification_schedule")
    .select("id, household_id, title, body")
    .eq("sent", false)
    .lte("fire_at", new Date().toISOString())
    .limit(100);

  if (fetchErr) {
    console.error("Failed to fetch notification_schedule:", fetchErr.message);
    return new Response(JSON.stringify({ error: fetchErr.message }), { status: 500 });
  }

  if (!pending || pending.length === 0) {
    return new Response(JSON.stringify({ processed: 0 }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  // Sign the APNs JWT once and reuse for all pushes in this batch.
  const jwt = await makeAPNsJWT();
  let processed = 0;

  for (const item of pending) {
    // Fetch device tokens for this household.
    const { data: tokenRows } = await sb
      .from("device_tokens")
      .select("token")
      .eq("household_id", item.household_id);

    if (tokenRows && tokenRows.length > 0) {
      await Promise.all(
        tokenRows.map(({ token }: { token: string }) =>
          sendAPNs(token, item.title, item.body, jwt)
        )
      );
    }

    // Mark as sent regardless — prevents re-delivery if APNs tokens are stale.
    await sb
      .from("notification_schedule")
      .update({ sent: true })
      .eq("id", item.id);

    processed++;
  }

  console.log(`process-scheduled-push: sent ${processed} notification(s)`);
  return new Response(JSON.stringify({ processed }), {
    headers: { "Content-Type": "application/json" },
  });
});
