// verify-subscription — Supabase Edge Function
//
// Replaces the removed client-callable update_subscription_status('active') path
// (security audit, 2026-07-03: any authenticated user could self-report 'active'
// with no purchase check, letting household members grant themselves permanent
// free access). This function is the ONLY path that may set subscription_status
// to 'active': it takes a StoreKit transaction id from the caller's own device,
// asks Apple's App Store Server API to confirm the transaction is real, unrevoked,
// unexpired, for this app's bundle id, and for one of our known product ids — then
// writes the result using the service-role client, which the profiles guard
// trigger only allows for service_role callers.
//
// The Apple-issued transaction id is also bound to exactly one profile via a
// unique index (see migration 20260703140000) so a leaked/shared transaction id
// can't be replayed to activate a second, unrelated account.
//
// Secrets required (supabase secrets set ...):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//   APPSTORE_ISSUER_ID       — App Store Connect > Users and Access > Integrations > In-App Purchase key
//   APPSTORE_KEY_ID          — the key id shown next to the key above
//   APPSTORE_PRIVATE_KEY     — contents of the downloaded .p8 file, PEM format, newlines preserved
//   APPSTORE_BUNDLE_ID       — com.issamnmerhej.Hemvo
//
// Deploy: supabase functions deploy verify-subscription

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APPSTORE_ISSUER_ID = Deno.env.get("APPSTORE_ISSUER_ID")!;
const APPSTORE_KEY_ID = Deno.env.get("APPSTORE_KEY_ID")!;
const APPSTORE_PRIVATE_KEY = Deno.env.get("APPSTORE_PRIVATE_KEY")!;
const APPSTORE_BUNDLE_ID = Deno.env.get("APPSTORE_BUNDLE_ID") ?? "com.issamnmerhej.Hemvo";

const KNOWN_PRODUCT_IDS = new Set([
  "com.hemvo.app.sub.monthly",
  "com.hemvo.app.sub.annual",
]);

const PRODUCTION_HOST = "https://api.storekit.itunes.apple.com";
const SANDBOX_HOST = "https://api.storekit-sandbox.itunes.apple.com";

function jsonError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let str = "";
  for (const b of arr) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlDecodeToJSON(segment: string): any {
  const padded = segment.replace(/-/g, "+").replace(/_/g, "/");
  const pad = padded.length % 4 === 0 ? "" : "=".repeat(4 - (padded.length % 4));
  return JSON.parse(atob(padded + pad));
}

async function importAppleSigningKey(pem: string): Promise<CryptoKey> {
  const stripped = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = Uint8Array.from(atob(stripped), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    raw,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

// Builds the ES256 JWT App Store Server API auth token per Apple's spec.
// https://developer.apple.com/documentation/appstoreserverapi/generating-json-web-tokens-for-api-requests
async function buildAppleAuthToken(): Promise<string> {
  const key = await importAppleSigningKey(APPSTORE_PRIVATE_KEY);
  const now = Math.floor(Date.now() / 1000);

  const header = { alg: "ES256", kid: APPSTORE_KEY_ID, typ: "JWT" };
  const payload = {
    iss: APPSTORE_ISSUER_ID,
    iat: now,
    exp: now + 15 * 60,
    aud: "appstoreconnect-v1",
    bid: APPSTORE_BUNDLE_ID,
  };

  const encoder = new TextEncoder();
  const signingInput = `${base64url(encoder.encode(JSON.stringify(header)))}.${base64url(encoder.encode(JSON.stringify(payload)))}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(signingInput),
  );
  return `${signingInput}.${base64url(signature)}`;
}

async function fetchTransactionInfo(host: string, transactionId: string, authToken: string) {
  const res = await fetch(`${host}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`, {
    headers: { Authorization: `Bearer ${authToken}` },
  });
  return res;
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return jsonError(401, "Missing authorization token");
  }
  const jwt = authHeader.slice(7);

  let transactionId: string;
  try {
    ({ transactionId } = await req.json());
  } catch {
    return jsonError(400, "Invalid JSON");
  }
  if (!transactionId || typeof transactionId !== "string") {
    return jsonError(400, "Missing transactionId");
  }

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: { user: requester }, error: authError } = await admin.auth.getUser(jwt);
  if (authError || !requester) {
    return jsonError(401, "Invalid or expired token");
  }

  let appleAuthToken: string;
  try {
    appleAuthToken = await buildAppleAuthToken();
  } catch (err) {
    console.error(`verify-subscription: failed to build Apple auth token: ${err}`);
    return jsonError(500, "Server misconfiguration");
  }

  let res = await fetchTransactionInfo(PRODUCTION_HOST, transactionId, appleAuthToken);
  if (!res.ok) {
    // Sandbox/TestFlight transactions aren't known to the production endpoint.
    // Apple returns 404 for an unknown transaction — but for a sandbox
    // transaction id it returns 401 from the production host, so retry sandbox
    // on any non-2xx (not just 404) before giving up. A genuinely bad auth
    // token still fails here because sandbox returns non-2xx too.
    res = await fetchTransactionInfo(SANDBOX_HOST, transactionId, appleAuthToken);
  }

  if (!res.ok) {
    console.error(`verify-subscription: Apple returned ${res.status} for transaction ${transactionId}`);
    return jsonError(res.status === 404 ? 404 : 502, "Could not verify transaction with Apple");
  }

  const { signedTransactionInfo } = await res.json();
  if (!signedTransactionInfo || typeof signedTransactionInfo !== "string") {
    return jsonError(502, "Unexpected response from Apple");
  }

  // The JWS payload is trusted as-is: it came directly from an authenticated
  // HTTPS call to Apple's own API, not from the client, so re-verifying the
  // signature chain would be redundant.
  const segments = signedTransactionInfo.split(".");
  if (segments.length !== 3) {
    return jsonError(502, "Malformed transaction data from Apple");
  }
  const transaction = base64urlDecodeToJSON(segments[1]);

  const isValidPurchase =
    transaction.bundleId === APPSTORE_BUNDLE_ID &&
    KNOWN_PRODUCT_IDS.has(transaction.productId) &&
    !transaction.revocationDate &&
    typeof transaction.expiresDate === "number" &&
    transaction.expiresDate > Date.now();

  if (!isValidPurchase) {
    return new Response(JSON.stringify({ active: false }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const { error: updateError } = await admin
    .from("profiles")
    .update({
      subscription_status: "active",
      subscription_transaction_id: String(transaction.transactionId),
    })
    .eq("id", requester.id);

  if (updateError) {
    // Unique-violation means this transaction id is already bound to a different profile.
    if (updateError.code === "23505") {
      console.error(`verify-subscription: transaction ${transactionId} already bound to another profile`);
      return jsonError(409, "This transaction is already associated with another account");
    }
    console.error(`verify-subscription: profile update error: ${updateError.message}`);
    return jsonError(500, "Failed to update subscription status");
  }

  return new Response(JSON.stringify({ active: true, expiresDate: transaction.expiresDate }), {
    headers: { "Content-Type": "application/json" },
  });
});
