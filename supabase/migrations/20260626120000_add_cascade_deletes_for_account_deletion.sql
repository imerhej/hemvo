-- Migration: add_cascade_deletes_for_account_deletion
--
-- Adds ON DELETE CASCADE to every FK that references auth.users(id) so the
-- delete_my_account RPC's single DELETE on auth.users atomically removes all
-- user-owned rows. Previously, AuthService.deleteAccount() manually looped
-- over 8 tables as a client-side safety net to avoid FK violations; those
-- explicit deletes are now redundant (the DB handles them).
--
-- Existing cascades (from 20260504230000_fix_account_deletion_fk_cascade.sql):
--   households.owner_id → auth.users(id)  CASCADE
--   events.household_id → households(id)  CASCADE
--   house_tasks.household_id → households(id)  CASCADE
--   profiles.household_id → households(id)  SET NULL
--
-- This migration closes the remaining gaps:
--   expenses, meals, grocery_items, shopping_items, shopping_lists,
--   device_tokens, and the direct created_by→auth.users paths on events
--   and house_tasks (covers rows created before a household was joined).
--
-- Uses IF EXISTS on drops so the migration is idempotent.

-- ── expenses.created_by → auth.users(id) ────────────────────────────────────
ALTER TABLE expenses DROP CONSTRAINT IF EXISTS expenses_created_by_fkey;
ALTER TABLE expenses
    ADD CONSTRAINT expenses_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ── meals.created_by → auth.users(id) ───────────────────────────────────────
ALTER TABLE meals DROP CONSTRAINT IF EXISTS meals_created_by_fkey;
ALTER TABLE meals
    ADD CONSTRAINT meals_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ── grocery_items.created_by → auth.users(id) ───────────────────────────────
ALTER TABLE grocery_items DROP CONSTRAINT IF EXISTS grocery_items_created_by_fkey;
ALTER TABLE grocery_items
    ADD CONSTRAINT grocery_items_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ── shopping_lists.created_by → auth.users(id) ──────────────────────────────
ALTER TABLE shopping_lists DROP CONSTRAINT IF EXISTS shopping_lists_created_by_fkey;
ALTER TABLE shopping_lists
    ADD CONSTRAINT shopping_lists_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ── shopping_items.created_by → auth.users(id) ──────────────────────────────
ALTER TABLE shopping_items DROP CONSTRAINT IF EXISTS shopping_items_created_by_fkey;
ALTER TABLE shopping_items
    ADD CONSTRAINT shopping_items_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ── device_tokens.user_id → auth.users(id) ──────────────────────────────────
ALTER TABLE device_tokens DROP CONSTRAINT IF EXISTS device_tokens_user_id_fkey;
ALTER TABLE device_tokens
    ADD CONSTRAINT device_tokens_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ── events.created_by → auth.users(id) ──────────────────────────────────────
-- Belt-and-suspenders: events also cascade via household_id → households, but
-- rows created before the user joined a household have household_id = NULL.
ALTER TABLE events DROP CONSTRAINT IF EXISTS events_created_by_fkey;
ALTER TABLE events
    ADD CONSTRAINT events_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ── house_tasks.created_by → auth.users(id) ─────────────────────────────────
-- Same rationale as events above.
ALTER TABLE house_tasks DROP CONSTRAINT IF EXISTS house_tasks_created_by_fkey;
ALTER TABLE house_tasks
    ADD CONSTRAINT house_tasks_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;
