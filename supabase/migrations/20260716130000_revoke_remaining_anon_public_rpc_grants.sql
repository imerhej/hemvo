-- Revoke the anon/PUBLIC EXECUTE grants the 2026-07-05 sweep missed.
--
-- 20260705160000_revoke_anon_rpc_grants.sql did this for set_member_disabled
-- and friends, but the household RPCs below were overlooked and still carry
-- anon (and in four cases PUBLIC) EXECUTE in the live database.
--
-- None of these is exploitable today: every one keys off auth.uid(), which is
-- NULL for anon, so the owner/membership checks fail closed and the call raises.
-- This is least privilege, not an incident fix — the point is that a future edit
-- to any of these bodies could turn a stray grant into a real exposure, which is
-- exactly the trap the 2026-07-05 migration was written to avoid.
--
-- NOTE ON GRANT DRIFT: CREATE OR REPLACE FUNCTION preserves ACLs, but DROP +
-- CREATE resets them to the default, which includes EXECUTE for PUBLIC. If a
-- later migration ever drops and recreates one of these, the PUBLIC grant comes
-- back silently. Re-run the audit query in this file's footer after any such
-- change rather than trusting the migration history.
--
-- Deliberately NOT touched:
--   * get_email_for_username(text), is_username_available(text) — anon needs
--     both before login; both are rate-limited.
--   * handle_new_user, prevent_client_profile_privilege_update,
--     prevent_client_subscription_update, prevent_client_trial_end_date_abuse,
--     update_device_token_timestamp — these return `trigger`. PostgREST does not
--     expose trigger functions and a direct call fails with "trigger functions
--     can only be called as triggers", so the grant confers nothing. Trigger
--     firing does not consult EXECUTE privilege, so revoking would be harmless
--     but equally pointless; left alone to keep this migration's blast radius at
--     zero for the signup path (handle_new_user fires on auth.users insert).

-- Household membership/ownership RPCs — all require a logged-in caller.
REVOKE EXECUTE ON FUNCTION public.claim_new_household_ownership(uuid) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.delete_household_member(uuid) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.get_my_household_id() FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.join_household_with_code(text) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.leave_household() FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.transfer_household_ownership(uuid, uuid) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.update_member_permissions(uuid, jsonb) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.update_member_role(uuid, text) FROM anon, public;

-- Audit query — should return only the two intentional pre-login RPCs and the
-- trigger functions listed above:
--
--   SELECT p.proname, pg_get_function_result(p.oid)
--     FROM pg_proc p
--     JOIN pg_namespace n ON n.oid = p.pronamespace,
--          LATERAL aclexplode(p.proacl) a
--    WHERE n.nspname = 'public'
--      AND a.privilege_type = 'EXECUTE'
--      AND a.grantee IN (0, 'anon'::regrole)
--    ORDER BY 1;
