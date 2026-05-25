// delete-member — Supabase Edge Function
// Allows a household owner to delete another member's Supabase auth account.
// The requesting user's JWT is verified; they must hold the "Owner" role in
// the same household as the member being deleted.
//
// Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Deploy: supabase functions deploy delete-member

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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
  if (!authHeader?.startsWith("Bearer ")) {
    return jsonError(401, "Missing authorization token");
  }
  const jwt = authHeader.slice(7);

  let memberID: string;
  try {
    ({ member_id: memberID } = await req.json());
  } catch {
    return jsonError(400, "Invalid JSON");
  }
  if (!memberID) return jsonError(400, "Missing member_id");

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Resolve the requesting user from their JWT.
  const { data: { user: requester }, error: authError } = await admin.auth.getUser(jwt);
  if (authError || !requester) {
    return jsonError(401, "Invalid or expired token");
  }

  // Prevent self-deletion through this endpoint.
  if (requester.id === memberID) {
    return jsonError(400, "Use the delete-account flow to remove your own account");
  }

  // Verify the requester holds the Owner role.
  const { data: requesterProfile, error: rErr } = await admin
    .from("profiles")
    .select("household_id, role")
    .eq("id", requester.id)
    .single();

  if (rErr || !requesterProfile) {
    return jsonError(403, "Could not verify requester profile");
  }
  if (requesterProfile.role !== "Owner") {
    return jsonError(403, "Only the household owner can delete members");
  }

  // Confirm the target member belongs to the same household.
  const { data: memberProfile, error: mErr } = await admin
    .from("profiles")
    .select("household_id")
    .eq("id", memberID)
    .single();

  if (mErr || !memberProfile) {
    return jsonError(404, "Member not found");
  }
  if (memberProfile.household_id !== requesterProfile.household_id) {
    return jsonError(403, "Member does not belong to your household");
  }

  // Delete the member's auth account. Cascades to their profile row.
  const { error: deleteError } = await admin.auth.admin.deleteUser(memberID);
  if (deleteError) {
    console.error(`delete-member: deleteUser error: ${deleteError.message}`);
    return jsonError(500, "Failed to delete member account");
  }

  return new Response(JSON.stringify({ deleted: true }), {
    headers: { "Content-Type": "application/json" },
  });
});
