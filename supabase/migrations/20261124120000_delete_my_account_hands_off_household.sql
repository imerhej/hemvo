-- delete_my_account(): hand off the household before deleting the account.
--
-- Before this, delete_my_account was a bare `DELETE FROM auth.users`. For an
-- owner whose household still had other members, that cascaded:
--   auth.users → households (owner_id ON DELETE CASCADE)
--              → profiles.household_id ON DELETE SET NULL for every member
-- and the SET NULL fired guard_profile_privilege_columns, which rejected it
-- ("role, household_id, permissions and disabled can only change via ...").
-- The whole deletion rolled back, so owners of shared households could not
-- delete their account at all.
--
-- Had it succeeded it would have been worse: deleting the household cascades
-- to every member's shared meals, budget, schedule, maintenance and groceries.
--
-- Now, in one transaction and with the allow-flag set:
--   1. leave_household_safely() — a member just detaches; an owner with other
--      members hands ownership to the best successor; a last member deletes
--      the household.
--   2. Any OTHER household still owned by the caller (inconsistent data: owner
--      whose profile points elsewhere) gets the same treatment, so the
--      auth.users cascade can never delete a household out from under members.
--   3. Delete the auth user (cascades the profile and the caller's own rows).

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_hh        uuid;
  v_successor uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'delete_my_account: not authenticated';
  END IF;

  PERFORM set_config('app.allow_profile_privilege_update', 'true', true);

  -- 1. The caller's current household.
  PERFORM leave_household_safely();

  -- 2. Any household the caller still owns.
  FOR v_hh IN
    SELECT id FROM households WHERE owner_id = v_uid FOR UPDATE
  LOOP
    SELECT id INTO v_successor
    FROM   profiles
    WHERE  household_id = v_hh
      AND  id <> v_uid
    ORDER BY
           COALESCE(disabled, false),
           (lower(COALESCE(role, '')) = 'teen'),
           created_at NULLS LAST,
           id
    LIMIT 1;

    IF v_successor IS NOT NULL THEN
      UPDATE households SET owner_id = v_successor WHERE id = v_hh;
      UPDATE profiles   SET role = 'Owner'          WHERE id = v_successor;
    ELSE
      DELETE FROM households WHERE id = v_hh;
    END IF;
  END LOOP;

  -- 3. The account itself.
  DELETE FROM auth.users WHERE id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_my_account() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_my_account() FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;
