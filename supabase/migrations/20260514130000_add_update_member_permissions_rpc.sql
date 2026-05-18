-- RPC: update_member_permissions
-- Allows a household owner to update the `permissions` JSONB column of
-- another member's profile row. Direct UPDATE via RLS is blocked because
-- the profiles policy only permits users to update their own row.
-- SECURITY DEFINER lets this function act with elevated privileges after
-- it validates that the caller really is the household owner.

CREATE OR REPLACE FUNCTION update_member_permissions(
  p_member_id  UUID,
  p_permissions JSONB
)
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
    RAISE EXCEPTION 'update_member_permissions: caller is not the household owner';
  END IF;

  UPDATE profiles
  SET    permissions = p_permissions
  WHERE  id = p_member_id;
END;
$$;

-- Grant execute to authenticated users so the Supabase client can call it.
GRANT EXECUTE ON FUNCTION update_member_permissions(UUID, JSONB) TO authenticated;
