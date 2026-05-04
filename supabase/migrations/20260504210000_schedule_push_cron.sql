-- Migration: schedule_push_cron
-- Uses pg_cron + pg_net to call the process-scheduled-push Edge Function
-- every minute, delivering APNs pushes for any due notification_schedule rows.
--
-- Requires the pg_net extension (enabled by default on Supabase).
-- pg_cron is available on all Supabase plans.

CREATE EXTENSION IF NOT EXISTS pg_net  WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- Schedule the Edge Function to run every minute.
-- The function has JWT verification disabled so no auth header is needed.
SELECT cron.schedule(
    'process-scheduled-push',           -- job name (unique)
    '* * * * *',                        -- every minute
    $$
    SELECT extensions.http_post(
        'https://tyfdsrxkswwwfmdkjknk.functions.supabase.co/process-scheduled-push',
        '{}',
        'application/json'
    )
    $$
);
