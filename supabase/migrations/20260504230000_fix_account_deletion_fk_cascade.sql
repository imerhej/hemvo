-- Migration: fix_account_deletion_fk_cascade
-- The `delete_my_account` RPC deletes the auth.users row, but
-- households.owner_id holds a non-cascading FK to auth.users(id).
-- This causes: "update or delete on table "users" violates foreign key
-- constraint "household_owner_id_fkey" on table "households"".
--
-- Fix: rebuild every FK in the households dependency chain with the
-- correct ON DELETE behaviour so account deletion never violates a constraint.

-- ── 1. households.owner_id → auth.users(id)  ─────────────────────────────
-- CASCADE: deleting the auth user deletes their household.
ALTER TABLE households DROP CONSTRAINT IF EXISTS household_owner_id_fkey;
ALTER TABLE households
    ADD CONSTRAINT household_owner_id_fkey
    FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ── 2. events.household_id → households(id)  ─────────────────────────────
-- CASCADE: deleting the household deletes all its events.
ALTER TABLE events DROP CONSTRAINT IF EXISTS events_household_id_fkey;
ALTER TABLE events
    ADD CONSTRAINT events_household_id_fkey
    FOREIGN KEY (household_id) REFERENCES households(id) ON DELETE CASCADE;

-- ── 3. house_tasks.household_id → households(id)  ────────────────────────
-- CASCADE: deleting the household deletes all its tasks.
ALTER TABLE house_tasks DROP CONSTRAINT IF EXISTS house_tasks_household_id_fkey;
ALTER TABLE house_tasks
    ADD CONSTRAINT house_tasks_household_id_fkey
    FOREIGN KEY (household_id) REFERENCES households(id) ON DELETE CASCADE;

-- ── 4. profiles.household_id → households(id)  ───────────────────────────
-- SET NULL: when a household is deleted, members lose their household_id
-- gracefully (their profile row is preserved; the app detects null and
-- shows the "no household" state on next launch).
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_household_id_fkey;
ALTER TABLE profiles
    ADD CONSTRAINT profiles_household_id_fkey
    FOREIGN KEY (household_id) REFERENCES households(id) ON DELETE SET NULL;
