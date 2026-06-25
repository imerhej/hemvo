// reset-user-password — Supabase Edge Function
// Called from ResetPasswordView after the recovery session is established.
// Uses the admin API to set the new password, bypassing secure_password_change.
// The recovery session JWT is sent automatically in the Authorization header
// by supabase.functions.invoke — we use it to identify the user.
//
// Secrets used (already set): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Deploy: supabase functions deploy reset-user-password

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

  // Recovery session JWT sent automatically by supabase.functions.invoke
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return jsonError(401, "Missing authorization token");
  }
  const accessToken = authHeader.substring(7);

  let newPassword: string;
  try {
    ({ newPassword } = await req.json());
  } catch {
    return jsonError(400, "Invalid JSON");
  }
  if (!newPassword || newPassword.length < 8) {
    return jsonError(400, "Password must be at least 8 characters");
  }
  if (!/[A-Z]/.test(newPassword)) {
    return jsonError(400, "Password must contain at least one uppercase letter");
  }
  if (!/[0-9]/.test(newPassword)) {
    return jsonError(400, "Password must contain at least one number");
  }

  // Resolve the user ID from the recovery token
  const userClient = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return jsonError(401, "Invalid or expired recovery token");
  }

  // Update password via admin API — bypasses secure_password_change
  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { error: updateError } = await admin.auth.admin.updateUserById(user.id, {
    password: newPassword,
  });
  if (updateError) {
    return jsonError(500, updateError.message);
  }

  return new Response(JSON.stringify({ success: true }), {
    headers: { "Content-Type": "application/json" },
  });
});
