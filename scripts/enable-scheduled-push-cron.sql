-- HOW TO BRING THE SERVER-SIDE SCHEDULED-PUSH PIPELINE BACK
--
-- NOT A MIGRATION — deliberately kept out of supabase/migrations/ so a routine
-- `supabase db push` can never enable this pipeline by accident.
--
-- ⚠️  DO NOT RUN AS-IS. Running only the SQL at the bottom double-notifies
--     every user. Read the two problems first.
--
-- ── History ─────────────────────────────────────────────────────────────────
-- The cron job for process-scheduled-push never once invoked the function: it
-- omitted the Authorization header the Edge Function gateway requires, so every
-- call was rejected 401 before the function ran (invisible in
-- cron.job_run_details — net.http_post only queues, so the job always read
-- "succeeded"; the truth is in net._http_response). The job was unscheduled
-- and the backlog retired by migration 20261001232000. Nothing was ever
-- delivered through this path, so nothing was lost.
--
-- ── Problem 1: duplicates (blocks a naive re-enable) ────────────────────────
-- The app schedules LOCAL notifications for the same events and meals, at the
-- same times, with the same text — MealPlanViewModel even notes "same format as
-- local notification". Every member who has opened the app holds those locals.
-- Switching the cron on means each reminder arrives twice:
--   • meal rows carry no creator_id  → duplicate hits everyone, planner included
--   • event rows carry creator_id    → duplicate hits everyone but the creator
--
-- Two ways out:
--
--   (a) Server becomes the single source of truth. Ship a client that stops
--       scheduling local event/meal reminders FIRST, then enable the cron.
--       Order matters: reversed, everyone still on the old build is
--       double-notified until they update. Costs offline reliability — a
--       reminder is lost if the device is offline or the project is paused at
--       fire time, where a local would have fired regardless.
--
--   (b) Push only where a local cannot exist (recommended; no client release).
--       device_tokens.updated_at is refreshed on every app foreground by
--       trg_device_tokens_updated_at, and opening the app reschedules all
--       locals. So a device can only hold a local for a given row if it opened
--       the app after that row was written. Push a row only to devices where
--           device_tokens.updated_at < notification_schedule.created_at
--       which is exactly the set of devices that could not have a local for it.
--       No duplicates, and the dormant-device gap is covered. Verify
--       created_at is set on insert for both row sources before relying on it.
--
-- ── Problem 2: recipient permissions are ignored ────────────────────────────
-- This function pushes to every household member, unlike notify-household,
-- which filters on profiles.permissions (receiveCalendarAlerts /
-- receiveMealAlerts). Whichever route is taken above, add that filter, or
-- members who switched these alerts off will start receiving them.
--
-- ── Was it even worth it? ───────────────────────────────────────────────────
-- Measured 2026-10-01: 1 of 80 device tokens had opened the app within 7 days.
-- The dormant-device gap this pipeline closes affected almost nobody, while the
-- duplicate risk would have landed on the few active users. notify-household
-- already pushes at creation time, so dormant members do hear about new
-- events — they only miss the timed reminder. Re-check that ratio before
-- spending effort here.
--
-- ── Prerequisite ────────────────────────────────────────────────────────────
-- The gateway needs a bearer token. The anon key is public (it ships in the
-- iOS app) but the repo keeps Supabase credentials out of git, so store it in
-- internal_config alongside cron_secret and run this once:
--
--   INSERT INTO internal_config (key, value) VALUES ('functions_anon_key', '<anon key>')
--   ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
--
-- Retrieve the key with:
--   supabase projects api-keys --project-ref tyfdsrxkswwwfmdkjknk
--
-- ── Re-enable (only after the above is resolved) ────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM internal_config WHERE key = 'functions_anon_key') THEN
    RAISE EXCEPTION
      'internal_config.functions_anon_key is missing — insert it first (see header)';
  END IF;
END;
$$;

SELECT cron.schedule(
  'process-scheduled-push',
  '* * * * *',
  $job$
    SELECT net.http_post(
        url     := 'https://tyfdsrxkswwwfmdkjknk.functions.supabase.co/process-scheduled-push',
        body    := '{}'::jsonb,
        headers := jsonb_build_object(
            'Content-Type',   'application/json',
            'Authorization',  'Bearer ' || (SELECT value FROM internal_config WHERE key = 'functions_anon_key'),
            'X-Cron-Secret',  (SELECT value FROM internal_config WHERE key = 'cron_secret')
        )
    )
  $job$
);

-- Verify afterwards — job_run_details will lie, so check the HTTP result:
--   select status_code, left(content,140), max(created)
--     from net._http_response group by 1,2 order by 3 desc limit 5;
