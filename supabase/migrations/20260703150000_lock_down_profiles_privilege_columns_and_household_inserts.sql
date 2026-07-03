-- Security hardening — follow-up audit, same day as 20260703140000.
--
-- 1. profiles_update RLS only restricts *which row* a user can touch (their own),
--    never *which columns*. Every "secure" RPC in this schema (update_member_role,
--    update_member_permissions, set_member_disabled, join_household_with_code)
--    exists specifically because a raw `UPDATE profiles` was assumed blocked for
--    privileged columns — it wasn't. Any authenticated user could PATCH their own
--    row directly via PostgREST to:
--      - set role = 'Owner' (self-promote, bypassing every Owner-gated action)
--      - set household_id to any household's UUID (join without an invite code)
--      - set permissions to anything (self-grant arbitrary JSON permissions)
--      - reset their own disabled flag back to false
--      - most seriously: set trial_end_date to any future date, then call
--        activate_trial_subscription() — this fully re-opens the subscription
--        self-activation bypass that 20260703140000 closed, via a different column.
--
--    Fix: a second BEFORE UPDATE trigger guards role/household_id/permissions/
--    disabled the same way guard_subscription_status already guards
--    subscription_status — blocked unless service_role or an authorised RPC flags
--    the transaction via set_config. trial_end_date gets its own narrower,
--    self-contained rule (settable exactly once, only to a near-term date) so the
--    existing client call in AuthService.updateTrialEndDate() keeps working
--    without requiring an app update.
--
-- 2. INSERT policies on events/house_tasks/expenses/meals/grocery_items/
--    shopping_lists only checked `created_by = auth.uid()`, never that
--    household_id belongs to the caller — any authenticated user (including a
--    removed former member, since removal doesn't revoke their JWT until it
--    expires) could inject rows into ANY household by UUID. Fixed by requiring
--    household_id to be NULL or the caller's own household, via the existing
--    get_my_household_id() helper.
--
-- 3. join_household_with_code() lost its EMAIL_MISMATCH check when
--    20260701120000 (rate limiting) was written against a stale copy of the
--    function body — restoring it here alongside the rate limit.

-- ═════════════════════════════════════════════════════════════════════════════
-- 1a. Guard role / household_id / permissions / disabled
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION prevent_client_profile_privilege_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.role IS NOT DISTINCT FROM OLD.role
     AND NEW.household_id IS NOT DISTINCT FROM OLD.household_id
     AND NEW.permissions IS NOT DISTINCT FROM OLD.permissions
     AND NEW.disabled IS NOT DISTINCT FROM OLD.disabled
  THEN
    RETURN NEW;
  END IF;

  IF auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  IF current_setting('app.allow_profile_privilege_update', true) = 'true' THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'role, household_id, permissions and disabled can only change via update_member_role(), update_member_permissions(), set_member_disabled(), join_household_with_code(), or a service-role caller';
END;
$$;

CREATE TRIGGER guard_profile_privilege_columns
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION prevent_client_profile_privilege_update();

-- ═════════════════════════════════════════════════════════════════════════════
-- 1b. Guard trial_end_date: settable exactly once, only to a near-term date
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION prevent_client_trial_end_date_abuse()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.trial_end_date IS NOT DISTINCT FROM OLD.trial_end_date THEN
    RETURN NEW;
  END IF;

  IF auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  -- Legitimate first-time trial start (AuthViewModel.startTrial() ->
  -- AuthService.updateTrialEndDate()): can only be set once (OLD must be NULL)
  -- and only to a date within 8 days (7-day trial + 1-day clock-skew buffer),
  -- never reset or extended afterward.
  IF OLD.trial_end_date IS NULL
     AND NEW.trial_end_date > now()
     AND NEW.trial_end_date <= now() + interval '8 days'
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'trial_end_date can only be set once, to a date within 8 days of signup';
END;
$$;

CREATE TRIGGER guard_trial_end_date
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION prevent_client_trial_end_date_abuse();

-- ═════════════════════════════════════════════════════════════════════════════
-- 1c. Flag the legitimate privilege-changing RPCs to pass the new guard
-- ═════════════════════════════════════════════════════════════════════════════

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
  IF p_role NOT IN ('Adult', 'Teen') THEN
    RAISE EXCEPTION 'update_member_role: invalid role "%"', p_role;
  END IF;

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

  PERFORM set_config('app.allow_profile_privilege_update', 'true', true);

  UPDATE profiles
  SET    role = p_role
  WHERE  id = p_member_id;
