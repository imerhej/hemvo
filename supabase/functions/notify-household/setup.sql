-- Run this once in the Supabase SQL editor before deploying the Edge Function.

-- Table: device_tokens
-- Stores one row per (user, device) pair.
-- A user who uses two devices (iPhone + iPad) will have two rows.
CREATE TABLE IF NOT EXISTS device_tokens (
    id           UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    household_id UUID,
    token        TEXT        NOT NULL,
    device_id    TEXT        NOT NULL DEFAULT '',
    updated_at   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, device_id)
);

-- Keep updated_at current so we can prune stale tokens later.
CREATE OR REPLACE FUNCTION update_device_token_timestamp()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

CREATE OR REPLACE TRIGGER trg_device_tokens_updated_at
BEFORE INSERT OR UPDATE ON device_tokens
FOR EACH ROW EXECUTE FUNCTION update_device_token_timestamp();

-- RLS: users manage only their own tokens; service role reads all (for Edge Function).
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own tokens"
    ON device_tokens FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Service role reads all tokens"
    ON device_tokens FOR SELECT
    TO service_role USING (true);
