-- Security hardening follow-ups from audit:
--
-- 1. check_and_increment_rate_limit() had no explicit grants, so it was
--    callable by PUBLIC (including anon) by default. Any caller could pass
--    an arbitrary key/action to pollute or reset another actor's rate-limit
--    bucket. It's only ever invoked directly by Edge Functions (service_role)
--    or from within other SECURITY DEFINER RPCs (which run as the function
--    owner and don't need a separate grant), so restrict it to service_role.
--
-- 2. prevent_client_subscription_update() is SECURITY DEFINER but, unlike
--    every other SECURITY DEFINER function in this schema, was missing
--    `SET search_path`. Pin it for consistency and to close off search_path
--    hijacking as a theoretical attack surface.

REVOKE ALL ON FUNCTION check_and_increment_rate_limit(TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION check_and_increment_rate_limit(TEXT, TEXT, INTEGER, INTEGER) TO service_role;

CREATE OR REPLACE FUNCTION prevent_client_subscription_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller text;
BEGIN
  -- No change to subscription_status — let other column updates through.
  IF NEW.subscription_status IS NOT DISTINCT FROM OLD.subscription_status THEN
    RETURN NEW;
  END IF;

  -- Service-role callers (Edge Functions, cron, admin) are always allowed.
  IF auth.role() = 'service_role' THEN
    caller := 'service_role';
    INSERT INTO subscription_status_audit (user_id, old_status, new_status, changed_by)
    VALUES (NEW.id, OLD.subscription_status, NEW.subscription_status, caller);
    RETURN NEW;
  END IF;

  -- update_subscription_status() sets this flag (transaction-local) before writing.
  IF current_setting('app.allow_subscription_update', true) = 'true' THEN
    caller := 'user';
    INSERT INTO subscription_status_audit (user_id, old_status, new_status, changed_by)
    VALUES (NEW.id, OLD.subscription_status, NEW.subscription_status, caller);
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'subscription_status can only be updated via update_subscription_status()';
END;
$$;
