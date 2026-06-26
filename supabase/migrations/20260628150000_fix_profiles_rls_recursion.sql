-- Fix infinite recursion in profiles_select RLS policy.
--
-- The previous policy used a correlated subquery (SELECT household_id FROM
-- profiles WHERE id = auth.uid()) inside the USING clause. When PostgreSQL
-- evaluates that subquery it re-applies the SELECT policies on profiles,
-- which re-evaluates the same subquery — infinite recursion.
--
-- Fix: extract the inner lookup into a SECURITY DEFINER function. Functions
-- marked SECURITY DEFINER run as the function owner and bypass RLS, so the
-- subquery never re-triggers the policy check.

CREATE OR REPLACE FUNCTION public.get_my_household_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT household_id FROM profiles WHERE id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.get_my_household_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_household_id() TO authenticated;

-- Replace the recursive policy with one that calls the safe helper.
DROP POLICY IF EXISTS "profiles_select" ON profiles;

CREATE POLICY "profiles_select"
    ON profiles
    FOR SELECT
    TO authenticated
    USING (
        id = auth.uid()
        OR (
            household_id IS NOT NULL
            AND household_id = public.get_my_household_id()
        )
    );
