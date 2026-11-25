-- delete_my_account(): keep the household's shared data when a member leaves.
--
-- 20261124120000 handed ownership to a successor, but the departing user's
-- rows still went with the auth.users delete: every content table has
-- created_by → auth.users ON DELETE CASCADE. The owner usually creates most
-- of a household's content, so the household survived with its meals,
-- expenses, events, maintenance and groceries gone (seen on "The Woods",
-- 2026-11-24 22:38).
--
-- Now, before the auth row is deleted, every SHARED row the caller created in
-- the household they're leaving is reassigned to whoever stays in charge
-- (the successor on a transfer, else the existing owner). PERSONAL rows
-- (expenses.scope = 'personal', events.scope = 'Personal') are left alone so
-- the cascade still deletes them — account deletion must remove the user's
-- own data. Reassigning (rather than SET NULL) keeps created_by non-null, so
-- app models that decode it as a UUID keep working.

CREATE OR REPLACE FUNCTION public._reassign_shared_rows(p_hh uuid, p_from uuid, p_to uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_hh IS NULL OR p_to IS NULL OR p_to = p_from THEN
    RETURN;
  END IF;
  UPDATE expenses       SET created_by = p_to WHERE household_id = p_hh AND created_by = p_from AND lower(COALESCE(scope, 'household')) <> 'personal';
  UPDATE events         SET created_by = p_to WHERE household_id = p_hh AND created_by = p_from AND lower(COALESCE(scope, 'household')) <> 'personal';
  UPDATE meals          SET created_by = p_to WHERE household_id = p_hh AND created_by = p_from;
  UPDATE grocery_items  SET created_by = p_to WHERE household_id = p_hh AND created_by = p_from;
  UPDATE maintenance_items SET created_by = p_to WHERE household_id = p_hh AND created_by = p_from;
  UPDATE maintenance_completions SET completed_by = p_to WHERE household_id = p_hh AND completed_by = p_from;
  UPDATE shopping_lists SET created_by = p_to WHERE household_id = p_hh AND created_by = p_from;
  UPDATE shopping_items SET created_by = p_to WHERE household_id = p_hh AND created_by = p_from;
  UPDATE house_tasks    SET created_by = p_to WHERE household_id = p_hh AND created_by = p_from;
END;
$$;

REVOKE ALL ON FUNCTION public._reassign_shared_rows(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._reassign_shared_rows(uuid, uuid, uuid) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_hh        uuid;
  v_result    jsonb;
  v_keeper    uuid;
  v_other     uuid;
  v_successor uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'delete_my_account: not authenticated';
  END IF;

  PERFORM set_config('app.allow_profile_privilege_update', 'true', true);

  -- 1. Leave the current household (transfer / detach / delete-if-last).
  SELECT household_id INTO v_hh FROM profiles WHERE id = v_uid;
  v_result := leave_household_safely();

  IF v_result->>'action' = 'transferred' THEN
    v_keeper := (v_result->>'new_owner_id')::uuid;
  ELSIF v_result->>'action' = 'left' THEN
    SELECT owner_id INTO v_keeper FROM households WHERE id = v_hh;
  END IF;
  PERFORM _reassign_shared_rows(v_hh, v_uid, v_keeper);

  -- 2. Any other household the caller still owns.
  FOR v_other IN
    SELECT id FROM households WHERE owner_id = v_uid FOR UPDATE
  LOOP
    v_successor := NULL;
    SELECT id INTO v_successor
    FROM   profiles
    WHERE  household_id = v_other
      AND  id <> v_uid
    ORDER BY
           COALESCE(disabled, false),
           (lower(COALESCE(role, '')) = 'teen'),
           created_at NULLS LAST,
           id
    LIMIT 1;

    IF v_successor IS NOT NULL THEN
      UPDATE households SET owner_id = v_successor WHERE id = v_other;
      UPDATE profiles   SET role = 'Owner'          WHERE id = v_successor;
      PERFORM _reassign_shared_rows(v_other, v_uid, v_successor);
    ELSE
      DELETE FROM households WHERE id = v_other;
    END IF;
  END LOOP;

  -- 3. The account itself (cascades the profile and the caller's PERSONAL rows).
  DELETE FROM auth.users WHERE id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_my_account() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_my_account() FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;
