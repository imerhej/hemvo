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
const BUNDLE_ID     = "com.issammerhej.Hemvo";
// Use api.sandbox.push.apple.com during development / TestFlight
const APNS_HOST     = "https://api.push.apple.com";

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
  jwt: string
): Promise<void> {
  const res = await fetch(`${APNS_HOST}/3/device/${token}`, {
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

  if (!res.ok) {
    const err = await res.text();
    console.error(`APNs ${res.status} for token …${token.slice(-8)}: ${err}`);
  }
}

// ── Handler ──────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  let household_id: string | undefined,
      user_ids: string[] | undefined,
      exclude_user_ids: string[] | undefined,
      creator_id: string,
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

  let query = supabase
    .from("device_tokens")
    .select("token")
    .neq("user_id", creator_id);

  // Target specific users (invitees) or fall back to the whole household.
  if (user_ids && user_ids.length > 0) {
    query = query.in("user_id", user_ids);
  } else {
    query = query.eq("household_id", household_id!);
    // Optionally exclude specific users (e.g. invitees who already got a personal push).
    if (exclude_user_ids && exclude_user_ids.length > 0) {
      query = query.not("user_id", "in", `(${exclude_user_ids.join(",")})`);
    }
  }

  const { data: rows, error } = await query;

  if (error) {
    console.error("Failed to fetch tokens:", error.message);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!rows || rows.length === 0) {
    return new Response(JSON.stringify({ sent: 0 }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  // Sign JWT once and reuse for every delivery in this request.
  const jwt = await makeAPNsJWT();
  await Promise.all(
    rows.map(({ token }: { token: string }) => sendAPNs(token, title, body, jwt))
  );

  return new Response(JSON.stringify({ sent: rows.length }), {
    headers: { "Content-Type": "application/json" },
  });
});
