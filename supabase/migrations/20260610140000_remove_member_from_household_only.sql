-- Replace delete_household_member to remove the member from the household
-- without deleting their auth account.  The member's account remains valid
-- and they are routed to HouseholdSetupView on their next app launch.

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

  -- Prevent owners from removing themselves through this path.
  IF p_member_id = auth.uid() THEN
    RAISE EXCEPTION 'delete_household_member: cannot remove your own account via this function';
  END IF;

  -- Detach the member from the household; their auth account is preserved.
  UPDATE profiles
  SET    household_id = NULL,
         role         = NULL
  WHERE  id = p_member_id;
END;
$$;

-- Grant is already in place from the original migration; no change needed.
