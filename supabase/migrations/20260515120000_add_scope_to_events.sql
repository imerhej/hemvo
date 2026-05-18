-- Migration: add_scope_to_events
-- Adds a `scope` column ('Personal' | 'Household') to the events table so that
-- personal events are only visible to their creator and explicitly invited users.
--
-- RLS changes:
--   SELECT — household events: any household member; personal events: creator or invitee only.
--   UPDATE — same visibility rule (so an invitee can edit a personal event they were shared with).
--   INSERT/DELETE — unchanged (creator only).

-- ── 1. Add column ─────────────────────────────────────────────────────────────
ALTER TABLE events
  ADD COLUMN IF NOT EXISTS scope TEXT NOT NULL DEFAULT 'Household';

-- ── 2. Rebuild SELECT policy ──────────────────────────────────────────────────
DROP POLICY IF EXISTS "events_select" ON events;

CREATE POLICY "events_select"
  ON events FOR SELECT TO authenticated
  USING (
    -- Household events are visible to all household members.
    (
      scope = 'Household'
      AND household_id IN (
        SELECT household_id FROM profiles WHERE id = auth.uid()
      )
    )
    -- Personal events are visible to the creator …
    OR created_by = auth.uid()
    -- … and to anyone explicitly invited.
    OR auth.uid() = ANY(invitee_ids)
  );

-- ── 3. Rebuild UPDATE policy ──────────────────────────────────────────────────
-- Household events: any household member can edit.
-- Personal events: only the creator or an invitee can edit.
DROP POLICY IF EXISTS "events_update" ON events;

CREATE POLICY "events_update"
  ON events FOR UPDATE TO authenticated
  USING (
    (
      scope = 'Household'
      AND household_id IN (
        SELECT household_id FROM profiles WHERE id = auth.uid()
      )
    )
    OR created_by = auth.uid()
    OR auth.uid() = ANY(invitee_ids)
  )
  WITH CHECK (
    (
      scope = 'Household'
      AND household_id IN (
        SELECT household_id FROM profiles WHERE id = auth.uid()
      )
    )
    OR created_by = auth.uid()
    OR auth.uid() = ANY(invitee_ids)
  );
