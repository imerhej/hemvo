-- Retires the process-scheduled-push cron job, which has never worked.
--
-- Background: the job (jobid 4, every minute) called the Edge Function without
-- an Authorization header, so Supabase's gateway answered 401
-- UNAUTHORIZED_NO_AUTH_HEADER before the function ran. Every scheduled push
-- since the job was created was dropped — `sent` was false on all 76 rows the
-- table had ever held, going back to 2026-05-25. It looked healthy because
-- net.http_post only queues the request: cron.job_run_details reported
-- "succeeded" every minute regardless of the HTTP result.
--
-- Why retire rather than repair: the app already schedules LOCAL notifications
-- for the same events and meals, at the same times, with the same text, on
-- every member's device. Repairing the header would double-notify every user
-- (meal rows carry no creator_id, so even the planner gets two). Local
-- reminders are also strictly more reliable — they fire offline, need no valid
-- APNs token, and don't depend on this free-tier project staying unpaused.
--
-- Leaving the job scheduled meant one header away from that duplicate storm,
-- plus a wasted request every minute filling net._http_response. So: unschedule
-- it, and retire the overdue rows so a future re-enable can't start on a
-- backlog. See scripts/enable-scheduled-push-cron.sql for how to bring the
-- pipeline back correctly if the dormant-device gap ever justifies it.
--
-- Nothing here changes what users receive: this pipeline has never delivered
-- a single notification.

-- 1. Stop the job. Idempotent: cron.unschedule() throws if the job is absent.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'process-scheduled-push') THEN
    PERFORM cron.unschedule('process-scheduled-push');
  END IF;
END;
$$;

-- 2. Retire the undeliverable backlog. Only rows already past their fire time —
-- any future-dated row is left untouched, so re-enabling later still honours it.
UPDATE public.notification_schedule
   SET sent = true
 WHERE sent = false
   AND fire_at <= now();