END;
$$;

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

  PERFORM set_config('app.allow_profile_privilege_update', 'true', true);

  UPDATE profiles
  SET
    permissions = p_permissions,
    notif_bills = CASE
      WHEN NOT (p_permissions->>'receiveExpenseAlerts')::boolean THEN false
      ELSE notif_bills
    END,
    notif_meals = CASE
      WHEN NOT (p_permissions->>'receiveMealAlerts')::boolean THEN false
      ELSE notif_meals
    END,
    notif_schedule = CASE
      WHEN NOT (p_permissions->>'receiveCalendarAlerts')::boolean THEN false
      ELSE notif_schedule
    END,
    notif_maintenance = CASE
      WHEN NOT (p_permissions->>'receiveMaintenanceAlerts')::boolean THEN false
      ELSE notif_maintenance
    END
  WHERE id = p_member_id;
END;
$$;

CREATE OR REPLACE FUNCTION set_member_disabled(p_member_id UUID, p_disabled BOOLEAN)
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
    RAISE EXCEPTION 'set_member_disabled: caller is not the household owner';
  END IF;

  IF p_member_id = auth.uid() THEN
    RAISE EXCEPTION 'set_member_disabled: cannot disable your own account';
  END IF;

  PERFORM set_config('app.allow_profile_privilege_update', 'true', true);

  UPDATE public.profiles SET disabled = p_disabled WHERE id = p_member_id;

  UPDATE auth.users
  SET    banned_until = CASE
           WHEN p_disabled THEN NOW() + INTERVAL '100 years'
           ELSE NULL
         END
  WHERE  id = p_member_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.join_household_with_code(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite      household_invites%ROWTYPE;
    v_user_id     UUID := auth.uid();
    v_user_email  TEXT;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    IF NOT check_and_increment_rate_limit(
        v_user_id::text, 'join_household', 10, 10
    ) THEN
        RAISE EXCEPTION 'rate_limit_exceeded' USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_invite
    FROM household_invites
    WHERE UPPER(code) = UPPER(TRIM(p_code))
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'INVALID_CODE';
    END IF;

    IF v_invite.expires_at < now() THEN
        RAISE EXCEPTION 'EXPIRED_CODE';
    END IF;

    IF v_invite.accepted_at IS NOT NULL THEN
        RAISE EXCEPTION 'ALREADY_USED';
    END IF;

    -- Restored: was dropped by 20260701120000, which was written against a
    -- stale copy of this function that predated the email-lock-in check.
    SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;
    IF LOWER(v_user_email) != LOWER(v_invite.invitee_email) THEN
        RAISE EXCEPTION 'EMAIL_MISMATCH';
    END IF;

    IF EXISTS (
        SELECT 1 FROM profiles
        WHERE id = v_user_id AND household_id IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'ALREADY_MEMBER';
    END IF;

    PERFORM set_config('app.allow_profile_privilege_update', 'true', true);

    UPDATE profiles
    SET
        household_id = v_invite.household_id,
        role         = v_invite.role,
        permissions  = v_invite.permissions
    WHERE id = v_user_id;

    UPDATE household_invites
    SET
        accepted_at = now(),
        accepted_by = v_user_id
    WHERE id = v_invite.id;

    RETURN jsonb_build_object(
        'household_id',   v_invite.household_id,
        'household_name', v_invite.household_name,
        'inviter_name',   v_invite.inviter_name,
        'role',           v_invite.role,
        'permissions',    v_invite.permissions
    );
END;
$$;

-- ═════════════════════════════════════════════════════════════════════════════
-- 2. Household content INSERT policies: require household_id to be NULL or the
--    caller's own household, not just created_by = auth.uid().
-- ═════════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "events_insert" ON events;
CREATE POLICY "events_insert"
  ON events FOR INSERT
  TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND (household_id IS NULL OR household_id = get_my_household_id())
  );

DROP POLICY IF EXISTS "house_tasks_insert" ON house_tasks;
CREATE POLICY "house_tasks_insert"
  ON house_tasks FOR INSERT
  TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND (household_id IS NULL OR household_id = get_my_household_id())
  );

DROP POLICY IF EXISTS "expenses_insert" ON expenses;
CREATE POLICY "expenses_insert"
  ON expenses FOR INSERT
  TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND (household_id IS NULL OR household_id = get_my_household_id())
  );

DROP POLICY IF EXISTS "meals_insert" ON meals;
CREATE POLICY "meals_insert"
  ON meals FOR INSERT
  TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND (household_id IS NULL OR household_id = get_my_household_id())
  );

DROP POLICY IF EXISTS "grocery_items_insert" ON grocery_items;
CREATE POLICY "grocery_items_insert"
  ON grocery_items FOR INSERT
  TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND (household_id IS NULL OR household_id = get_my_household_id())
  );

DROP POLICY IF EXISTS "shopping_lists_insert" ON shopping_lists;
CREATE POLICY "shopping_lists_insert"
  ON shopping_lists FOR INSERT
  TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND (household_id IS NULL OR household_id = get_my_household_id())
  );
