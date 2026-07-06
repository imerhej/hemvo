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

// Per-user: 120 push requests per hour (a busy household member creating
// content legitimately stays well under this; it only stops spam loops).
const USER_RATE_LIMIT_MAX     = 120;
const USER_RATE_LIMIT_MINUTES = 60;

// APNs payloads cap at 4 KB — bound the alert fields well below that.
const MAX_TITLE_LENGTH = 120;
const MAX_BODY_LENGTH  = 500;
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

  // ── Auth check: verify the caller's identity and household membership ────

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Use the caller's JWT to authoritatively resolve their own user ID (this
  // hits the auth server directly, not a table subject to RLS — profiles_select
  // intentionally also exposes household-mates' rows, so a plain `.single()`
  // query with no filter would ambiguously match every member of the caller's
  // household, not just the caller themself).
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const callerClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    anonKey,
    { global: { headers: { Authorization: authHeader } } }
  );

  const { data: { user: callerUser }, error: callerUserErr } = await callerClient.auth.getUser();
  if (callerUserErr || !callerUser) {
    console.error("notify-household: failed to resolve caller identity:", callerUserErr?.message);
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data: callerProfile, error: callerErr } = await callerClient
    .from("profiles")
    .select("id, household_id")
    .eq("id", callerUser.id)
    .single();

  if (callerErr || !callerProfile) {
    console.error("notify-household: failed to resolve caller profile:", callerErr?.message);
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const callerHouseholdId: string | null = callerProfile.household_id;

  // ── Rate limit: per caller, fail open on DB errors ───────────────────────

  const rateLimitClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );
  const { data: allowed, error: rlErr } = await rateLimitClient.rpc("check_and_increment_rate_limit", {
    p_key: callerUser.id,
    p_action: "notify-household",
    p_max_count: USER_RATE_LIMIT_MAX,
    p_window_minutes: USER_RATE_LIMIT_MINUTES,
  });
  if (rlErr) {
    console.warn(`notify-household: rate limit check failed: ${rlErr.message}`);
  } else if (allowed !== true) {
    return new Response(JSON.stringify({ error: "Too many notifications. Please try again later." }), {
      status: 429,
      headers: { "Content-Type": "application/json", "Retry-After": "3600" },
    });
  }

  // ── Parse request body ───────────────────────────────────────────────────

  let household_id: string | undefined,
      user_ids: string[] | undefined,
      exclude_user_ids: string[] | undefined,
      title: string,
      body: string;
  try {
    ({ household_id, user_ids, exclude_user_ids, title, body } = await req.json());
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

  if (typeof title !== "string" || typeof body !== "string" || !title.trim() || !body.trim()) {
    return new Response(JSON.stringify({ error: "title and body are required" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }
  title = title.slice(0, MAX_TITLE_LENGTH);
  body  = body.slice(0, MAX_BODY_LENGTH);

  // ── Membership check ─────────────────────────────────────────────────────

  if (!callerHouseholdId) {
    return new Response(JSON.stringify({ error: "Forbidden: caller has no household" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (household_id && household_id !== callerHouseholdId) {
    console.error(
      `notify-household: caller ${callerProfile.id} in household ${callerHouseholdId} ` +
      `attempted to notify household ${household_id}`
    );
    return new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  // For the user_ids path, verify all targets belong to the caller's household.
  if (user_ids && user_ids.length > 0) {
    // Use service role to read targets (their profiles may have RLS that hides them
    // from the caller client, but we've already validated the caller's household).
    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );
    const { data: targetProfiles, error: targetErr } = await serviceClient
      .from("profiles")
      .select("id")
      .in("id", user_ids)
      .eq("household_id", callerHouseholdId);

    if (targetErr) {
      console.error("notify-household: failed to validate target profiles:", targetErr.message);
      return new Response(JSON.stringify({ error: "Internal error" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (!targetProfiles || targetProfiles.length !== user_ids.length) {
      console.error(
        `notify-household: caller ${callerProfile.id} attempted to notify ` +
        `users outside their household (${callerHouseholdId})`
      );
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }
  }

  // ── Resolve target user IDs ───────────────────────────────────────────────

  // Use the service-role key so RLS doesn't block cross-user reads.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  let targetUserIds: string[];

  // Always derive the creator from the verified JWT — never trust the request body.
  const creator_id = callerProfile.id;

  if (user_ids && user_ids.length > 0) {
    // Targeting specific users (e.g. invitees) — filter out the creator.
    // Normalize case: the iOS client sends uppercase UUID strings while
    // Postgres returns lowercase, so a plain string comparison never matches
    // and the creator would push-notify themself.
    const creatorLower = String(creator_id).toLowerCase();
    targetUserIds = user_ids
      .map((id: string) => id.toLowerCase())
      .filter((id: string) => id !== creatorLower);
    if (targetUserIds.length === 0) {
      return new Response(JSON.stringify({ sent: 0 }), {
        headers: { "Content-Type": "application/json" },
      });
    }
  } else {
    // Broadcast to the whole household: resolve member IDs via profiles table.
    // This is more reliable than filtering device_tokens by household_id because
    // tokens may have been registered before household_id was set on the row.
    let profileQuery = supabase
      .from("profiles")
      .select("id")
      .eq("household_id", household_id!)
      .neq("id", creator_id);

    // Exclude specific users (e.g. invitees who already got a personal push).
    if (exclude_user_ids && exclude_user_ids.length > 0) {
      for (const excludedId of exclude_user_ids) {
        profileQuery = profileQuery.neq("id", excludedId);
      }
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

  // One push per physical device: the same token can appear under several
  // user_ids when accounts share a device, and APNs would deliver each copy.
  const uniqueRows = [
    ...new Map(rows.map((r: { token: string; apns_environment: string }) => [r.token, r])).values(),
  ] as { token: string; apns_environment: string }[];

  // Sign JWT once and reuse for every delivery in this request.
  const jwt = await makeAPNsJWT();
  const results = await Promise.all(
    uniqueRows.map(({ token, apns_environment }: { token: string; apns_environment: string }) =>
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
  console.log(`notify-household: ${succeeded}/${uniqueRows.length} delivered, results: ${JSON.stringify(sanitized)}`);
  // Only return aggregate counts to the caller. Per-token delivery details
  // (token suffix, APNs env, failure reasons) stay in the server log above —
  // there's no reason to expose another household member's device state to the
  // client that triggered the push.
  return new Response(JSON.stringify({ sent: uniqueRows.length, delivered: succeeded }), {
    headers: { "Content-Type": "application/json" },
  });
});
