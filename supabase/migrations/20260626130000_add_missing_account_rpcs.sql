-- Migration: add_missing_account_rpcs
--
-- Two RPCs called by the iOS app that were never defined in migrations:
--
-- 1. delete_my_account() — SECURITY DEFINER so it can DELETE from auth.users,
--    which requires elevated privileges. The caller is restricted to their own
--    row via auth.uid(). The cascade constraints added in migration
--    20260626120000 atomically remove all child rows.
--
-- 2. is_username_available(p_username) — SECURITY DEFINER so it can read
--    profiles.username for both anon (pre-signup) and authenticated callers
--    without requiring direct table SELECT grants. Returns TRUE if the username
--    is not taken.

-- ── 1. delete_my_account ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM auth.users WHERE id = auth.uid();
END;
$$;

-- Only authenticated users may call this — they can only delete themselves
-- because the WHERE clause is pinned to auth.uid().
REVOKE ALL ON FUNCTION public.delete_my_account() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;

-- ── 2. is_username_available ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_username_available(p_username TEXT)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN NOT EXISTS (
        SELECT 1
          FROM profiles
         WHERE username = lower(trim(p_username))
    );
END;
$$;

-- Callable by anon so that the username availability check works during
-- sign-up before the user has a session.
REVOKE ALL ON FUNCTION public.is_username_available(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.is_username_available(TEXT) TO anon, authenticated;
