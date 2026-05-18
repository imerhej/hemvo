-- Migration: cleanup_events_policies
-- The events table accumulated conflicting policies including an ALL policy
-- ("household members manage events") that allowed any household member to
-- UPDATE and DELETE events they didn't create, and to corrupt created_by.
--
-- Drop everything and apply the canonical 4-policy set.

-- ── Drop all existing events policies ─────────────────────────────────────
DROP POLICY IF EXISTS "events_delete"                   ON events;
DROP POLICY IF EXISTS "events_insert"                   ON events;
DROP POLICY IF EXISTS "events_select"                   ON events;
DROP POLICY IF EXISTS "events_update"                   ON events;
DROP POLICY IF EXISTS "creator_delete_events"           ON events;
DROP POLICY IF EXISTS "only creator can delete"         ON events;
DROP POLICY IF EXISTS "household members manage events" ON events;

-- ── Recreate canonical set ────────────────────────────────────────────────

-- Household members OR the creator can read events.
CREATE POLICY "events_select"
  ON events FOR SELECT
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
    OR created_by = auth.uid()
  );

-- Only authenticated users can insert; they must be the creator.
CREATE POLICY "events_insert"
  ON events FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());

-- Only the creator can update an event, and cannot change created_by.
CREATE POLICY "events_update"
  ON events FOR UPDATE
  TO authenticated
  USING     (created_by = auth.uid())
  WITH CHECK(created_by = auth.uid());

-- Only the creator can delete an event.
CREATE POLICY "events_delete"
  ON events FOR DELETE
  TO authenticated
  USING (created_by = auth.uid());
