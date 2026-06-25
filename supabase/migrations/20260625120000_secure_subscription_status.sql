-- Prevent direct client writes to profiles.subscription_status.
-- Only the update_subscription_status() RPC and service-role callers may change this column.
--
-- Strategy: a BEFORE UPDATE trigger blocks writes to subscription_status unless
-- the session was flagged by the authorised RPC (via set_config) or the caller
-- is the service role (used by Edge Functions / cron jobs).

-- ── Trigger function ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION prevent_client_subscription_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- No change to subscription_status — allow the row update through.
  IF NEW.subscription_status IS NOT DISTINCT FROM OLD.subscription_status THEN
    RETURN NEW;
  END IF;

  -- Service-role callers (Edge Functions, cron, admin) are always allowed.
  IF auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  -- update_subscription_status() sets this flag (transaction-local) before writing.
  IF current_setting('app.allow_subscription_update', true) = 'true' THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'subscription_status can only be updated via update_subscription_status()';
END;
$$;

CREATE TRIGGER guard_subscription_status
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION prevent_client_subscription_update();

-- ── Secure RPC ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION update_subscription_status(p_status text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_status NOT IN ('active', 'expired') THEN
    RAISE EXCEPTION 'Invalid subscription_status value: %', p_status;
  END IF;

  -- Flag this transaction so the trigger allows the write.
  PERFORM set_config('app.allow_subscription_update', 'true', true);

  UPDATE profiles
  SET subscription_status = p_status
  WHERE id = auth.uid();
END;
$$;

-- Expose to authenticated users only.
REVOKE ALL ON FUNCTION update_subscription_status(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_subscription_status(text) TO authenticated;
