-- Add a disabled flag to profiles so the household owner can suspend members.
-- set_member_disabled RPC follows the same owner-guard pattern as
-- update_member_permissions and delete_household_member.

ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS disabled BOOLEAN NOT NULL DEFAULT FALSE;

-- RPC: set_member_disabled
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

  -- Prevent the owner from disabling their own account.
  IF p_member_id = auth.uid() THEN
    RAISE EXCEPTION 'set_member_disabled: cannot disable your own account';
  END IF;

  UPDATE profiles SET disabled = p_disabled WHERE id = p_member_id;
END;
$$;

GRANT EXECUTE ON FUNCTION set_member_disabled(UUID, BOOLEAN) TO authenticated;
