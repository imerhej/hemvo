-- leave_household_safely(): one atomic, server-decided "leave household".
--
-- Before this, HouseholdService.leaveHousehold decided on the CLIENT whether an
-- owner's departure should transfer ownership or delete the household, using
-- the member list cached in UserDefaults. A stale cache (e.g. members joined
-- since the last successful refresh) made a multi-member household look like
-- the owner was alone, and the client then issued a raw DELETE on households —
-- which cascades to events, house_tasks, budget_settings, budget_categories,
-- maintenance_completions, etc. for every member. It also handed ownership to
-- whichever member happened to be first in the cached array, Teen included.
--
-- This RPC makes the decision from the live profiles table, under a row lock
-- on the household so two concurrent leaves can't both see "someone else is
-- still here" or both see "I'm last":
--   • caller not in a household        → {"action":"none"}
--   • caller is not the owner          → clear caller's row → {"action":"left"}
--   • owner, other members remain      → transfer to best successor, clear
--                                         caller → {"action":"transferred",
--                                         "new_owner_id": <uuid>}
--     Successor preference: enabled non-Teen, then enabled Teen, then any
--     remaining (disabled) member; oldest account first within each tier. The
--     household is NEVER deleted while any other member still belongs to it.
--   • owner and genuinely the last member → delete the household (cascades)
--                                         → {"action":"deleted"}
--
-- The allow-flag is set before any profiles write, including the ON DELETE
-- SET NULL cascade from households → profiles, which also fires the
-- guard_profile_privilege_columns trigger.
--
-- Additive: the old leave_household / transfer_household_ownership RPCs stay
-- in place so builds already in users' hands keep working.

CREATE OR REPLACE FUNCTION leave_household_safely()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid          uuid := auth.uid();
  v_household_id uuid;
  v_owner_id     uuid;
  v_successor    uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'leave_household_safely: not authenticated';
  END IF;

  SELECT household_id INTO v_household_id FROM profiles WHERE id = v_uid;
  IF v_household_id IS NULL THEN
    RETURN jsonb_build_object('action', 'none');
  END IF;

  -- Serialise concurrent leaves/transfers for this household.
  SELECT owner_id INTO v_owner_id
  FROM   households
  WHERE  id = v_household_id
  FOR UPDATE;

  PERFORM set_config('app.allow_profile_privilege_update', 'true', true);

  -- Household row already gone, or caller is a regular member: just detach.
  IF v_owner_id IS NULL OR v_owner_id <> v_uid THEN
    UPDATE profiles SET household_id = NULL, role = NULL WHERE id = v_uid;
    RETURN jsonb_build_object('action', 'left');
  END IF;

  -- Caller is the owner. Pick a successor from the LIVE membership.
  SELECT id INTO v_successor
  FROM   profiles
  WHERE  household_id = v_household_id
    AND  id <> v_uid
  ORDER BY
         COALESCE(disabled, false),                     -- enabled first
         (lower(COALESCE(role, '')) = 'teen'),          -- adults before teens
         created_at NULLS LAST,
         id
  LIMIT 1;

  IF v_successor IS NOT NULL THEN
    UPDATE households SET owner_id = v_successor WHERE id = v_household_id;
    UPDATE profiles   SET role = 'Owner'          WHERE id = v_successor;
    UPDATE profiles   SET household_id = NULL, role = NULL WHERE id = v_uid;
    RETURN jsonb_build_object('action', 'transferred', 'new_owner_id', v_successor);
  END IF;

  -- Genuinely the last member: delete the household (cascades shared data).
  UPDATE profiles SET household_id = NULL, role = NULL WHERE id = v_uid;
  DELETE FROM households WHERE id = v_household_id;
  RETURN jsonb_build_object('action', 'deleted');
END;
$$;

REVOKE ALL ON FUNCTION leave_household_safely() FROM PUBLIC;
REVOKE ALL ON FUNCTION leave_household_safely() FROM anon;
GRANT EXECUTE ON FUNCTION leave_household_safely() TO authenticated;
