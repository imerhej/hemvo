-- Backfill full_name and username for existing users whose profile rows
-- were created before the handle_new_user trigger fix (2026-05-24).
-- The old trigger did not read from raw_user_meta_data, so full_name and
-- username were left NULL for anyone who signed up before that date.
-- This migration reads both fields directly from auth.users and writes them
-- into profiles where the column is currently NULL or empty.

UPDATE public.profiles p
SET
  full_name = NULLIF(TRIM(u.raw_user_meta_data->>'full_name'), ''),
  username  = COALESCE(
                NULLIF(TRIM(u.raw_user_meta_data->>'username'), ''),
                p.username
              )
FROM auth.users u
WHERE p.id = u.id
  AND (
    p.full_name IS NULL
    OR p.full_name = ''
  )
  AND NULLIF(TRIM(u.raw_user_meta_data->>'full_name'), '') IS NOT NULL;
