-- Remove the Child role from the application.
-- Update update_member_role RPC to only accept Adult and Teen as valid targets.

CREATE OR REPLACE FUNCTION update_member_role(
  p_member_id UUID,
  p_role       TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Guard: only Adult / Teen are valid targets.
  IF p_role NOT IN ('Adult', 'Teen') THEN
    RAISE EXCEPTION 'update_member_role: invalid role "%"', p_role;
  END IF;

  -- Guard: caller must be the Owner of the member's household.
  IF NOT EXISTS (
    SELECT 1
    FROM   profiles AS caller
    JOIN   profiles AS member ON member.id = p_member_id
    WHERE  caller.id            = auth.uid()
      AND  caller.household_id IS NOT NULL
      AND  caller.household_id  = member.household_id
      AND  caller.role          = 'Owner'
  ) THEN
    RAISE EXCEPTION 'update_member_role: caller is not the household owner';
  END IF;

  UPDATE profiles
  SET    role = p_role
  WHERE  id = p_member_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_member_role(UUID, TEXT) TO authenticated;
