-- Follow-up to 20260703150000, same day.
--
-- 1. 20260703150000's guard_profile_privilege_columns trigger blocks any UPDATE
--    to profiles.role/household_id unless service_role or an authorised RPC sets
--    app.allow_profile_privilege_update. Only update_member_role,
--    update_member_permissions, set_member_disabled and join_household_with_code
--    were updated to set that flag. Three other legitimate write paths were
--    missed and are broken in production right now:
--      - creating a household (HouseholdService.upsertHouseholdToSupabase does a
--        raw `UPDATE profiles SET household_id=.., role='Owner'`)
--      - leaving a household (HouseholdService.clearProfileHousehold does a raw
--        `UPDATE profiles SET household_id=NULL, role=NULL`)
--      - removing a member (delete_household_member RPC does the same raw
--        UPDATE, but never set the allow-flag)
--    Fixed here by adding the flag to delete_household_member, and by adding
--    three new guarded RPCs (claim_new_household_ownership, leave_household,
--    transfer_household_ownership) that the client now calls instead of
--    writing to profiles directly. transfer_household_ownership also fixes a
--    pre-existing bug: the new owner's profile.role update in
--    transferOwnershipInSupabase was writing to someone else's row, which the
--    base profiles_update RLS (id = auth.uid()) already silently rejected —
--    ownership transfer never actually promoted the new owner.
--
-- 2. maintenance_completions_insert (added in 20260703130000, 20 minutes before
--    the INSERT-policy hardening pass in 20260703150000) only checked
--    completed_by = auth.uid(), never household membership — any authenticated
--    user could inject fabricated maintenance-history rows into any household
--    by UUID. Brought in line with the other six tables' INSERT policies.

-- ═════════════════════════════════════════════════════════════════════════════
-- 1a. delete_household_member: set the allow-flag before writing profiles
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION delete_household_member(p_member_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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

  IF p_member_id = auth.uid() THEN
    RAISE EXCEPTION 'delete_household_member: cannot remove your own account via this function';
  END IF;

  PERFORM set_config('app.allow_profile_privilege_update', 'true', true);

  UPDATE profiles
  SET    household_id = NULL,
         role         = NULL
  WHERE  id = p_member_id;
END;
$$;

-- ═════════════════════════════════════════════════════════════════════════════
-- 1b. claim_new_household_ownership: caller becomes Owner of a household they
--     already own the households row for (checked below), and does not yet
--     belong to any household.
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION claim_new_household_ownership(p_household_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM households
    WHERE id = p_household_id AND owner_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'claim_new_household_ownership: caller does not own household %', p_household_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND household_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'claim_new_household_ownership: caller already belongs to a household';
  END IF;

  PERFORM set_config('app.allow_profile_privilege_update', 'true', true);

  UPDATE profiles
  SET    household_id = p_household_id,
         role         = 'Owner'
  WHERE  id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION claim_new_household_ownership(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION claim_new_household_ownership(UUID) TO authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- 1c. leave_household: caller clears household_id/role on their own row only.
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION leave_household()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('app.allow_profile_privilege_update', 'true', true);

  UPDATE profiles
  SET    household_id = NULL,
         role         = NULL
  WHERE  id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION leave_household() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION leave_household() TO authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- 1d. transfer_household_ownership: caller (current owner) hands ownership to
--     an existing member of the same household.
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION transfer_household_ownership(p_household_id UUID, p_new_owner_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM households
    WHERE id = p_household_id AND owner_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'transfer_household_ownership: caller is not the current owner';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = p_new_owner_id AND household_id = p_household_id
  ) THEN
    RAISE EXCEPTION 'transfer_household_ownership: target is not a member of this household';
  END IF;

  UPDATE households SET owner_id = p_new_owner_id WHERE id = p_household_id;

  PERFORM set_config('app.allow_profile_privilege_update', 'true', true);

  UPDATE profiles SET role = 'Owner' WHERE id = p_new_owner_id;
END;
$$;

REVOKE ALL ON FUNCTION transfer_household_ownership(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION transfer_household_ownership(UUID, UUID) TO authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- 2. maintenance_completions_insert: require household membership, not just
--    completed_by = auth.uid().
-- ═════════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "maintenance_completions_insert" ON maintenance_completions;
CREATE POLICY "maintenance_completions_insert"
  ON maintenance_completions FOR INSERT
  TO authenticated
  WITH CHECK (
    completed_by = auth.uid()
    AND household_id = get_my_household_id()
  );
