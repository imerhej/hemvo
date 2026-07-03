-- Close the subscription self-activation bypass found in security audit (2026-07-03).
--
-- update_subscription_status(p_status) let any authenticated client set their own
-- profiles.subscription_status to 'active' with no purchase verification. Household
-- members read the owner's subscription_status to decide whether they have access,
-- so any user who became a household "Owner" could call this RPC directly with
-- their own session JWT and grant every member of their household permanent free
-- access — no jailbreak or client patching required.
--
-- Fix: only the service_role (driven by the new verify-subscription Edge Function,
-- which confirms the purchase with Apple's App Store Server API before writing) may
-- set subscription_status to 'active'. Clients may still self-downgrade their own
-- row to 'expired' via expire_my_subscription() — a downgrade can never grant
-- unauthorized access, so it's safe to leave client-callable.

REVOKE EXECUTE ON FUNCTION update_subscription_status(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION update_subscription_status(text) TO service_role;

-- ── Anti-replay: bind a verified Apple transaction to exactly one profile ──────
-- Without this, a leaked/shared Apple transaction id could be replayed by the
-- verify-subscription Edge Function against multiple unrelated accounts.
-- A unique index (NULLs excluded) makes the second activation attempt fail.

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS subscription_transaction_id text;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_subscription_transaction_id_unique
  ON profiles (subscription_transaction_id)
  WHERE subscription_transaction_id IS NOT NULL;

-- Extend the existing guard trigger to cover the new column: a direct client
-- write to subscription_transaction_id (without a matching subscription_status
-- change) must be blocked too, otherwise a client could pre-claim a transaction
-- id to grief a legitimate future activation.

CREATE OR REPLACE FUNCTION prevent_client_subscription_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller text;
  changed boolean;
BEGIN
  changed := (NEW.subscription_status IS DISTINCT FROM OLD.subscription_status)
    OR (NEW.subscription_transaction_id IS DISTINCT FROM OLD.subscription_transaction_id);

  IF NOT changed THEN
    RETURN NEW;
  END IF;

  IF auth.role() = 'service_role' THEN
    caller := 'service_role';
    INSERT INTO subscription_status_audit (user_id, old_status, new_status, changed_by)
    VALUES (NEW.id, OLD.subscription_status, NEW.subscription_status, caller);
    RETURN NEW;
  END IF;

  IF current_setting('app.allow_subscription_update', true) = 'true' THEN
    caller := 'user';
    INSERT INTO subscription_status_audit (user_id, old_status, new_status, changed_by)
    VALUES (NEW.id, OLD.subscription_status, NEW.subscription_status, caller);
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'subscription_status and subscription_transaction_id can only be updated via update_subscription_status(), expire_my_subscription(), or a service-role caller';
END;
$$;

CREATE OR REPLACE FUNCTION expire_my_subscription()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Flag this transaction so the existing guard_subscription_status trigger allows the write.
  PERFORM set_config('app.allow_subscription_update', 'true', true);

  UPDATE profiles
  SET subscription_status = 'expired'
  WHERE id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION expire_my_subscription() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION expire_my_subscription() TO authenticated;

-- ── Trial activation stays client-callable, but bounded by the server's own
-- trial_end_date (set once at signup via AuthService.updateTrialEndDate(), never
-- client-extendable) instead of trusting an unconditional client-supplied status.
-- This keeps existing trial-based member access working exactly as before, while
-- removing the previous "call anytime, forever" hole for the trial path too.

CREATE OR REPLACE FUNCTION activate_trial_subscription()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('app.allow_subscription_update', 'true', true);

  UPDATE profiles
  SET subscription_status = 'active'
  WHERE id = auth.uid()
    AND trial_end_date IS NOT NULL
    AND trial_end_date > now();
END;
$$;

REVOKE ALL ON FUNCTION activate_trial_subscription() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION activate_trial_subscription() TO authenticated;
