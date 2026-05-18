-- Migration: fix_push_pipeline
--
-- Fixes three bugs that made the scheduled push pipeline completely non-functional:
--
-- 1. notification_schedule had RLS enabled with ZERO policies, so the iOS client
--    could not INSERT schedule rows or DELETE cancelled ones. Scheduled pushes
--    were silently dropped at the point of creation.
--
-- 2. The pg_cron job called extensions.http_post() which does not exist; the
--    actual function lives in the net schema. Every cron run has been failing
--    since the job was created. Replaced with the correct net.http_post() call
--    using JSONB-typed arguments.
--
-- 3. process-scheduled-push is now deployed with --no-verify-jwt so the cron
--    job can call it without an auth header (handled at deploy time, not here).

-- ── 1. RLS policies for notification_schedule ────────────────────────────────

-- Any authenticated household member may insert schedule rows for their household.
CREATE POLICY "members_insert_notification_schedule"
    ON notification_schedule
    FOR INSERT
    TO authenticated
    WITH CHECK (
        household_id IN (
            SELECT household_id
            FROM profiles
            WHERE id = auth.uid()
              AND household_id IS NOT NULL
        )
    );

-- Any authenticated household member may delete unsent schedule rows for their
-- household (used when an event is updated or deleted).
CREATE POLICY "members_delete_notification_schedule"
    ON notification_schedule
    FOR DELETE
    TO authenticated
    USING (
        household_id IN (
            SELECT household_id
            FROM profiles
            WHERE id = auth.uid()
              AND household_id IS NOT NULL
        )
    );

-- ── 2. Fix the pg_cron job ───────────────────────────────────────────────────

-- Remove the broken job that used the non-existent extensions.http_post().
SELECT cron.unschedule('process-scheduled-push');

-- Re-create with the correct net.http_post() signature and JSONB-typed args.
-- process-scheduled-push is deployed with --no-verify-jwt so no auth header needed.
SELECT cron.schedule(
    'process-scheduled-push',
    '* * * * *',
    $$
    SELECT net.http_post(
        url     := 'https://tyfdsrxkswwwfmdkjknk.functions.supabase.co/process-scheduled-push',
        body    := '{}'::jsonb,
        headers := '{"Content-Type": "application/json"}'::jsonb
    )
    $$
);
