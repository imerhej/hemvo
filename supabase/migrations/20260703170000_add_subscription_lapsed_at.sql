-- Server-side grace-period clock (2026-07-03).
--
-- Previously each member device started its own 5-day grace countdown in the
-- local Keychain the first time it observed the owner's subscription_status
-- as not-active. Members therefore saw *different* "days left" numbers
-- depending on when each device happened to check, and a reinstall restarted
-- the clock. Store the lapse moment once, server-side, so every household
-- member computes the identical countdown from the same timestamp.
--
-- profiles.subscription_lapsed_at is entirely trigger-managed:
--   subscription_status -> 'active'/'trial'   => cleared to NULL
--   subscription_status -> anything else      => stamped now()
-- Clients can never write the column directly: the guard trigger overwrites
-- any attempted change with the OLD value before deriving the new one, so no
-- separate "blocked column" exception path is needed.

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS subscription_lapsed_at timestamptz;

-- Backfill rows that are already lapsed so their grace window starts at
-- deploy time. This runs while the *current* trigger function is still
-- installed, which allows writes that don't touch subscription_status /
-- subscription_transaction_id; the replacement below would revert them.
UPDATE profiles
SET subscription_lapsed_at = now()
WHERE subscription_status IS DISTINCT FROM 'active'
  AND subscription_status IS DISTINCT FROM 'trial'
  AND subscription_lapsed_at IS NULL;

-- Same body as 20260703140000, plus subscription_lapsed_at derivation.
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
  -- subscription_lapsed_at is derived from status transitions below — discard
  -- whatever the caller tried to write to it (all callers, service_role too).
  NEW.subscription_lapsed_at := OLD.subscription_lapsed_at;

  changed := (NEW.subscription_status IS DISTINCT FROM OLD.subscription_status)
    OR (NEW.subscription_transaction_id IS DISTINCT FROM OLD.subscription_transaction_id);

  IF NOT changed THEN
    RETURN NEW;
  END IF;

  IF auth.role() = 'service_role' THEN
    caller := 'service_role';
  ELSIF current_setting('app.allow_subscription_update', true) = 'true' THEN
    caller := 'user';
  ELSE
    RAISE EXCEPTION 'subscription_status and subscription_transaction_id can only be updated via update_subscription_status(), expire_my_subscription(), or a service-role caller';
  END IF;

  IF NEW.subscription_status IS DISTINCT FROM OLD.subscription_status THEN
    -- 'trial' counts as active: fetchOwnerSubscriptionState() grants members
    -- access for both values, so neither may start the grace clock.
    IF NEW.subscription_status IN ('active', 'trial') THEN
      NEW.subscription_lapsed_at := NULL;
    ELSE
      NEW.subscription_lapsed_at := now();
    END IF;
  END IF;

  INSERT INTO subscription_status_audit (user_id, old_status, new_status, changed_by)
  VALUES (NEW.id, OLD.subscription_status, NEW.subscription_status, caller);

  RETURN NEW;
END;
$$;
