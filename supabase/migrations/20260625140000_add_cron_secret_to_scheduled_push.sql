-- Migration: add_cron_secret_to_scheduled_push
--
-- Adds an X-Cron-Secret header to the pg_cron HTTP POST so that
-- process-scheduled-push rejects unauthenticated invocations.
--
-- Steps after running this migration:
--   1. Copy the secret value from this table:
--        SELECT value FROM internal_config WHERE key = 'cron_secret';
--   2. Set it as a Supabase Edge Function secret:
--        supabase secrets set CRON_SECRET=<value-from-step-1>
--   3. Redeploy the function:
--        supabase functions deploy process-scheduled-push --no-verify-jwt
--
-- The internal_config table is RLS-enabled with no policies, so it is
-- accessible only to the service_role (pg_cron runs as superuser and can read it).

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS internal_config (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
ALTER TABLE internal_config ENABLE ROW LEVEL SECURITY;

INSERT INTO internal_config (key, value)
VALUES ('cron_secret', encode(extensions.gen_random_bytes(32), 'hex'))
ON CONFLICT (key) DO NOTHING;

SELECT cron.unschedule('process-scheduled-push');

SELECT cron.schedule(
    'process-scheduled-push',
    '* * * * *',
    $$
    SELECT net.http_post(
        url     := 'https://tyfdsrxkswwwfmdkjknk.functions.supabase.co/process-scheduled-push',
        body    := '{}'::jsonb,
        headers := (
            '{"Content-Type": "application/json", "X-Cron-Secret": "' ||
            (SELECT value FROM internal_config WHERE key = 'cron_secret') ||
            '"}'
        )::jsonb
    )
    $$
);
