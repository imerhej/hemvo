-- Audit log for subscription_status changes.
-- Every write that passes the guard trigger (via update_subscription_status() RPC
-- or service-role callers) is recorded here with old/new status and caller type.

-- ── Audit table ───────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS subscription_status_audit (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    changed_at  timestamptz NOT NULL DEFAULT now(),
    old_status  text,
    new_status  text        NOT NULL,
    changed_by  text        NOT NULL  -- 'user' | 'service_role'
);

ALTER TABLE subscription_status_audit ENABLE ROW LEVEL SECURITY;

-- Authenticated users may only read their own rows.
DROP POLICY IF EXISTS "subscription_audit_select" ON subscription_status_audit;
CREATE POLICY "subscription_audit_select"
  ON subscription_status_audit FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- The trigger function (SECURITY DEFINER) performs all writes; revoke direct access.
REVOKE ALL ON TABLE subscription_status_audit FROM PUBLIC;
GRANT SELECT ON TABLE subscription_status_audit TO authenticated;

-- ── Updated trigger — now logs on every allowed change ────────────────────────

CREATE OR REPLACE FUNCTION prevent_client_subscription_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
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
