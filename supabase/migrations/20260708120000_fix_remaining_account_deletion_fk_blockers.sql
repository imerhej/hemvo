-- Migration: fix_remaining_account_deletion_fk_blockers
--
-- Account deletion (delete_my_account RPC → single DELETE on auth.users)
-- failed in production with:
--   "update or delete on table "users" violates foreign key constraint
--    "households_owner_id_fkey" on table "households""
--
-- Root cause: four FKs referencing auth.users(id) exist on the live DB with
-- the default NO ACTION delete behavior. None of them appear in any repo
-- migration — they were created outside the migration history (dashboard /
-- table editor), so the cascade sweeps in 20260504230000 and 20260626120000
-- never touched them:
--
--   households.owner_id        households_owner_id_fkey       ← duplicate of
--       the cascading household_owner_id_fkey added in 20260504230000; the
--       non-cascading twin blocks the delete even though the cascading one
--       would allow it.
--   events.assigned_to_id      events_assigned_to_id_fkey
--   house_tasks.assigned_to_id house_tasks_assigned_to_id_fkey
--   maintenance_items.created_by maintenance_items_created_by_fkey
--
-- Behavior choices follow the established design:
--   * assigned_to_id → ON DELETE SET NULL: rows created by *other* members but
--     assigned to the deleted user must survive, unassigned (rows the deleted
--     user created are already removed via the created_by CASCADE).
--   * created_by → ON DELETE CASCADE: same pattern as expenses, meals,
--     grocery_items, shopping_*, events, house_tasks in 20260626120000.
--
-- Uses IF EXISTS on drops so the migration is idempotent.

-- ── households.owner_id: drop the duplicate non-cascading FK ────────────────
-- household_owner_id_fkey (ON DELETE CASCADE) remains the single FK.
ALTER TABLE households DROP CONSTRAINT IF EXISTS households_owner_id_fkey;

-- ── events.assigned_to_id → auth.users(id) SET NULL ─────────────────────────
ALTER TABLE events DROP CONSTRAINT IF EXISTS events_assigned_to_id_fkey;

ALTER TABLE events
    ADD CONSTRAINT events_assigned_to_id_fkey
    FOREIGN KEY (assigned_to_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- ── house_tasks.assigned_to_id → auth.users(id) SET NULL ────────────────────
ALTER TABLE house_tasks DROP CONSTRAINT IF EXISTS house_tasks_assigned_to_id_fkey;

ALTER TABLE house_tasks
    ADD CONSTRAINT house_tasks_assigned_to_id_fkey
    FOREIGN KEY (assigned_to_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- ── maintenance_items.created_by → auth.users(id) CASCADE ───────────────────
ALTER TABLE maintenance_items DROP CONSTRAINT IF EXISTS maintenance_items_created_by_fkey;

ALTER TABLE maintenance_items
    ADD CONSTRAINT maintenance_items_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;
