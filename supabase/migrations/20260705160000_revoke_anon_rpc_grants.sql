-- Revoke EXECUTE grants that client roles don't need (security audit 2026-07-05).
--
-- All of these RPCs key off auth.uid(), which is NULL for anon, so today the
-- grants are no-ops — but a future edit to any of these functions could turn a
-- stray grant into a real exposure. Principle of least privilege.
--
-- Kept for anon (required pre-login): get_email_for_username (rate-limited),
-- is_username_available.

-- Authenticated-only actions: anon has no business calling these.
revoke execute on function public.activate_trial_subscription() from anon;
revoke execute on function public.claim_device_token() from anon;
revoke execute on function public.delete_my_account() from anon;
revoke execute on function public.expire_my_subscription() from anon;
revoke execute on function public.update_subscription_status(text) from anon;

-- Was granted to PUBLIC (the "=X" ACL entry) in addition to explicit roles.
revoke execute on function public.set_member_disabled(uuid, boolean) from public;
revoke execute on function public.set_member_disabled(uuid, boolean) from anon;

-- Internal rate limiter: only SECURITY DEFINER functions (which run as the
-- function owner) and service-role edge functions may call it. Directly
-- executable by clients, it would let anyone burn a victim's rate-limit keys
-- (e.g. exhaust their signup or username-lookup allowance) as a targeted DoS.
revoke execute on function public.check_and_increment_rate_limit(text, text, integer, integer) from anon, authenticated;
