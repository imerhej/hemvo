-- Stores per-user notification preferences in Supabase so they follow the
-- Hemvo account across devices, regardless of iCloud availability.
-- Default true matches the app's first-launch defaults.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS notif_bills       boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notif_meals       boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notif_schedule    boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notif_maintenance boolean NOT NULL DEFAULT true;
