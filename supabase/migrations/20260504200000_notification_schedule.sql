-- Migration: notification_schedule
-- Stores future push notifications that need to be sent at a specific time.
-- A cron Edge Function (process-scheduled-push) polls this table every minute
-- and delivers APNs pushes for any rows where fire_at <= now() and sent = false.
--
-- Used for:
--   • Event alert (e.g. "15 minutes before")  → fire_at = event.date - alert_offset
--   • Event start                              → fire_at = event.date

CREATE TABLE IF NOT EXISTS notification_schedule (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID        NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    event_id     UUID,                           -- nullable; links to events table
    fire_at      TIMESTAMPTZ NOT NULL,
    title        TEXT        NOT NULL,
    body         TEXT        NOT NULL DEFAULT '',
    sent         BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Efficient polling: only scan unsent rows ordered by fire time.
CREATE INDEX IF NOT EXISTS notification_schedule_pending_idx
    ON notification_schedule (fire_at)
    WHERE NOT sent;

-- RLS: the iOS client never reads or writes this table directly.
-- The process-scheduled-push Edge Function uses the service-role key, which
-- bypasses RLS entirely. No public policies are needed.
ALTER TABLE notification_schedule ENABLE ROW LEVEL SECURITY;
