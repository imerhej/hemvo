// notify-household — Supabase Edge Function
// Sends an APNs push notification to every household member except the creator.
//
// Required Supabase secrets (set via dashboard or CLI):
//   APNS_KEY_ID      — 10-char key ID  (Apple Developer → Keys)
//   APNS_TEAM_ID     — 10-char Team ID (Apple Developer → Membership)
//   APNS_PRIVATE_KEY — full .p8 file contents including header/footer lines
//
// Deploy:  supabase functions deploy notify-household
// Logs:    supabase functions logs notify-household

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const APNS_KEY_ID   = Deno.env.get("APNS_KEY_ID")!;
const APNS_TEAM_ID  = Deno.env.get("APNS_TEAM_ID")!;
const APNS_PRIV_KEY = Deno.env.get("APNS_PRIVATE_KEY")!;
const BUNDLE_ID          = "com.issamnmerhej.Hemvo";
const APNS_HOST_PROD     = "https://api.push.apple.com";
const APNS_HOST_SANDBOX  = "https://api.sandbox.push.apple.com";

// ── JWT helpers ──────────────────────────────────────────────────────────────

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
  const buf = new ArrayBuffer(binary.length);
  const view = new Uint8Array(buf);
  for (let i = 0; i < binary.length; i++) view[i] = binary.charCodeAt(i);
  return buf;
}

// Generates a signed APNs JWT valid for ~1 hour.
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

// ── APNs delivery ────────────────────────────────────────────────────────────

async function sendAPNs(
  token: string,
  title: string,
  body: string,
  jwt: string,
  host: string = APNS_HOST_PROD
): Promise<{ ok: boolean; status: number; reason: string }> {
  const res = await fetch(`${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization:    `bearer ${jwt}`,
      "apns-topic":     BUNDLE_ID,
      "apns-push-type": "alert",
      "apns-priority":  "10",
      "content-type":   "application/json",
    },
    body: JSON.stringify({
      aps: { alert: { title, body }, sound: "default" },
    }),
  });

  const text = await res.text();
  if (!res.ok) {
    console.error(`APNs ${res.status} for token …${token.slice(-8)}: ${text}`);
  }
  return { ok: res.ok, status: res.status, reason: res.ok ? "ok" : text };
}

// ── Handler ──────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  let household_id: string | undefined,
      user_ids: string[] | undefined,
      exclude_user_ids: string[] | undefined,
      creator_id: string | undefined,
      title: string,
      body: string;
  try {
    ({ household_id, user_ids, exclude_user_ids, creator_id, title, body } = await req.json());
  } catch {
    return new Response(JSON.stringify({ error: "invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!household_id && (!user_ids || user_ids.length === 0)) {
    return new Response(JSON.stringify({ error: "household_id or user_ids required" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Use the service-role key so RLS doesn't block cross-user reads.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  let targetUserIds: string[];

  if (user_ids && user_ids.length > 0) {
    // Targeting specific users (e.g. invitees) — filter out the creator.
    targetUserIds = creator_id
      ? user_ids.filter(id => id !== creator_id)
      : user_ids;
  } else {
    // Broadcast to the whole household: resolve member IDs via profiles table.
    // This is more reliable than filtering device_tokens by household_id because
    // tokens may have been registered before household_id was set on the row.
    let profileQuery = supabase
      .from("profiles")
      .select("id")
      .eq("household_id", household_id!);

    if (creator_id) {
      profileQuery = profileQuery.neq("id", creator_id);
    }

    // Exclude specific users (e.g. invitees who already got a personal push).
    if (exclude_user_ids && exclude_user_ids.length > 0) {
      profileQuery = profileQuery.not("id", "in", `(${exclude_user_ids.join(",")})`);
    }

    const { data: members, error: profileErr } = await profileQuery;
    if (profileErr) {
      console.error("Failed to fetch household members:", profileErr.message);
      return new Response(JSON.stringify({ error: profileErr.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (!members || members.length === 0) {
      console.log(`notify-household: no other members in household ${household_id}`);
      return new Response(JSON.stringify({ sent: 0 }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    targetUserIds = members.map((m: { id: string }) => m.id);
  }

  // Fetch device tokens for the resolved user IDs.
  const { data: rows, error: tokenErr } = await supabase
    .from("device_tokens")
    .select("token, apns_environment")
    .in("user_id", targetUserIds);

  if (tokenErr) {
    console.error("Failed to fetch tokens:", tokenErr.message);
    return new Response(JSON.stringify({ error: tokenErr.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!rows || rows.length === 0) {
    console.log(`notify-household: no device tokens for users [${targetUserIds.join(",")}]`);
    return new Response(JSON.stringify({ sent: 0 }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  // Sign JWT once and reuse for every delivery in this request.
  const jwt = await makeAPNsJWT();
  const results = await Promise.all(
    rows.map(({ token, apns_environment }: { token: string; apns_environment: string }) =>
      sendAPNs(token, title, body, jwt,
        apns_environment === "sandbox" ? APNS_HOST_SANDBOX : APNS_HOST_PROD).then(r => ({
          token,
          tokenSuffix: `…${token.slice(-8)}`,
          env: apns_environment,
          ...r,
        }))
    )
  );

  // Only delete on 400 BadDeviceToken — the token is genuinely dead.
  // 403 BadEnvironmentKeyInToken means a key or env-tag misconfiguration, not a dead token.
  const staleTokens = results
    .filter(r => r.status === 400 && r.reason?.includes("BadDeviceToken"))
    .map(r => r.token);
  if (staleTokens.length > 0) {
    await supabase.from("device_tokens").delete().in("token", staleTokens);
    console.log(`notify-household: removed ${staleTokens.length} stale token(s)`);
  }

  const succeeded = results.filter(r => r.ok).length;
  const sanitized = results.map(({ token: _t, ...rest }) => rest);
  console.log(`notify-household: ${succeeded}/${rows.length} delivered, results: ${JSON.stringify(sanitized)}`);
  return new Response(JSON.stringify({ sent: rows.length, delivered: succeeded, results: sanitized }), {
    headers: { "Content-Type": "application/json" },
  });
});
