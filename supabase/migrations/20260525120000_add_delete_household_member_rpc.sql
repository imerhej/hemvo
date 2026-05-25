-- RPC: delete_household_member
-- Allows a household owner to fully delete another member's Supabase auth
-- account. Deleting from auth.users cascades to the profile row via FK.
-- SECURITY DEFINER runs as the postgres role so it can reach auth.users.

CREATE OR REPLACE FUNCTION delete_household_member(p_member_id UUID)
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
    RAISE EXCEPTION 'delete_household_member: caller is not the household owner';
  END IF;

  -- Prevent owners from deleting themselves through this path.
  IF p_member_id = auth.uid() THEN
    RAISE EXCEPTION 'delete_household_member: cannot delete your own account via this function';
  END IF;

  -- Delete the member — cascades to their profile row.
  DELETE FROM auth.users WHERE id = p_member_id;
END;
$$;

-- Grant execute to authenticated users so the Supabase client can call it.
GRANT EXECUTE ON FUNCTION delete_household_member(UUID) TO authenticated;
