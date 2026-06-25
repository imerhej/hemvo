-- Migration: tighten_profiles_rls_and_username_rpc
--
-- Two changes:
--
-- 1. Replace the permissive profiles_select policy (USING true — any
--    authenticated user can read every profile row) with one that scopes
--    reads to the caller's own row plus their household members.
--
-- 2. Add get_email_for_username() — a SECURITY DEFINER function callable
--    by the anon role so that username-based login can resolve email without
--    requiring direct profiles table access for unauthenticated callers.

-- ── 1. get_email_for_username ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_email_for_username(p_username TEXT)
RETURNS TABLE(email TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT p.email
      FROM profiles p
     WHERE p.username = lower(trim(p_username))
     LIMIT 1;
END;
$$;

-- Callable by anon so that unauthenticated username login works.
REVOKE ALL ON FUNCTION public.get_email_for_username(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_email_for_username(TEXT) TO anon, authenticated;

-- ── 2. Tighten profiles SELECT policy ────────────────────────────────────────

DROP POLICY IF EXISTS "profiles_select" ON profiles;

-- Authenticated users may read their own row and their household members' rows.
-- Anon callers cannot read profiles directly; they must use get_email_for_username().
CREATE POLICY "profiles_select"
    ON profiles
    FOR SELECT
    TO authenticated
    USING (
        id = auth.uid()
        OR household_id IS NOT NULL AND household_id = (
            SELECT household_id
              FROM profiles
             WHERE id = auth.uid()
             LIMIT 1
        )
    );
