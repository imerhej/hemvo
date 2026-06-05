-- Add device_id to device_tokens so token rotation updates the row in-place
-- instead of inserting duplicates.
--
-- Previously the unique constraint was (user_id, token). When a token changed
-- (reinstall, iOS rotation) a new row was inserted. The notify-household Edge
-- Function sends one push per row, causing N duplicate notifications for a user
-- with N stale rows.
--
-- The new constraint is (user_id, device_id). The client sends identifierForVendor
-- as device_id, which is stable across reinstalls (resets only when ALL vendor apps
-- are uninstalled), so each physical install produces exactly one row.

-- Step 1: Clear all existing rows.
-- They will be re-registered on next app launch (refreshToken is called on every
-- loadFromSupabase, which runs on foreground and on a 15s timer in ScheduleViewModel).
DELETE FROM device_tokens;

-- Step 2: Add the device_id column.
ALTER TABLE device_tokens
    ADD COLUMN IF NOT EXISTS device_id TEXT NOT NULL DEFAULT '';

-- Step 3: Swap the unique constraint from (user_id, token) → (user_id, device_id).
ALTER TABLE device_tokens
    DROP CONSTRAINT IF EXISTS device_tokens_user_id_token_key;

ALTER TABLE device_tokens
    ADD CONSTRAINT device_tokens_user_id_device_id_key UNIQUE (user_id, device_id);
