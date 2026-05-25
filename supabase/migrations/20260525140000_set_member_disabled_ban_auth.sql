-- Replace set_member_disabled to also set auth.users.banned_until.
-- Supabase rejects token refreshes for banned users, which invalidates
-- their session within one JWT TTL (~1 hour). The profiles.disabled flag
-- is kept for UI display.

CREATE OR REPLACE FUNCTION set_member_disabled(p_member_id UUID, p_disabled BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Caller must be the Owner of the same household as the target member.
  IF NOT EXISTS (
    SELECT 1
    FROM   profiles AS caller
    JOIN   profiles AS member ON member.id = p_member_id
    WHERE  caller.id            = auth.uid()
      AND  caller.household_id IS NOT NULL
      AND  caller.household_id  = member.household_id
      AND  caller.role          = 'Owner'
  ) THEN
    RAISE EXCEPTION 'set_member_disabled: caller is not the household owner';
  END IF;

  IF p_member_id = auth.uid() THEN
    RAISE EXCEPTION 'set_member_disabled: cannot disable your own account';
  END IF;

  -- Update the display flag on the profile.
  UPDATE public.profiles SET disabled = p_disabled WHERE id = p_member_id;

  -- Set/clear the native Supabase auth ban so token refresh is rejected.
  -- 100 years ≈ permanent; NULL lifts the ban.
  UPDATE auth.users
  SET    banned_until = CASE
           WHEN p_disabled THEN NOW() + INTERVAL '100 years'
           ELSE NULL
         END
  WHERE  id = p_member_id;
END;
$$;

GRANT EXECUTE ON FUNCTION set_member_disabled(UUID, BOOLEAN) TO authenticated;
