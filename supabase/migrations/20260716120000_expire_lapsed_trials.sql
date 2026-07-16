-- Migration: expire_lapsed_trials
--
-- activate_trial_subscription() sets subscription_status = 'active' while
-- trial_end_date is in the future, but nothing server-side ever set it back:
-- the only downgrade path was the client calling expire_my_subscription(),
-- fire-and-forget (AuthService.expireSubscriptionStatus uses `try?`). A user
-- who stays offline, blocks that RPC, or never relaunches after the trial keeps
-- 'active' forever — and household members read the owner's status for their
-- own access, so one stale row grants a whole household free use.
--
-- Found in the pre-submission audit (2026-07-16): 7 profiles were 'active' with
-- only 1 holding a subscription_transaction_id, 3 of them with a past
-- trial_end_date. This job makes expiry a server-side fact.
--
-- Scope is deliberately narrow — only rows that are unambiguously lapsed
-- trials:
--   * subscription_transaction_id IS NULL  — never touch a verified Apple
--     purchase. Paid subscriptions are expired by verify-subscription against
--     Apple's records; guessing here could lock out a paying customer.
--   * trial_end_date IS NOT NULL AND < now() — a NULL trial_end_date (e.g. the
--     owner row re-activated by hand on 2026-07-09) is left alone rather than
--     treated as an expired trial.
--
-- 'trial' is expired alongside 'active' because fetchOwnerSubscriptionState()
-- grants member access for both values.
--
-- The job is idempotent: re-running this migration replaces the prior job
-- definition, and the UPDATE is a no-op once a row is already 'expired'.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- ── 1. Let the guard trigger recognise the expiry job ────────────────────────
-- prevent_client_subscription_update() allows a write only from service_role or
-- from a transaction carrying app.allow_subscription_update. pg_cron runs as
-- postgres with no JWT, so auth.role() is NULL and neither branch matches — the
-- job's UPDATE would raise every hour. Reusing app.allow_subscription_update
-- would work but would log every expiry as changed_by = 'user', which is a lie
-- in the one audit trail that exists for subscription changes. A dedicated flag
-- keeps attribution honest.
CREATE OR REPLACE FUNCTION public.prevent_client_subscription_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
  ELSIF current_setting('app.trial_expiry_job', true) = 'true' THEN
    caller := 'trial_expiry_job';
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
$function$;

-- ── 2. The expiry job ───────────────────────────────────────────────────────
-- SECURITY DEFINER so it runs as owner regardless of the cron invoker, and
-- granted to nobody: cron runs it as postgres, which executes it by ownership.
-- No client role has any reason to reach it.
CREATE OR REPLACE FUNCTION public.expire_lapsed_trials()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  affected integer;
BEGIN
  PERFORM set_config('app.trial_expiry_job', 'true', true);

  UPDATE profiles
  SET    subscription_status = 'expired'
  WHERE  subscription_status IN ('active', 'trial')
    AND  subscription_transaction_id IS NULL
    AND  trial_end_date IS NOT NULL
    AND  trial_end_date < now();

  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected;
END;
$function$;

REVOKE ALL ON FUNCTION public.expire_lapsed_trials() FROM public, anon, authenticated;

-- ── 3. Schedule it hourly ───────────────────────────────────────────────────
-- Hourly, not per-minute: the grace-period countdown is measured in days, so an
-- expiry landing up to an hour late costs nothing, and this keeps the audit
-- table from taking a needless write burst.
SELECT cron.unschedule('expire-lapsed-trials')
  WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'expire-lapsed-trials'
  );

SELECT cron.schedule(
  'expire-lapsed-trials',
  '0 * * * *',  -- top of every hour
  $$ SELECT public.expire_lapsed_trials(); $$
);
