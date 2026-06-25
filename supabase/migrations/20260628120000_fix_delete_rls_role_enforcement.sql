-- Migration: fix_delete_rls_role_enforcement
--
-- Problem: events_delete and house_tasks_delete were created_by-only, so
-- Owner/Adult could update others' items (per the existing update policies)
-- but could not delete them. This is an intentional decision: Owner/Adult
-- should have full content authority, matching the update policy split.
--
-- Fix: mirror the role split already in house_tasks_update and events_update:
--   Owner / Adult → may delete any item belonging to their household
--   Teen / solo   → may only delete items they created

-- ── events_delete ─────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "events_delete" ON events;

CREATE POLICY "events_delete"
  ON events FOR DELETE
  TO authenticated
  USING (
    -- Owner or Adult: full delete authority over household events
    household_id IN (
      SELECT household_id FROM profiles
      WHERE id = auth.uid()
        AND role IN ('Owner', 'Adult')
    )
    OR
    -- Teen or solo user: may only delete events they created
    created_by = auth.uid()
  );

-- ── house_tasks_delete ────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "house_tasks_delete" ON house_tasks;

CREATE POLICY "house_tasks_delete"
  ON house_tasks FOR DELETE
  TO authenticated
  USING (
    -- Owner or Adult: full delete authority over household tasks
    household_id IN (
      SELECT household_id FROM profiles
      WHERE id = auth.uid()
        AND role IN ('Owner', 'Adult')
    )
    OR
    -- Teen or solo user: may only delete tasks they created
    created_by = auth.uid()
  );
