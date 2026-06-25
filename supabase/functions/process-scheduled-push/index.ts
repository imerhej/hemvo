// process-scheduled-push — Supabase Edge Function
//
// Polls `notification_schedule` for rows where fire_at <= now() and sends
// an APNs push to every household member except the event creator. Designed
// to run every minute via Supabase's built-in cron scheduler.
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

const APNS_KEY_ID       = Deno.env.get("APNS_KEY_ID")!;
const APNS_TEAM_ID      = Deno.env.get("APNS_TEAM_ID")!;
const APNS_PRIV_KEY     = Deno.env.get("APNS_PRIVATE_KEY")!;
const BUNDLE_ID         = "com.issamnmerhej.Hemvo";
const APNS_HOST_PROD    = "https://api.push.apple.com";
const APNS_HOST_SANDBOX = "https://api.sandbox.push.apple.com";

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

async function sendAPNs(
  token: string,
  title: string,
  body: string,
  jwt: string,
  host: string
): Promise<void> {
  const res = await fetch(`${host}/3/device/${token}`, {
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

const CRON_SECRET = Deno.env.get("CRON_SECRET");

serve(async (req: Request) => {
  // Reject requests that don't carry the shared cron secret.
  // Set it once: supabase secrets set CRON_SECRET=<random-string>
  // The pg_cron job must include X-Cron-Secret: <same-value> in its headers
  // (see migration 20260625140000_add_cron_secret_to_scheduled_push.sql).
  if (!CRON_SECRET || req.headers.get("X-Cron-Secret") !== CRON_SECRET) {
    return new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 });
  }

  // Use service-role key — bypasses RLS for cross-user queries.
  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // Fetch up to 100 unsent notifications that are due.
  const { data: pending, error: fetchErr } = await sb
    .from("notification_schedule")
    .select("id, household_id, creator_id, title, body")
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
    // Resolve household member IDs via profiles — more reliable than filtering
    // device_tokens by household_id (tokens may have been registered before
    // household_id was set on the row, leaving it NULL).
    let profileQuery = sb
      .from("profiles")
      .select("id")
      .eq("household_id", item.household_id);

    if (item.creator_id) {
      profileQuery = profileQuery.neq("id", item.creator_id);
    }

    const { data: members } = await profileQuery;
    const memberIds = (members || []).map((m: { id: string }) => m.id);

    let tokenRows: { token: string; apns_environment: string }[] | null = null;
    if (memberIds.length > 0) {
      const { data } = await sb
        .from("device_tokens")
        .select("token, apns_environment")
        .in("user_id", memberIds);
      tokenRows = data;
    }

    if (tokenRows && tokenRows.length > 0) {
      const deliveryResults = await Promise.all(
        tokenRows.map(async ({ token, apns_environment }: { token: string; apns_environment: string }) => {
          const res = await fetch(`${apns_environment === "sandbox" ? APNS_HOST_SANDBOX : APNS_HOST_PROD}/3/device/${token}`, {
            method: "POST",
            headers: {
              authorization:    `bearer ${jwt}`,
              "apns-topic":     BUNDLE_ID,
              "apns-push-type": "alert",
              "apns-priority":  "10",
              "content-type":   "application/json",
            },
            body: JSON.stringify({ aps: { alert: { title: item.title, body: item.body }, sound: "default" } }),
          });
          const reason = res.ok ? "ok" : await res.text();
          if (!res.ok) console.error(`APNs ${res.status} for token …${token.slice(-8)}: ${reason}`);
          return { token, ok: res.ok, status: res.status, reason };
        })
      );

      const staleTokens = deliveryResults
        .filter(r => r.status === 400 && r.reason?.includes("BadDeviceToken"))
        .map(r => r.token);
      if (staleTokens.length > 0) {
        await sb.from("device_tokens").delete().in("token", staleTokens);
        console.log(`process-scheduled-push: removed ${staleTokens.length} stale token(s)`);
      }
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
