-- Migration: rate_limit_cleanup
--
-- rate_limits rows are never deleted by check_and_increment_rate_limit —
-- expired windows are reset in-place but the rows stay forever. On a busy
-- app (or under abuse) this table grows unboundedly. This migration schedules
-- an hourly pg_cron job to purge rows whose window expired more than 2 hours
-- ago (double the max window used anywhere in the system).
--
-- The job is idempotent: re-running this migration reschedules the same job
-- name, replacing any prior definition.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

SELECT cron.unschedule('purge-expired-rate-limits')
  WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'purge-expired-rate-limits'
  );

SELECT cron.schedule(
  'purge-expired-rate-limits',
  '0 * * * *',  -- top of every hour
  $$
  DELETE FROM public.rate_limits
   WHERE window_start < NOW() - INTERVAL '2 hours';
  $$
);
